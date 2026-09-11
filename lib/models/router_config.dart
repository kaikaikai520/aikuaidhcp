/// 路由器连接配置。
///
/// 保存爱快路由器的地址、端口、登录凭据与协议类型，供 [IkuaiClient] 建立连接。
class RouterConfig {
  const RouterConfig({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    this.useHttps = false,
  });

  /// 路由器地址，例如 `192.168.17.254`。
  final String host;

  /// 端口，HTTP 默认 80，HTTPS 默认 443。
  final int port;

  final String username;
  final String password;

  /// 是否使用 HTTPS（爱快默认自签名证书）。
  final bool useHttps;

  /// 组装基础地址，例如 `http://192.168.17.254:80`。
  String get baseUrl {
    final scheme = useHttps ? 'https' : 'http';
    return '$scheme://$host:$port';
  }

  /// 判断配置是否完整（可作为登录入口的基本校验）。
  bool get isComplete =>
      host.trim().isNotEmpty && username.trim().isNotEmpty && port > 0;

  RouterConfig copyWith({
    String? host,
    int? port,
    String? username,
    String? password,
    bool? useHttps,
  }) {
    return RouterConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: password ?? this.password,
      useHttps: useHttps ?? this.useHttps,
    );
  }

  /// 清除密码后的副本，用于展示时不暴露明文密码。
  RouterConfig withPasswordMasked() => copyWith(password: password.isEmpty ? '' : '••••••');
}
