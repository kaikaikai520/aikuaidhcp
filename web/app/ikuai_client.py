"""爱快（iKuai）路由器 API 客户端（Python 移植版）。

将原 Flutter 版 `IkuaiClient` 的核心逻辑移植为 Python 实现：
登录认证（MD5 + Base64 + salt 多版本重试）、会话管理、通用调用、
DHCP 静态分配列表读取、网关 A/B 切换、字段兼容。

爱快 API 关键结论（联调实测）：
- 登录：`POST /Action/login`，body `{username, passwd: MD5(密码), pass: Base64(salt+密码), remember_password: null}`。
  - 字段是 `username`（非 user_name）；`passwd`=md5(密码)，`pass`=base64(salt前缀+密码)。
  - salt 前缀随固件变化（salt_123 / salt_113 / salt_11 / salt_13 …），逐个尝试。
- 业务：`POST /Action/call`，body `{func_name, action, param}`。
  - **成功判断（关键坑）**：不是看 `Result` 码，而是 `ErrMsg=="Success"`（旧版）或 `code==0`（企业版 4.x）；
    部分固件 `/Action/call` 响应不含 `Result` 字段，需综合判断 `Result==10000 || code==0 || ErrMsg=="Success"`。
  - 列表数据容器：旧版 `Data`、企业版 `results`；内层字段 `data`/`result` 等，需多字段兼容。
- DHCP 静态绑定：`func_name=dhcp_static`（不是 `dhcp_addr_bind`）；读=show(`{"TYPE":"total,data","limit":"0,500"}`)；
  写=add/edit（param 为平铺字段，不要 `{"data":{}}` 包装）。字段：mac、ip_addr、comment、dns1/dns2（3.7.12+）。
  - **网关字段名待确认**：爱快不同模块命名不一（`static_rt` 用 `gateway`，DHCP 相关常缩写 `gw`），
    逆向项目 gxxHuang 的 dhcp_static `add` 未覆盖网关字段，本实现默认用 `gw` 并做双字段兼容。
- 会话：登录后 `sess_key` cookie；会话过期码 10001，自动重登重试一次。
"""
from __future__ import annotations

import base64
import hashlib
import json
from typing import Any, Optional

import requests
import urllib3

# 忽略自签名证书告警（爱快默认自签名 HTTPS）
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)


class IkuaiError(Exception):
    """爱快 API 异常，携带错误码与可读信息。"""

    def __init__(self, code: int, message: str):
        self.code = code
        self.message = message
        super().__init__(f"[{code}] {message}")


# ---- 认证编码工具（纯函数，便于单元测试）----


def md5_password(password: str) -> str:
    """`MD5(明文密码)`，返回 32 位小写十六进制。"""
    return hashlib.md5(password.encode("utf-8")).hexdigest()


def encode_pass(password: str, salt: str) -> str:
    """`Base64(salt 前缀 + 明文密码)`。"""
    return base64.b64encode(f"{salt}{password}".encode("utf-8")).decode("ascii")


def encode_credentials(password: str, salt: str) -> tuple[str, str]:
    """返回 `(passwd, pass)` 元组，供登录请求体使用。"""
    return md5_password(password), encode_pass(password, salt)


# ---- 网关 A/B 决策（纯函数）----


def decide_target_gateway(current: str, gateway_a: str, gateway_b: str) -> str:
    """当前网关 == B → 切到 A；其余（含无法匹配）按「当前≈A」处理，切到 B。"""
    if current == gateway_b:
        return gateway_a
    return gateway_b


# ---- 字段兼容工具 ----


def get_field(item: dict, *keys: str) -> str:
    """按优先级取字段，返回非空字符串；兼容爱快多字段命名。"""
    for key in keys:
        value = item.get(key)
        if value is not None and str(value).strip() != "":
            return str(value).strip()
    return ""


