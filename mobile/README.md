# 爱快 DHCP 网关切换助手 · 安卓版（APK）

原生 Android App（Flutter）。**不依赖任何服务端**：手机连上内网 WiFi 后，App 直接访问爱快路由器，
拉取 DHCP 静态分配列表，并对每台终端在预设的两个网关（A/B）之间一键切换。

## 与 Web 版的关系

本目录是把仓库里 `web/`（FastAPI + 原生 JS 的单页 Web 服务）**完整移植为安卓原生 App** 的产物，
业务逻辑、字段兼容策略与界面交互保持一致：

| Web 版文件 | 安卓版对应文件 | 说明 |
|---|---|---|
| `web/app/ikuai_client.py` | `lib/services/ikuai_client.dart` | 登录认证、会话管理、DHCP 静态分配读写、网关 A/B 切换 |
| `web/app/config.py` | `lib/services/config_store.dart` | 连接配置 + 隐藏终端列表持久化（`config.json`/`hidden.json` → SharedPreferences） |
| `web/app/schemas.py` | `lib/models/models.dart` | `IkuaiConfig` / `Device` / `ToggleResult` |
| `web/app/main.py` | `lib/pages/*.dart` | 路由/编排职责落到页面状态层（客户端直连，无需后端） |
| `web/static/index.html` + `app.js` + `style.css` | `lib/pages/*` + `lib/widgets/device_tile.dart` + `lib/theme.dart` | 界面与配色 |
| `web/tests/*.py` | `test/*.dart` | 单元测试与界面测试 |

### 架构差异

```
Web 版：  浏览器 ──HTTP──> Web 后端(内网机器) ──HTTP──> 爱快路由器
安卓版：  手机 App ──HTTP──> 爱快路由器                （省掉中间那台机器）
```

因此安卓版**无需部署、无需常开设备**，代价是手机必须与爱快在同一内网。

## 功能

- **连接配置**：爱快地址（IP:端口）、用户名、密码，可选 HTTPS（自动忽略自签名证书）。配置存在手机本地，重开 App 自动加载。
- **终端列表**：展示设备名、IP、MAC、当前网关，并用蓝色（A）／橙色（B）胶囊标出当前处于哪一侧。
- **A/B 一键切换**：每台终端右侧一个开关，**关 = 网关 A，开 = 网关 B**，点击即写回爱快并刷新列表。
- **终端隐藏**：不常切换的设备可隐藏，列表默认只显示未隐藏的；点顶部「隐藏的终端 (N)」可查看并恢复。
- **状态与错误提示**：顶栏显示「已连接／错误／未连接」，失败原因以浮层提示。

## 构建与安装

### 环境要求

- Flutter 3.35+（本项目在 Flutter 3.47.3 / Dart 3.13.3 上验证）
- JDK 17
- Android SDK（compileSdk 由 Flutter 提供）

### 构建

```bash
cd mobile
flutter pub get
flutter build apk --release
```

产物：`mobile/build/app/outputs/flutter-apk/app-release.apk`

安装到手机（USB 调试已开启）：

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

或把 APK 传到手机上直接点击安装（需允许「安装未知来源应用」）。

> ⚠️ 当前 `android/app/build.gradle.kts` 的 release 构建**沿用 debug 签名**（Flutter 模板默认），
> 仅供自用安装。若要上架或长期分发，请自行生成 keystore 并配置 `signingConfigs.release`。

### 跑测试

```bash
cd mobile
flutter test
```

## 使用步骤

1. 手机连上爱快所在的 WiFi。
2. 首次打开进入「设置」页，填写爱快地址、端口、用户名、密码，以及网关 A / 网关 B，点「保存并连接」。
3. 连接成功后进入终端列表，看到所有 DHCP 静态分配终端及其当前网关。
4. 点某台终端的 A/B 开关即完成切换，成功后列表自动刷新。
5. 终端太多时，点某台设备右侧「隐藏」把它收起；需要时点顶部「隐藏的终端 (N)」再「恢复」。

## 前置条件（爱快侧）

- 一个具备爱快 Web 管理权限的账号（默认 `admin`）。
- 需先在爱快「网络设置 → DHCP设置 → DHCP静态分配」中为终端建立**静态绑定记录**（本工具切换的正是这些记录里的网关字段）。
- 爱快需支持「静态分配指定网关」——免费版 3.7.x 实测支持。

## 目录结构

```
mobile/
├── lib/
│   ├── main.dart                     # App 入口
│   ├── theme.dart                    # 主题与配色（对齐 Web 版 CSS 变量）
│   ├── models/models.dart            # IkuaiConfig / Device / ToggleResult
│   ├── services/
│   │   ├── ikuai_client.dart         # 爱快 API 客户端 + 纯函数（认证编码、A/B 决策、字段兼容）
│   │   └── config_store.dart         # 本地持久化（KeyValueStore 抽象 + SharedPreferences 实现）
│   ├── pages/
│   │   ├── home_page.dart            # 终端列表页（首页）
│   │   └── config_page.dart          # 设置页
│   └── widgets/device_tile.dart      # 终端卡片（网关胶囊 + 隐藏按钮 + A/B 开关）
├── test/
│   ├── ikuai_client_test.dart        # 客户端核心逻辑单测
│   ├── config_store_test.dart        # 持久化单测
│   └── widget_test.dart              # 界面冒烟测试
└── android/                          # Android 工程（权限、明文 HTTP 放行、自签名证书信任）
```

## 安卓侧的关键配置

| 配置项 | 位置 | 原因 |
|---|---|---|
| `INTERNET` 权限 | `AndroidManifest.xml` | 访问内网路由器 |
| `usesCleartextTraffic="true"` | `AndroidManifest.xml` | 爱快默认走 HTTP（80 端口），Android 9+ 默认禁止明文流量 |
| `network_security_config.xml` | `res/xml/` | 允许明文流量 + 信任用户证书（自签名 HTTPS） |
| `badCertificateCallback` | `ikuai_client.dart` | 忽略自签名 HTTPS 证书，与 Web 版 `session.verify = False` 等价 |

## 与 Web 版的行为差异

1. **会话失效判定更严**：技术方案约定「响应非 JSON 视为会话失效，需重登重试」。
   Web 版把非 JSON 包装成 `{"raw": ...}` 后会被判为「未失效」，该约定实际未生效；
   安卓版补齐了这一步（`IkuaiClient.isUnparsedResponse`），并在单测中固化。
2. **密码落盘方式**：Web 版写 `config.json` 明文；安卓版存 SharedPreferences，同为明文。
   如需更高安全性，可后续接入 `flutter_secure_storage`（Android Keystore）。
