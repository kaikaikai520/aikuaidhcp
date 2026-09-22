"""Pydantic 请求/响应模型。"""
from __future__ import annotations

from pydantic import BaseModel, Field


class ConfigIn(BaseModel):
    """路由器连接配置（写入/读取共用）。"""

    host: str = Field(..., description="爱快地址，如 192.168.1.1")
    port: int = Field(80, ge=1, le=65535)
    use_https: bool = False
    username: str = ""
    password: str = ""
    gateway_a: str = Field("", description="网关 A")
    gateway_b: str = Field("", description="网关 B")


class DeviceOut(BaseModel):
    """终端设备（列表项）。"""

    mac: str
    name: str
    ip: str
    gateway: str
    is_a: bool
    is_b: bool


class ToggleResult(BaseModel):
    """切换结果。"""

    mac: str
    old_gateway: str
    new_gateway: str