class IkuaiClient:
    """爱快 API 客户端（网络层），只负责「与爱快通信」，不掺杂业务判断。"""

    DEFAULT_SALT_LIST = ["salt_123", "salt_113", "salt_11", "salt_13"]
    SUCCESS_CODE = 10000
    SESSION_EXPIRED_CODE = 10001

    def __init__(
        self,
        host: str,
        port: int = 80,
        username: str = "",
        password: str = "",
        use_https: bool = False,
        salt_list: Optional[list[str]] = None,
        timeout: int = 20,
    ):
        self.host = host
        self.port = int(port)
        self.username = username
        self.password = password
        self.use_https = use_https
        self.salt_list = salt_list or self.DEFAULT_SALT_LIST
        self.timeout = timeout

        self.session = requests.Session()
        self.session.verify = False  # 忽略自签名证书
        self._logging_in = False
        self._logged_in = False

    # ---- 基础属性 ----

    @property
    def base_url(self) -> str:
        scheme = "https" if self.use_https else "http"
        return f"{scheme}://{self.host}:{self.port}"

    # ---- 登录 ----

    def ensure_login(self) -> None:
        """仅在未登录时执行登录；已登录则跳过（会话过期由 call 自动重登）。"""
        if not self._logged_in:
            self.login()

    def login(self) -> None:
        if self._logging_in:
            return
        self._logging_in = True
        try:
            errors: list[str] = []
            for salt in self.salt_list:
                try:
                    self._try_login(salt)
                    self._logged_in = True
                    return
                except IkuaiError as exc:
                    errors.append(f"[{salt}] {exc.message}")
            raise IkuaiError(401, "登录失败：" + "；".join(errors))
        finally:
            self._logging_in = False

    def _try_login(self, salt: str) -> None:
        passwd, pass_ = encode_credentials(self.password, salt)
        body = {
            "username": self.username,
            "passwd": passwd,
            "pass": pass_,
            "remember_password": None,
        }
        data = self._post("/Action/login", body)
        if not self._is_success(data):
            raise IkuaiError(
                self._extract_result(data),
                self._extract_err_msg(data) or "登录失败",
            )
        self._store_session(data)

    # ---- 通用调用 ----

    def call(self, func_name: str, action: str, param: Optional[dict] = None) -> Any:
        body = {"func_name": func_name, "action": action, "param": param or {}}
        data = self._post("/Action/call", body)
        if self._is_session_expired(data):
            self._logged_in = False
            self.login()
            data = self._post("/Action/call", body)
        if not self._is_success(data):
            raise IkuaiError(
                self._extract_result(data),
                self._extract_err_msg(data) or f"调用失败（原始返回：{self._summarize(data)}）",
            )
        return data

    def _post(self, path: str, body: dict) -> Any:
        try:
            resp = self.session.post(f"{self.base_url}{path}", json=body, timeout=self.timeout)
        except requests.RequestException as exc:
            raise IkuaiError(503, f"无法连接路由器：{exc}") from exc
        return self._to_json(resp)

    # ---- DHCP 静态分配 ----

    def get_dhcp_bindings(self) -> list[dict]:
        """读取 DHCP 静态分配列表（原始字段）。"""
        data = self.call("dhcp_static", "show", {"TYPE": "total,data", "limit": "0,500"})
        return self._extract_list(data)

    def save_dhcp_binding(self, item: dict, is_edit: bool) -> None:
        """新增或编辑一条 DHCP 静态绑定记录（平铺字段）。"""
        self.call("dhcp_static", "edit" if is_edit else "add", item)

    # ---- 切换网关（业务编排）----

    def toggle_gateway(self, mac: str, gateway_a: str, gateway_b: str) -> tuple[str, str]:
        """切换指定终端的网关，返回 `(原网关, 新网关)`。"""
        bindings = self.get_dhcp_bindings()
        target: Optional[dict] = None
        for item in bindings:
            if get_field(item, "mac").lower() == mac.lower():
                target = item
                break
        if target is None:
            raise IkuaiError(404, f"未找到该终端的静态绑定记录（MAC: {mac}）")

        current = get_field(target, "gw", "gateway")
        new_gateway = decide_target_gateway(current, gateway_a, gateway_b)

        updated = dict(target)
        self._set_gateway_field(updated, new_gateway)
        self.save_dhcp_binding(updated, is_edit=True)
        return current, new_gateway

    @staticmethod
    def _set_gateway_field(item: dict, gateway: str) -> None:
        """设置网关字段。爱快 dhcp_static 网关字段名待确认（gw vs gateway），默认 `gw`。"""
        item.pop("gateway", None)
        item["gw"] = gateway

    # ---- 解析工具 ----

    @staticmethod
    def _to_json(resp: requests.Response) -> Any:
        try:
            return resp.json()
        except ValueError:
            text = resp.text or ""
            # 部分固件响应带 "sending to kernel" 前缀
            if text.startswith("sending to kernel"):
                text = text.replace("sending to kernel", "", 1).strip()
            try:
                return json.loads(text)
            except ValueError:
                return {"raw": text}

    @staticmethod
    def _extract_result(data: Any) -> int:
        if isinstance(data, dict):
            for key in ("Result", "result", "code", "Code", "ret"):
                if key not in data:
                    continue
                value = data[key]
                if isinstance(value, bool):
                    continue
                if isinstance(value, int):
                    return value
                if isinstance(value, float):
                    return int(value)
                if isinstance(value, str):
                    try:
                        return int(value)
                    except ValueError:
                        pass
        return -1

    @classmethod
    def _is_success(cls, data: Any) -> bool:
        result = cls._extract_result(data)
        if result in (cls.SUCCESS_CODE, 0):
            return True
        msg = cls._extract_err_msg(data)
        return msg is not None and msg.strip().lower() == "success"

    @staticmethod
    def _extract_err_msg(data: Any) -> Optional[str]:
        if isinstance(data, dict):
            for key in ("ErrMsg", "errmsg", "ErrorMsg", "error_msg", "message", "msg"):
                if key in data and data[key] is not None:
                    return str(data[key])
        return None

    @staticmethod
    def _summarize(data: Any) -> str:
        try:
            text = json.dumps(data, ensure_ascii=False)
        except (TypeError, ValueError):
            text = str(data)
        return text if len(text) <= 200 else text[:200] + "…"

    @classmethod
    def _is_session_expired(cls, data: Any) -> bool:
        if not isinstance(data, dict):
            return True
        if cls._extract_result(data) == cls.SESSION_EXPIRED_CODE:
            return True
        msg = (cls._extract_err_msg(data) or "").lower()
        return any(k in msg for k in ("no login", "未登录", "expired", "过期"))

    def _store_session(self, data: Any) -> None:
        """优先用 Set-Cookie（Session 已自动保存）；若响应体含 sess_key 则补存。"""
        if isinstance(data, dict):
            for key in ("sess_key", "SessionKey", "session_key", "sesskey"):
                value = data.get(key)
                if value:
                    self.session.cookies.set("sess_key", str(value))
                    return

    @staticmethod
    def _extract_list(data: Any) -> list[dict]:
        lst = None
        if isinstance(data, list):
            lst = data
        elif isinstance(data, dict):
            container = None
            for key in ("Data", "data", "result", "results", "list", "items", "rows"):
                if key in data:
                    container = data[key]
                    break
            if isinstance(container, list):
                lst = container
            elif isinstance(container, dict):
                for key in ("data", "result", "results", "list", "items", "rows"):
                    if isinstance(container.get(key), list):
                        lst = container[key]
                        break
        if not isinstance(lst, list):
            return []
        return [dict(e) for e in lst if isinstance(e, dict)]
