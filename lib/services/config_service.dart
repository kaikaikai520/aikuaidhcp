import 'package:shared_preferences/shared_preferences.dart';

import '../models/gateway_config.dart';
import '../models/router_config.dart';

/// 本地配置存取（服务层）。
///
/// 通过 shared_preferences 持久化路由器连接信息与网关 A/B 预设。
/// 键名集中定义常量，避免散落。
class ConfigService {
  static const String _kHost = 'router_host';
  static const String _kPort = 'router_port';
  static const String _kUsername = 'router_username';
  static const String _kPassword = 'router_password';
  static const String _kUseHttps = 'router_use_https';
  static const String _kGatewayA = 'gateway_a';
  static const String _kGatewayB = 'gateway_b';

  SharedPreferences? _prefs;

  /// 应用启动时初始化，加载本地存储。
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    final prefs = _prefs;
    if (prefs == null) {
      throw StateError('ConfigService 尚未初始化，请先调用 init()');
    }
    return prefs;
  }

  /// 读取路由器连接配置；未保存过则返回 null。
  RouterConfig? loadRouterConfig() {
    final host = _p.getString(_kHost) ?? '';
    if (host.isEmpty) return null;
    return RouterConfig(
      host: host,
      port: _p.getInt(_kPort) ?? 80,
      username: _p.getString(_kUsername) ?? '',
      password: _p.getString(_kPassword) ?? '',
      useHttps: _p.getBool(_kUseHttps) ?? false,
    );
  }

  Future<void> saveRouterConfig(RouterConfig config) async {
    await _p.setString(_kHost, config.host.trim());
    await _p.setInt(_kPort, config.port);
    await _p.setString(_kUsername, config.username.trim());
    await _p.setString(_kPassword, config.password);
    await _p.setBool(_kUseHttps, config.useHttps);
  }

  /// 当前网关 A/B 预设。
  GatewayConfig get gatewayConfig => GatewayConfig(
        gatewayA: _p.getString(_kGatewayA) ?? '',
        gatewayB: _p.getString(_kGatewayB) ?? '',
      );

  Future<void> saveGatewayConfig(GatewayConfig config) async {
    await _p.setString(_kGatewayA, config.gatewayA.trim());
    await _p.setString(_kGatewayB, config.gatewayB.trim());
  }

  /// 清除登录凭据（用户名、密码），保留其余设置。
  Future<void> clearCredentials() async {
    await _p.remove(_kUsername);
    await _p.remove(_kPassword);
  }

  /// 清除全部本地配置。
  Future<void> clearAll() async {
    await _p.remove(_kHost);
    await _p.remove(_kPort);
    await _p.remove(_kUsername);
    await _p.remove(_kPassword);
    await _p.remove(_kUseHttps);
    await _p.remove(_kGatewayA);
    await _p.remove(_kGatewayB);
  }
}
