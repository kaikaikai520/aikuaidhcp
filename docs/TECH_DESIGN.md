# 技术方案：爱快 DHCP 网关切换助手（aikuaidhcp，Web 服务版）

> 版本：v0.2
> 对应产品设计文档：`docs/PRD.md`
> 更新日期：2026-09-22

## 1. 技术选型

| 类别 | 选型 | 理由 |
|------|------|------|
| 后端框架 | FastAPI（Python 3.9+） | 轻量、异步友好、自动生成 OpenAPI 文档，适合自用内网工具 |
| HTTP 客户端 | requests | 会话（Session）自动管理 cookie，配合忽略自签名证书，逻辑简单 |
| 数据校验 | pydantic v2 | FastAPI 内置，请求/响应模型校验 |
| 前端 | 原生 HTML + CSS + JS | 无构建步骤、无 CDN 依赖（内网可能无外网），移动端响应式 |
| 部署 | Docker + docker-compose | 一键部署到 NAS/软路由/Linux 常开设备，配置数据卷持久化 |
| 测试 | pytest + unittest.mock | 纯函数与请求组装逻辑的单元测试 |

## 2. 总体架构

从「客户端直连」改为「浏览器 → 后端 → 爱快」的三段式：

```
浏览器 ──HTTP──> Web 后端(FastAPI, 内网机器) ──HTTP──> 爱快路由器
   │                    │
   └── 静态页面/交互      ├── 登录认证、会话管理
                        ├── DHCP 静态分配读写
                        ├── 网关 A/B 切换编排
                        └── 配置持久化(config.json)
```

后端内部仍保持职责分层：

```
┌─────────────────────────────────────────────┐
│  路由层（main.py）                           │  REST API + 静态托管
├─────────────────────────────────────────────┤
│  客户端层（ikuai_client.py）                 │  爱快 HTTP API、会话管理、认证、切换编排
├─────────────────────────────────────────────┤
│  配置层（config.py）                         │  config.json 读写（连接信息 + 网关预设）
└─────────────────────────────────────────────┘
```

**分层原则**：

- 路由层只做参数校验、调用客户端、组装响应，不掺业务细节。
- 客户端层只负责「与爱快通信」，包含会话管理与网关切换编排。
- 配置层只负责配置文件的线程安全读写。
- 纯函数（认证编码、A/B 决策、字段兼容）独立导出，便于单元测试。

## 3. 项目结构

```
web/
├── app/
│   ├── __init__.py
│   ├── main.py            # FastAPI 入口（路由 + 静态托管）
│   ├── ikuai_client.py    # 爱快 API 客户端（登录/会话/切换/字段兼容）
│   ├── config.py          # config.json 读写
│   └── schemas.py         # Pydantic 模型
├── static/
│   ├── index.html         # 单页前端（配置页 + 列表页 + 设置）
│   ├── app.js
│   └── style.css
├── tests/
│   └── test_ikuai_client.py
├── conftest.py            # 确保 `import app` 可用
├── requirements.txt
├── requirements-dev.txt
├── Dockerfile
├── docker-compose.yml
├── .dockerignore
├── config.example.json
└── README.md
```

## 4. 核心模块设计

### 4.1 爱快 API 客户端（IkuaiClient）

这是整个产品的技术核心，负责与爱快路由器通信。

**职责**：登录认证、会话管理、通用调用、会话过期自动重登、网关切换编排。

**关键方法**：

| 方法 | 说明 |
|------|------|
| `login()` | 逐个尝试 salt → 计算凭据 → 登录 → 保存 sess_key |
| `ensure_login()` | 仅在未登录时登录；会话过期由 `call()` 自动重登 |
| `call(func_name, action, param)` | 带会话 cookie 调用 `/Action/call` |
| `get_dhcp_bindings()` | 读取 DHCP 静态分配列表 |
| `toggle_gateway(mac, a, b)` | 切换指定终端的网关，返回 (原网关, 新网关) |

**认证流程**（爱快本地 API 的登录机制，联调实测）：

1. `passwd = MD5(明文密码)`。
2. `pass = Base64(salt 前缀 + 明文密码)`。
3. `POST /Action/login`，body `{username, passwd, pass, remember_password: null}`。
4. salt 前缀随固件版本变化（`salt_123` / `salt_113` / `salt_11` / `salt_13`），逐个尝试直到成功。
5. 成功后从 Set-Cookie 或响应体 `sess_key` 取会话凭证。

**成功判断（关键坑，务必注意）**：

爱快 `/Action/call` 的成功标识**不是 `Result` 码**，而是综合判断：

