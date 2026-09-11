# 技术方案：爱快 DHCP 网关切换助手（aikuaidhcp）

> 版本：v0.1
> 对应产品设计文档：`docs/PRD.md`
> 更新日期：2026-09-11

## 1. 技术选型

| 类别 | 选型 | 理由 |
|------|------|------|
| 框架 | Flutter（Dart 3） | 跨平台、标准移动 UI 开发效率高、APK 打包顺滑，本机环境已就绪 |
| 网络请求 | dio | 拦截器机制便于实现「会话过期自动重登」；可配置忽略自签名证书 |
| 状态管理 | provider | MVP 规模足够，简单直观，不引入重型方案 |
| 本地存储 | shared_preferences | 存连接信息 + 网关预设，读写简单 |
| 密码安全 | flutter_secure_storage（可选） | 自用可先用 shared_preferences，后续按需升级 |

## 2. 总体架构

采用「UI 层 → 状态层 → 服务层 → 网络层」四层结构，职责单向依赖：

```
┌─────────────────────────────────────────────┐
│  UI 层（screens / widgets）                  │  页面与组件，只负责展示与交互
├─────────────────────────────────────────────┤
│  状态层（providers）                          │  ChangeNotifier，管理连接/列表/切换状态
├─────────────────────────────────────────────┤
│  服务层（services）                           │  业务逻辑：登录、DHCP 读写、网关切换编排
├─────────────────────────────────────────────┤
│  网络层（IkuaiClient + dio）                  │  爱快 HTTP API、会话管理、认证
└─────────────────────────────────────────────┘
```

**分层原则**：

- UI 层不直接发请求，只调用状态层暴露的方法。
- 服务层封装业务规则（如「切换网关 = 读取当前网关 → 取另一侧 → 提交」）。
- 网络层只负责「与爱快通信」，不掺杂业务判断。
- 各层通过依赖注入解耦，便于单元测试。

## 3. 项目结构

```
lib/
├── main.dart                 # 入口，初始化 Provider
├── models/
│   ├── router_config.dart    # 路由器连接配置
│   ├── device.dart           # 终端设备
│   └── gateway_config.dart   # 网关 A/B 预设
├── services/
│   ├── ikuai_client.dart     # 爱快 API 客户端（网络层）
│   ├── dhcp_service.dart     # DHCP 配置读写（服务层）
│   └── config_service.dart   # 本地配置存取（服务层）
├── providers/
│   ├── router_provider.dart  # 连接状态
│   └── device_provider.dart  # 终端列表 + 切换状态
├── screens/
│   ├── connect_screen.dart   # 连接页
│   ├── device_list_screen.dart # 终端列表页
│   └── settings_screen.dart  # 设置页
└── widgets/
    └── device_tile.dart      # 终端行（含 A/B 开关）
```

## 4. 核心模块设计

### 4.1 爱快 API 客户端（IkuaiClient）

这是整个产品的技术核心，负责与爱快路由器通信。

**职责**：登录认证、会话管理、通用调用、会话过期自动重登。

**关键方法**：

| 方法 | 说明 |
|------|------|
| `login()` | 获取 salt → 计算凭据 → 登录 → 保存 sess_key |
| `call(funcName, action, param)` | 带会话 cookie 调用 `/Action/call` |
| `getDhcpBindings()` | 读取 DHCP 静态分配列表 |
| `updateGateway(mac, gateway)` | 更新指定终端的网关 |

**认证流程**（爱快本地 API 的登录机制）：

1. 访问登录接口获取 `salt`（爱快可能存在多个 salt，需逐个尝试直到登录成功）。
2. `passwd = MD5(明文密码)`。
3. `pass = Base64(密码 + salt)` 组合编码。
4. `POST /Action/login`，提交 `user_name`、`passwd`、`pass`、`vldcode` 等参数。
5. 成功后从响应 / cookie 中取得 `sess_key`，作为后续请求的会话凭证。

> ⚠️ 说明：爱快不同固件版本的登录 salt 算法与字段命名存在差异，具体以联调实测为准。开发阶段先抓一次真实登录报文，再据此固化为客户端实现。

**会话管理（dio 拦截器）**：

- 请求拦截器：自动附加 `sess_key` cookie 与 `Content-Type`。
- 响应拦截器：识别「会话过期」错误码，自动调用 `login()` 重登并**重试一次**，失败则抛出统一异常。
- HTTPS 自签名证书：配置 `badCertificateCallback` 忽略证书校验（爱快默认自签名）。

