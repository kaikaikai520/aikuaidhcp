"""配置存储（HiddenStore）单元测试。"""
import os

from app.config import HiddenStore


def _tmp_dir(tmp_path):
    return tmp_path


def test_hidden_empty(tmp_path):
    store = HiddenStore(tmp_path)
    assert store.load() == []


def test_hidden_add_and_load(tmp_path):
    store = HiddenStore(tmp_path)
    store.add("AA:BB:CC:DD:EE:FF")
    store.add("aa:bb:cc:dd:ee:ff")  # 重复应去重
    store.add("11:22:33:44:55:66")
    assert store.load() == ["aa:bb:cc:dd:ee:ff", "11:22:33:44:55:66"]


def test_hidden_remove(tmp_path):
    store = HiddenStore(tmp_path)
    store.add("AA:BB:CC:DD:EE:FF")
    store.remove("aa:bb:cc:dd:ee:ff")  # 大小写不敏感
    assert store.load() == []


def test_hidden_remove_missing_noop(tmp_path):
    store = HiddenStore(tmp_path)
    store.add("AA:BB:CC:DD:EE:FF")
    store.remove("00:00:00:00:00:00")
    assert store.load() == ["aa:bb:cc:dd:ee:ff"]


def test_hidden_persisted(tmp_path):
    store = HiddenStore(tmp_path)
    store.add("AA:BB:CC:DD:EE:FF")
    # 重新实例化读取，验证落盘
    store2 = HiddenStore(tmp_path)
    assert store2.load() == ["aa:bb:cc:dd:ee:ff"]