- `Result == 10000`（旧版）或 `code == 0`（企业版 4.x）；
- 或 `ErrMsg == "Success"`（部分固件响应**不含 `Result` 字段**，只有 `ErrMsg` + `Data`）。

若只判断 `Result == 10000` 会误判失败（报错信息恰好是 "Success"）。

**会话管理**：

- `requests.Session` 自动保存 Set-Cookie；若响应体含 `sess_key` 则补存。
- 识别「会话过期」（返回码 `10001`，或提示语含 `no login`/`未登录`/`expired`/`过期`，或响应非 JSON）→ 自动重登并**重试一次**。
- HTTPS 自签名证书：`session.verify = False` 忽略校验。

### 4.2 DHCP 静态分配读写

- **读取**：`func_name = "dhcp_static"`，`action = "show"`，`param = {"TYPE": "total,data", "limit": "0,500"}`。
  - 列表数据容器兼容：`Data` / `data` / `result` / `results`，内层字段 `data`/`result`/`list`/`items`/`rows`。
- **更新网关**：定位到目标 MAC 对应的静态绑定记录，替换网关字段后提交 `edit`（param 为**平铺字段**，不要 `{"data":{}}` 包装）。
  - 字段：`mac`、`ip_addr`、`comment`、`dns1`/`dns2`（3.7.12+）；网关字段名见下方「待确认点」。

> ⚠️ **网关字段名待确认**：爱快不同模块网关字段命名不一（`static_rt` 用 `gateway`，DHCP 相关常缩写 `gw`）。
> 逆向项目 gxxHuang 的 `dhcp_static` `add` 仅含 `mac/ip_addr/comment`、`delete` 用 `{"id":xxx}`（action=`del`），
> **未覆盖网关字段**，无法从源码定名。本实现默认用 `gw` 并做 `gw`/`gateway` 双字段兼容，
> 最终以设备真实抓包为准（见 `_set_gateway_field` 一处修改点）。

### 4.3 网关 A/B 切换（核心业务）

```
用户点击开关
  → 后端读取该终端当前网关（字段兼容 gw/gateway）
  → decide_target_gateway(current, A, B)：current==B → A；否则 → B（无法匹配按「当前≈A」处理）
  → 更新网关字段后提交 edit
  → 成功：返回新网关；失败：抛出 IkuaiError（前端提示，开关回滚）
```

**关键约束**：

- 切换期间前端该终端开关进入 loading 态，防止重复提交。
- 提交失败不改变 UI 状态（无乐观更新，天然回滚）。
- 网关 A/B 相等或未配置时，路由层直接拒绝并提示。

### 4.4 配置存储（ConfigStore）

- 存储内容：`host`、`port`、`use_https`、`username`、`password`、`gateway_a`、`gateway_b`。
- 读写 `data/config.json`，线程安全（加锁），写入用临时文件 + `replace` 保证原子性。
- 数据目录优先环境变量 `DATA_DIR`（Docker 中挂载为 `/data`），否则默认 `web/data`。

## 5. 数据模型

```python
class ConfigIn(BaseModel):          # 连接配置
    host: str                       # 例：192.168.1.1
    port: int = 80
    use_https: bool = False
    username: str = ""
    password: str = ""
    gateway_a: str = ""             # 网关 A
    gateway_b: str = ""             # 网关 B

class DeviceOut(BaseModel):         # 终端设备
    mac: str                        # 唯一标识
    name: str                       # 设备名 / 备注
    ip: str
    gateway: str                    # 当前网关
    is_a: bool                      # 是否等于网关 A
    is_b: bool                      # 是否等于网关 B

class ToggleResult(BaseModel):      # 切换结果
    mac: str
    old_gateway: str
    new_gateway: str
```

## 6. REST API 设计

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/api/health` | 健康检查 |
| GET | `/api/config` | 读取配置 |
| POST | `/api/config` | 保存配置 |
| POST | `/api/login` | 测试/建立连接 |
| GET | `/api/devices` | 拉取终端列表 |
| POST | `/api/devices/{mac}/toggle` | 切换指定终端网关 |

错误统一返回 `{"detail": "<可读信息>"}`，HTTP 状态码 400（业务错误）。

## 7. 关键流程

### 7.1 首次访问

```
打开页面 → GET /api/config → 无 host → 显示配置页 → 用户填写 → POST /api/config
  → POST /api/login 测试连接 → 成功进入列表页
```

### 7.2 拉取终端列表

```
GET /api/devices → 后端 ensure_login → get_dhcp_bindings()
  → 解析为 DeviceOut 列表（含 is_a/is_b） → 前端渲染 A/B 开关