### 4.2 DHCP 配置读写（DhcpService）

- **读取**：调用 `dhcp_server` 模块的查询动作，解析返回的终端列表（MAC、IP、网关、备注等），映射为 `Device` 模型。
- **更新网关**：定位到目标 MAC 对应的静态绑定记录，替换 `gateway` 字段后提交保存动作。

> ⚠️ 说明：爱快「DHCP 静态分配」的读写 `func_name` / `action` / 字段名（如 `gateway` vs `gw`）随固件版本有差异，需在开发阶段联调确认，并在客户端内做字段兼容。

### 4.3 网关 A/B 切换（核心业务）

切换逻辑编排在 `DeviceProvider` / `DhcpService` 中：

```
用户点击开关
  → 读取该终端当前网关
  → 判断当前是 A 还是 B（无法匹配时按「当前≈A」处理）
  → 取另一侧作为目标网关
  → 调用 updateGateway(mac, 目标网关)
  → 成功：刷新列表、更新开关状态
  → 失败：回滚开关、提示错误
```

**关键约束**：

- 切换期间该终端行进入 loading 态，防止重复提交。
- 提交失败不改变 UI 状态（乐观更新前先锁定，失败回滚）。
- 网关 A/B 相等时，开关禁用并提示。

### 4.4 本地配置存储（ConfigService）

- 存储内容：路由器地址（host/port/是否 HTTPS）、用户名、密码、网关 A、网关 B。
- 读写通过 `shared_preferences`，键名集中定义常量。
- 提供「清除凭据」方法，供设置页调用。

## 5. 数据模型

```dart
class RouterConfig {
  final String host;      // 例：192.168.17.254
  final int port;         // 默认 80（HTTP）/ 443（HTTPS）
  final String username;
  final String password;
  final bool useHttps;
}

class Device {
  final String mac;       // 唯一标识，用于定位终端
  final String name;      // 设备名 / 备注
  final String ip;
  final String gateway;   // 当前网关
}

class GatewayConfig {
  final String gatewayA;
  final String gatewayB;
}
```

## 6. 关键流程

### 6.1 登录流程

```
打开应用 → 读取本地 RouterConfig
  → 有配置：直接调用 login() 建立会话
  → 无配置/登录失败：进入连接页，用户填写后保存并登录
  → 成功进入终端列表
```

### 6.2 拉取终端列表

```
login() 成功 → getDhcpBindings() → 解析为 List<Device>
  → DeviceProvider 更新列表 → UI 渲染每台的 A/B 开关
```

### 6.3 切换网关

见 4.3 节的编排流程。

## 7. 错误处理

| 场景 | 处理方式 |
|------|---------|
| 网络不可达 / 超时 | 提示「无法连接路由器，请检查网络与地址」 |
| 登录失败（凭据错误） | 提示「用户名或密码错误」，回到连接页 |
| 会话过期 | 拦截器自动重登并重试一次 |
| 切换提交失败 | 回滚开关，提示具体错误 |
| 爱快字段 / 版本不兼容 | 客户端做字段兼容，必要时提示「固件版本不支持」 |

统一封装 `IkuaiException`，携带错误码与可读信息，UI 层只消费友好文案，不暴露堆栈。

## 8. 测试策略

- **单元测试**：认证编码（MD5 / Base64 / salt 组合）、DHCP 参数组装、网关 A/B 判断逻辑。
- **Widget 测试**：连接页表单校验、终端列表渲染、开关切换状态变化。
- **集成 / 冒烟测试**：连接真实爱快设备，手动验证「登录 → 拉列表 → 切换 → 生效」，重点核对真实接口字段。

遵循项目 `AGENTS.md` 规范：每次改动后编写 / 更新对应测试，交付前确保测试与验证全部通过。

## 9. 打包与发布

- 构建命令：`flutter build apk --release`
- 签名：自用可先用 debug 签名；正式分发前生成自有 keystore 并配置 `signingConfig`。
- 产物：`build/app/outputs/flutter-apk/app-release.apk`，可直接拷贝到手机安装。
- 最低 Android 版本：按 Flutter 默认（API 21+），满足绝大多数设备。

## 10. 实现顺序建议

1. 网络层 `IkuaiClient`（认证 + 会话，先联调真实登录报文）。
2. 服务层 `ConfigService` + `DhcpService`。
3. 状态层 `RouterProvider` / `DeviceProvider`。
4. UI 层四个页面与终端行组件。
5. 单元 + Widget 测试。
6. 打包 APK 并冒烟验证。
