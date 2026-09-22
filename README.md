# 爱快 DHCP 网关切换助手（aikuaidhcp）

一款部署在**内网**的轻量 Web 工具：浏览器打开一个地址，即可查看爱快（iKuai）路由器里
DHCP 静态分配的终端列表，并对每台终端在**预设的两个网关（A/B）之间一键切换**。

典型用途：让某台设备（机顶盒、NAS、测试机等）在主网关和旁路由网关之间快速切换，
不用再登录爱快后台层层点击。

## 功能

- **路由器连接配置**：填写爱快管理地址（IP:端口）、用户名、密码，可选 HTTPS（自动忽略自签名证书）。
- **终端列表**：从爱快拉取 DHCP 静态分配列表，展示设备名、IP、MAC、当前网关，并标出当前处于 A 侧还是 B 侧。
- **网关 A/B 一键切换**：每台终端右侧一个开关，**关 = 网关 A，开 = 网关 B**，点击即切换并实时写回爱快。
- **终端隐藏**：终端太多时，可把不常切换的设备「隐藏」，列表默认只显示未隐藏的终端；点顶部「隐藏的终端」可随时查看并恢复。
- **配置持久化**：连接信息与网关预设保存到服务端 `config.json`，服务重启后自动加载，无需重复填写。
- **会话管理**：登录采用爱快认证协议（MD5 密码 + Base64 salt，多版本自动重试），会话过期自动重新登录。
- **移动端友好**：单页响应式界面，手机、电脑浏览器直接可用，无需安装 App。

## 使用步骤

1. 首次打开网页进入「设置」页，填写爱快连接信息 + 网关 A / 网关 B，点「保存并连接」。
2. 连接成功后进入终端列表，看到所有 DHCP 静态分配终端及其当前网关。
3. 点某台终端的 A/B 开关即完成切换，成功后列表自动刷新。
4. 终端太多时，点某台设备右侧的「隐藏」把它收起；需要时点顶部「隐藏的终端 (N)」再「恢复」。
5. 顶栏「⚙ 设置」可随时修改连接信息或网关 A/B。

## 部署方式

### 方式一：拉取预构建镜像（推荐，NAS / 群晖 / 任意装 Docker 的设备）

镜像由 GitHub Actions 自动构建并推送到 Docker Hub（`dehua/aikuaidhcp`），设备上**无需构建**，直接拉取运行：

```bash
cd web
docker compose -f docker-compose.pull.yml up -d
```

或在「Docker 应用 → Compose」里直接粘贴 `docker-compose.pull.yml` 内容部署。

浏览器访问 `http://<设备内网IP>:8000` 即可。

- 配置自动落盘到 `web/data/`（已挂载为容器卷 `/data`，容器重建不丢失）。
- 容器已设置 `restart: unless-stopped`，开机自启。

### 方式二：本地构建部署（开发 / 需自行改代码时）

```bash
cd web
docker compose up -d --build
```

### 方式三：本地直接运行（开发 / 临时使用）

需要 Python 3.9+：

```bash
cd web
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

浏览器访问 `http://<本机内网IP>:8000`。

> 提示：`--host 0.0.0.0` 让服务监听所有网卡，内网其他设备才能访问；仅本机使用可改成 `127.0.0.1`。

## 前置条件（爱快侧）

- 一个具备爱快 Web 管理权限的账号（默认 `admin`）。
- 需要先在爱快「网络设置 → DHCP设置 → DHCP静态分配」中为终端建立**静态绑定记录**（本工具切换的正是这些记录里的网关字段）。
- 爱快需支持「静态分配指定网关」——免费版 3.7.x 实测支持。

## 配置项

| 字段 | 说明 |
|------|------|
| `host` | 爱快管理地址，如 `192.168.1.1` |
| `port` | 端口，HTTP 默认 80 / HTTPS 默认 443 |
| `use_https` | 是否使用 HTTPS |
| `username` / `password` | 爱快登录凭据 |
| `gateway_a` / `gateway_b` | 两个预设网关地址 |

配置由 Web 页面写入，也可手动编辑 `web/data/config.json`。

## 目录结构

```
web/
├── app/
│   ├── main.py            # FastAPI 入口（REST 路由 + 静态托管）
│   ├── ikuai_client.py    # 爱快 API 客户端（登录/会话/网关切换）
│   ├── config.py          # config.json / hidden.json 读写
│   └── schemas.py         # Pydantic 数据模型
├── static/                # 单页前端（HTML + 原生 JS + CSS，无构建步骤）
├── tests/                 # pytest 单元测试
├── requirements.txt       # 运行依赖
├── requirements-dev.txt   # 测试依赖
├── Dockerfile
└── docker-compose.yml
```

## REST API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/health` | 健康检查 |
| GET | `/api/config` | 读取配置 |
| POST | `/api/config` | 保存配置 |
| POST | `/api/login` | 建立/测试连接 |
| GET | `/api/devices` | 拉取终端列表 |
| POST | `/api/devices/{mac}/toggle` | 切换指定终端的网关 |
| POST | `/api/devices/{mac}/hide` | 隐藏指定终端 |
| POST | `/api/devices/{mac}/unhide` | 恢复显示指定终端 |

## 运行测试

```bash
cd web
pip install -r requirements-dev.txt
python -m pytest
```

## 文档

- 产品设计：`docs/PRD.md`
- 技术方案：`docs/TECH_DESIGN.md`
- Web 服务说明：`web/README.md`