```

### 7.3 切换网关

见 4.3 节的编排流程。

## 8. 错误处理

| 场景 | 处理方式 |
|------|---------|
| 网络不可达 / 超时 | 提示「无法连接路由器」 |
| 登录失败（凭据错误） | 提示「用户名或密码错误」，回到配置页 |
| 会话过期 | 客户端自动重登并重试一次 |
| 切换提交失败 | 前端开关回滚，提示具体错误 |
| 爱快字段 / 版本不兼容 | 客户端做字段兼容，必要时提示「固件版本不支持」 |

统一封装 `IkuaiError`，携带错误码与可读信息，路由层转为 HTTP 400 + `detail`，前端只展示友好文案。

## 9. 测试策略

- **单元测试**（pytest）：认证编码（MD5/Base64/salt）、A/B 决策、成功判断兼容（Result/code/ErrMsg）、字段兼容、列表提取、请求参数组装、切换编排（mock `session.post` 捕获请求体断言）。
- **冒烟测试**：本地启动服务，`GET /api/health`、`GET /api/config` 等接口连通性验证；连接真实爱快设备手动验证「登录 → 拉列表 → 切换 → 生效」。

遵循项目 `AGENTS.md` 规范：每次改动后编写/更新对应测试，交付前确保测试与验证全部通过。

## 10. 部署

- **Docker**（推荐）：`cd web && docker compose up -d --build`，浏览器访问 `http://<内网IP>:8000`。
- **本地运行**：`pip install -r requirements.txt && uvicorn app.main:app --host 0.0.0.0 --port 8000`。
- 配置持久化：Docker 挂载 `./data:/data`；本地落盘 `web/data/config.json`。

## 11. 实现顺序建议

1. 爱快客户端 `ikuai_client.py`（认证 + 会话 + 切换，先联调真实登录报文）。
2. 配置层 `config.py` + 数据模型 `schemas.py`。
3. 路由层 `main.py`。
4. 前端单页 `static/`。
5. 单元测试 `tests/`。
6. 部署文件 + README。
7. 冒烟验证并 git 提交。

## 12. 安卓版（APK）技术说明

仓库另提供与本文档等价的**安卓原生实现**，位于 `mobile/`（Flutter）。

### 12.1 架构调整

Web 版是「浏览器 → 内网后端 → 爱快」三段式；安卓版把中间的 Web 后端整体下移到客户端，
变成「手机 App → 爱快」两段式，因此**无需部署任何服务端**，代价是手机必须与爱快同一内网。

```
┌─────────────────────────────────────────────┐
│  页面层（pages/）                            │  终端列表页 + 设置页（含编排与状态管理）
├─────────────────────────────────────────────┤
│  客户端层（services/ikuai_client.dart）      │  与 Web 版 ikuai_client.py 一一对应
├─────────────────────────────────────────────┤
│  存储层（services/config_store.dart）        │  KeyValueStore 抽象 + SharedPreferences 实现
└─────────────────────────────────────────────┘
```

### 12.2 文件对照

| Web 版 | 安卓版 |
|---|---|
| `app/ikuai_client.py` | `lib/services/ikuai_client.dart` |
| `app/config.py` | `lib/services/config_store.dart` |
| `app/schemas.py` | `lib/models/models.dart` |
| `app/main.py`（路由编排） | `lib/pages/home_page.dart`、`lib/pages/config_page.dart` |
| `static/index.html` + `app.js` + `style.css` | `lib/pages/*` + `lib/widgets/device_tile.dart` + `lib/theme.dart` |
| `tests/test_ikuai_client.py` | `test/ikuai_client_test.dart` |
| `tests/test_config.py` | `test/config_store_test.dart` |
| （无） | `test/widget_test.dart`（界面冒烟测试） |

### 12.3 安卓侧注意事项

- **明文流量**：爱快默认 HTTP:80，Android 9+ 默认禁止明文流量 → 需 `usesCleartextTraffic="true"`
  与 `res/xml/network_security_config.xml`。
- **自签名证书**：与 Web 版 `session.verify = False` 等价，用
  `HttpClient.badCertificateCallback` 放开。
- **Cookie 会话**：Dart `http` 不自动管理 Cookie，客户端自行维护 `sess_key` cookie 并在每次请求带上。
- **可测试性**：传输层通过构造参数注入（`IkuaiClient(transport: ...)`），页面通过
  `clientFactory` 注入，单测无需真实网络。

### 12.4 与 Web 版的行为差异

「响应非 JSON 视为会话失效」这一约定（见第 8 节错误处理）在 Web 版中因非 JSON 被包装为
`{"raw": ...}` 而**实际未生效**；安卓版补齐了该判断（`IkuaiClient.isUnparsedResponse`），
并在单测中固化。如需两端严格一致，可同步修正 `web/app/ikuai_client.py` 的 `_is_session_expired`。

