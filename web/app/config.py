"""配置管理：读写 `config.json`（爱快连接信息 + 网关 A/B 预设）。"""
from __future__ import annotations

import json
import os
import threading
from pathlib import Path
from typing import Optional


def default_data_dir() -> Path:
    """数据目录：优先环境变量 `DATA_DIR`，否则 `web/data`。"""
    env = os.environ.get("DATA_DIR")
    if env:
        return Path(env)
    return Path(__file__).resolve().parent.parent / "data"


class ConfigStore:
    """线程安全的 `config.json` 读写。"""

    def __init__(self, data_dir: Optional[Path] = None):
        self.data_dir = data_dir or default_data_dir()
        self._lock = threading.Lock()
        self._path = self.data_dir / "config.json"

    def load(self) -> dict:
        with self._lock:
            if not self._path.exists():
                return {}
            try:
                return json.loads(self._path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                return {}

    def save(self, config: dict) -> None:
        with self._lock:
            self.data_dir.mkdir(parents=True, exist_ok=True)
            tmp = self._path.with_suffix(".tmp")
            tmp.write_text(
                json.dumps(config, ensure_ascii=False, indent=2), encoding="utf-8"
            )
            tmp.replace(self._path)
