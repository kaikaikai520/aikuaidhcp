# 爱快 DHCP 网关切换助手（Web 版）

一款自用的内网 Web 服务：浏览器访问一个地址，即可查看爱快（iKuai）路由器里
DHCP 静态分配的终端列表，并对每台终端在**预设的两个网关（A/B）之间一键切换**。

> 本项目为「爱快 DHCP 网关切换助手」的 Web 服务形态。

## 功能

- **连接配置**：填写爱快地址（IP:端口）、用户名、密码，是否 HTTPS。
- **终端列表**：拉取 DHCP 静态分配列表，展示设备名、IP、MAC、当前网关。
- **网关 A/B 一键切换**：预设两个网关，点开关即在 A/B 之间切换并即时提交到爱快。
- **配置持久化**：连接信息与网关预设保存到 `config.json`，重启自动加载。

## 快速开始

### 方式一：Docker（推荐，适合 NAS/软路由/Linux 常开设备）

```bash
cd web
docker compose up -d --build
```

浏览器访问 `http://<内网IP>:8000`。

配置文件会落盘到 `web/data/config.json`。

### 方式二：本地直接运行

需要 Python 3.9+：

```bash
cd web
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

浏览器访问 `http://<内网IP>:8000`。

## 使用步骤

1. 首次打开会进入配置页，填写爱快连接信息 + 网关 A/B，点「保存并连接」。
2. 连接成功后进入终端列表，每台终端右侧有一个开关：**关 = 网关 A，开 = 网关 B**。
3. 点开关即可切换，成功后列表自动刷新。

## 前置条件（爱快侧）

- 需要开启爱快 Web 管理权限的账号（默认 `admin`）。
- 需要先在爱快「网络设置 → DHCP设置 → DHCP静态分配」中为终端建立静态绑定记录
  （本工具切换的是这些记录的网关字段）。
- 爱快需支持「静态分配指定网关」——免费版 3.7.x 实测支持（chiphell / 什么值得买多帖确认）。

## 配置项

| 字段 | 说明 |
|------|------|
| `host` | 爱快管理地址，如 `192.168.1.1` |
| `port` | 端口，HTTP 默认 80 / HTTPS 默认 443 |
| `use_https` | 是否 HTTPS（忽略自签名证书） |
| `username` / `password` | 爱快登录凭据 |
| `gateway_a` / `gateway_b` | 两个预设网关地址 |

配置由 Web 页写入，也可手动编辑 `data/config.json`。

## REST API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/health` | 健康检查 |
| GET | `/api/config` | 读取配置 |
| POST | `/api/config` | 保存配置 |
| POST | `/api/login` | 测试/建立连接 |
| GET | `/api/devices` | 拉取终端列表 |
| POST | `/api/devices/{mac}/toggle` | 切换指定终端网关 |

## 目录结构

```
web/
├── app/
│   ├── main.py            # FastAPI 入口（路由 + 静态托管）
│   ├── ikuai_client.py    # 爱快 API 客户端（登录/会话/切换）
│   ├── config.py          # config.json 读写
│   └── schemas.py         # Pydantic 模型
├── static/
│   ├── index.html         # 单页前端
│   ├── app.js
│   └── style.css
├── tests/                 # pytest 单元测试
├── requirements.txt
├── Dockerfile
└── docker-compose.yml
```

## 运行测试

```bash
cd web
pip install -r requirements-dev.txt
python -m pytest
```

## 已知待确认点

- **爱快 DHCP 静态分配的网关字段名**：不同模块命名不一（`static_rt` 用 `gateway`，
  DHCP 相关常缩写 `gw`）。本实现默认用 `gw` 并做 `gw`/`gateway` 双字段兼容；
  若切换报错，抓取爱快 Web 后台「DHCP 静态分配」编辑请求的 `param` 确认字段名后，
  修改 `app/ikuai_client.py` 中的 `_set_gateway_field` 即可。
