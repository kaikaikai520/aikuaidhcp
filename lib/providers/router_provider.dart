import 'package:flutter/foundation.dart';

import '../models/router_config.dart';
import '../services/config_service.dart';
import '../services/errors.dart';
import '../services/ikuai_client.dart';

/// 连接状态。
enum RouterStatus {
  /// 初始化中。
  loading,

  /// 尚无可用配置，需进入连接页填写。
  needsConfig,

  /// 已连接。
  connected,

  /// 连接 / 登录失败。
  error,
}

/// 路由器连接状态（状态层）。
///
/// 负责：读取本地配置、建立会话、登录、断开。连接成功后对外暴露
/// [IkuaiClient]，供 [DeviceProvider] 构建 [DhcpService] 使用。
class RouterProvider extends ChangeNotifier {
  RouterProvider(this._configService);

  final ConfigService _configService;

  RouterStatus _status = RouterStatus.loading;
  RouterConfig? _config;
  IkuaiClient? _client;
  String? _errorMessage;

  RouterStatus get status => _status;
  RouterConfig? get config => _config;
  IkuaiClient? get client => _client;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _status == RouterStatus.connected;

  /// 应用启动时初始化：读取本地配置，有则直接登录。
  Future<void> init() async {
    _status = RouterStatus.loading;
    notifyListeners();

    final saved = _configService.loadRouterConfig();
    if (saved == null || !saved.isComplete) {
      _status = RouterStatus.needsConfig;
      notifyListeners();
      return;
    }

    await _loginAndSet(saved);
  }

  /// 使用给定配置连接并登录。成功返回 true，失败返回 false。
  Future<bool> connect(RouterConfig config) async {
    _status = RouterStatus.loading;
    _errorMessage = null;
    notifyListeners();

    await _configService.saveRouterConfig(config);
    return _loginAndSet(config);
  }

  Future<bool> _loginAndSet(RouterConfig config) async {
    try {
      final client = IkuaiClient(config: config);
      await client.login();
      _client = client;
      _config = config;
      _status = RouterStatus.connected;
      _errorMessage = null;
    } catch (e) {
      _status = RouterStatus.error;
      _errorMessage = friendlyErrorMessage(e);
    }
    notifyListeners();
    return _status == RouterStatus.connected;
  }

  /// 断开连接并清除登录凭据，回到连接页。
  Future<void> logout() async {
    _client = null;
    _config = null;
    _status = RouterStatus.needsConfig;
    _errorMessage = null;
    await _configService.clearCredentials();
    notifyListeners();
  }
}
