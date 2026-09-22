"""爱快客户端核心逻辑单元测试。

覆盖：认证编码（MD5/Base64）、A/B 决策、成功判断兼容、字段兼容、
列表提取、请求参数组装、切换编排。
"""
import base64
import json
from unittest import mock

import pytest

from app.ikuai_client import (
    IkuaiClient,
    IkuaiError,
    decide_target_gateway,
    encode_credentials,
    encode_pass,
    get_field,
    md5_password,
)


# ---- 认证编码 ----


def test_md5_password():
    assert md5_password("admin") == "21232f297a57a5a743894a0e4a801fc3"


def test_encode_pass():
    expected = base64.b64encode("salt_11123456".encode("utf-8")).decode("ascii")
    assert encode_pass("123456", "salt_11") == expected


def test_encode_credentials():
    passwd, pass_ = encode_credentials("admin", "salt_11")
    assert passwd == md5_password("admin")
    assert pass_ == encode_pass("admin", "salt_11")


# ---- A/B 决策 ----


def test_decide_target_gateway_b_to_a():
    assert decide_target_gateway("2.2.2.2", "1.1.1.1", "2.2.2.2") == "1.1.1.1"


def test_decide_target_gateway_a_to_b():
    assert decide_target_gateway("1.1.1.1", "1.1.1.1", "2.2.2.2") == "2.2.2.2"


def test_decide_target_gateway_unknown_to_b():
    assert decide_target_gateway("", "1.1.1.1", "2.2.2.2") == "2.2.2.2"


# ---- 成功判断兼容 ----


def test_is_success_result_10000():
    assert IkuaiClient._is_success({"Result": 10000}) is True


def test_is_success_code_0():
    assert IkuaiClient._is_success({"code": 0}) is True


def test_is_success_errmsg_success_no_result():
    assert IkuaiClient._is_success({"ErrMsg": "Success"}) is True


def test_is_success_false():
    assert IkuaiClient._is_success({"Result": -1, "ErrMsg": "error"}) is False


# ---- 字段兼容 ----


def test_get_field_multi():
    item = {"name": "NAS", "ip_addr": "10.0.0.2", "gw": "10.0.0.1"}
    assert get_field(item, "name", "hostname", "comment") == "NAS"
    assert get_field(item, "ip", "ip_addr") == "10.0.0.2"
    assert get_field(item, "gw", "gateway") == "10.0.0.1"


def test_get_field_empty_fallback():
    assert get_field({}, "a", "b") == ""
    assert get_field({"a": ""}, "a", "b") == ""


# ---- 列表提取 ----


def test_extract_list_data():
    assert IkuaiClient._extract_list({"Data": [{"mac": "aa:bb"}]}) == [{"mac": "aa:bb"}]


def test_extract_list_results():
    assert IkuaiClient._extract_list({"results": [{"mac": "aa:bb"}]}) == [{"mac": "aa:bb"}]


def test_extract_list_nested_data():
    assert IkuaiClient._extract_list({"Data": {"data": [{"mac": "aa:bb"}]}}) == [
        {"mac": "aa:bb"}
    ]


def test_extract_list_empty():
    assert IkuaiClient._extract_list({}) == []
    assert IkuaiClient._extract_list({"Data": None}) == []


# ---- 请求组装（mock）----


class FakeResponse:
    def __init__(self, data):
        self._data = data
        self.cookies = {}
        self.text = json.dumps(data)

    def json(self):
        return self._data


def make_client():
    return IkuaiClient(host="192.168.1.1", username="admin", password="admin")


def test_login_posts_correct_body():
    client = make_client()
    with mock.patch.object(client.session, "post") as post:
        post.return_value = FakeResponse({"Result": 10000, "ErrMsg": "Success"})
        client.login()
        path = post.call_args.args[0]
        body = post.call_args.kwargs["json"]
        assert path.endswith("/Action/login")
        assert body["username"] == "admin"
        assert body["passwd"] == md5_password("admin")
        # 首个 salt 即成功，pass = base64(salt_123 + 密码)
        assert body["pass"] == encode_pass("admin", "salt_123")


def test_login_fails_all_salts():
    client = make_client()
    with mock.patch.object(client.session, "post") as post:
        post.return_value = FakeResponse({"Result": -1, "ErrMsg": "bad"})
        with pytest.raises(IkuaiError) as exc:
            client.login()
        assert exc.value.code == 401


def test_get_dhcp_bindings_params():
    client = make_client()
    client._logged_in = True
    with mock.patch.object(client.session, "post") as post:
        post.return_value = FakeResponse({"ErrMsg": "Success", "Data": []})
        client.get_dhcp_bindings()
        body = post.call_args.kwargs["json"]
        assert body["func_name"] == "dhcp_static"
        assert body["action"] == "show"
        assert body["param"] == {"TYPE": "total,data", "limit": "0,500"}


def test_save_dhcp_binding_edit():
    client = make_client()
    client._logged_in = True
    with mock.patch.object(client.session, "post") as post:
        post.return_value = FakeResponse({"ErrMsg": "Success"})
        client.save_dhcp_binding({"mac": "aa", "ip_addr": "10.0.0.2"}, is_edit=True)
        body = post.call_args.kwargs["json"]
        assert body["action"] == "edit"


def test_toggle_gateway():
    client = make_client()
    client._logged_in = True
    show_resp = FakeResponse(
        {
            "ErrMsg": "Success",
            "Data": [
                {
                    "mac": "AA:BB:CC:DD:EE:FF",
                    "ip_addr": "10.0.0.2",
                    "gw": "1.1.1.1",
                    "comment": "NAS",
                }
            ],
        }
    )
    edit_resp = FakeResponse({"ErrMsg": "Success"})
    with mock.patch.object(
        client.session, "post", side_effect=[show_resp, edit_resp]
    ) as post:
        old, new = client.toggle_gateway("aa:bb:cc:dd:ee:ff", "1.1.1.1", "2.2.2.2")
        assert old == "1.1.1.1"
        assert new == "2.2.2.2"
        edit_body = post.call_args_list[1].kwargs["json"]
        assert edit_body["action"] == "edit"
        assert edit_body["param"]["gw"] == "2.2.2.2"


def test_toggle_gateway_not_found():
    client = make_client()
    client._logged_in = True
    show_resp = FakeResponse({"ErrMsg": "Success", "Data": []})
    with mock.patch.object(client.session, "post", return_value=show_resp):
        with pytest.raises(IkuaiError) as exc:
            client.toggle_gateway("aa:bb:cc:dd:ee:ff", "1.1.1.1", "2.2.2.2")
        assert exc.value.code == 404
