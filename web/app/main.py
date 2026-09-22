"""爱快 DHCP 网关切换助手 - Web 服务入口。

浏览器访问 `http://<内网IP>:8000` 即可使用。
提供 REST API 并托管前端静态页面。
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from .config import ConfigStore, HiddenStore
from .ikuai_client import IkuaiClient, IkuaiError, get_field
from .schemas import ConfigIn, DeviceOut, ToggleResult

STATIC_DIR = Path(__file__).resolve().parent.parent / "static"

app = FastAPI(title="爱快 DHCP 网关切换助手", version="0.2.0")

store = ConfigStore()
hidden_store = HiddenStore()
_client: Optional[IkuaiClient] = None


@app.middleware("http")
async def _no_cache_static(request, call_next):
    """静态资源与首页禁用缓存，避免改版后浏览器继续用旧 JS/CSS。"""
    response = await call_next(request)
    path = request.url.path
    if path.startswith("/static/") or path == "/":
        response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        response.headers["Pragma"] = "no-cache"
    return response


def _get_client() -> IkuaiClient:
    """按当前配置懒加载客户端；配置变更时重建。"""
    global _client
    cfg = store.load()
    if not cfg.get("host"):
        raise HTTPException(status_code=400, detail="尚未配置路由器连接信息")
    if (
        _client is None
        or _client.host != cfg.get("host")
        or int(_client.port) != int(cfg.get("port", 80))
        or _client.username != cfg.get("username", "")
        or _client.password != cfg.get("password", "")
        or _client.use_https != bool(cfg.get("use_https", False))
    ):
        _client = IkuaiClient(
            host=cfg["host"],
            port=int(cfg.get("port", 80)),
            username=cfg.get("username", ""),
            password=cfg.get("password", ""),
            use_https=bool(cfg.get("use_https", False)),
        )
    return _client


def _require_gateways(cfg: dict) -> tuple[str, str]:
    """校验并返回网关 A/B，未配置则抛 400。"""
    gateway_a = (cfg.get("gateway_a") or "").strip()
    gateway_b = (cfg.get("gateway_b") or "").strip()
    if not gateway_a or not gateway_b:
        raise HTTPException(status_code=400, detail="请先配置网关 A/B")
    return gateway_a, gateway_b


@app.get("/api/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/api/config")
def get_config() -> dict:
    return store.load()


@app.post("/api/config")
def save_config(cfg: ConfigIn) -> dict:
    global _client
    _client = None  # 配置变更，重置客户端
    store.save(cfg.model_dump())
    return {"ok": True}


@app.post("/api/login")
def login() -> dict:
    client = _get_client()
    try:
        client.login()
    except IkuaiError as exc:
        raise HTTPException(status_code=400, detail=exc.message) from exc
    return {"ok": True}


@app.get("/api/devices")
def list_devices() -> dict:
    client = _get_client()
    cfg = store.load()
    gateway_a, gateway_b = _require_gateways(cfg)

    try:
        client.ensure_login()
        bindings = client.get_dhcp_bindings()
    except IkuaiError as exc:
        raise HTTPException(status_code=400, detail=exc.message) from exc

    hidden_macs = set(hidden_store.load())
    devices = []
    for item in bindings:
        mac = get_field(item, "mac")
        name = get_field(item, "name", "hostname", "comment", "remark")
        ip = get_field(item, "ip", "ip_addr")
        gateway = get_field(item, "gateway", "gw")
        devices.append(
            DeviceOut(
                mac=mac,
                name=name or mac,
                ip=ip,
                gateway=gateway,
                is_a=bool(gateway and gateway == gateway_a),
                is_b=bool(gateway and gateway == gateway_b),
                hidden=(mac.lower() in hidden_macs),
            ).model_dump()
        )
    return {"devices": devices}


@app.post("/api/devices/{mac}/toggle", response_model=ToggleResult)
def toggle(mac: str) -> ToggleResult:
    client = _get_client()
    cfg = store.load()
    gateway_a, gateway_b = _require_gateways(cfg)

    try:
        client.ensure_login()
        old, new = client.toggle_gateway(mac, gateway_a, gateway_b)
    except IkuaiError as exc:
        raise HTTPException(status_code=400, detail=exc.message) from exc
    return ToggleResult(mac=mac, old_gateway=old, new_gateway=new)


@app.post("/api/devices/{mac}/hide")
def hide_device(mac: str) -> dict:
    """隐藏指定终端（后续列表默认不显示）。"""
    hidden_store.add(mac)
    return {"ok": True}


@app.post("/api/devices/{mac}/unhide")
def unhide_device(mac: str) -> dict:
    """取消隐藏指定终端。"""
    hidden_store.remove(mac)
    return {"ok": True}


@app.get("/")
def index() -> FileResponse:
    return FileResponse(STATIC_DIR / "index.html")


# 静态资源挂载（放在最后，避免覆盖 /api 路由）
app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
