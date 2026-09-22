/// 数据模型：路由器连接配置、终端设备、切换结果。
///
/// 与 Web 版 `web/app/schemas.py` 一一对应。
library;

/// 路由器连接配置（爱快管理地址 + 登录凭据 + 网关 A/B 预设）。
class IkuaiConfig {
  const IkuaiConfig({
    this.host = '',
    this.port = 80,
    this.useHttps = false,
    this.username = '',
    this.password = '',
    this.gatewayA = '',
    this.gatewayB = '',
  });

  /// 爱快管理地址，如 `192.168.1.1`。
  final String host;

  /// 端口，HTTP 默认 80 / HTTPS 默认 443。
  final int port;

  /// 是否使用 HTTPS（自签名证书自动忽略校验）。
  final bool useHttps;

  final String username;
  final String password;

  /// 网关 A / 网关 B 两个预设地址（关 = A，开 = B）。
  final String gatewayA;
  final String gatewayB;

  /// 是否已填写路由器地址（决定进列表页还是设置页）。
  bool get isConfigured => host.trim().isNotEmpty;

  /// 两个网关是否都已配置（切换前必须满足）。
  bool get hasGateways =>
      gatewayA.trim().isNotEmpty && gatewayB.trim().isNotEmpty;

  IkuaiConfig copyWith({
    String? host,
    int? port,
    bool? useHttps,
    String? username,
    String? password,
    String? gatewayA,
    String? gatewayB,
  }) {
    return IkuaiConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      useHttps: useHttps ?? this.useHttps,
      username: username ?? this.username,
      password: password ?? this.password,
      gatewayA: gatewayA ?? this.gatewayA,
      gatewayB: gatewayB ?? this.gatewayB,
    );
  }

  Map<String, dynamic> toJson() => {
    'host': host,
    'port': port,
    'use_https': useHttps,
    'username': username,
    'password': password,
    'gateway_a': gatewayA,
    'gateway_b': gatewayB,
  };

  /// 容错解析：字段缺失/类型不符时回落到默认值，绝不抛异常。
  factory IkuaiConfig.fromJson(Map<String, dynamic> json) {
    return IkuaiConfig(
      host: (json['host'] ?? '').toString(),
      port: _parsePort(json['port']),
      useHttps: json['use_https'] == true,
      username: (json['username'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
      gatewayA: (json['gateway_a'] ?? '').toString(),
      gatewayB: (json['gateway_b'] ?? '').toString(),
    );
  }

  static int _parsePort(dynamic raw) {
    final int? parsed;
    if (raw is int) {
      parsed = raw;
    } else if (raw is num) {
      parsed = raw.toInt();
    } else {
      parsed = int.tryParse(raw?.toString() ?? '');
    }
    if (parsed == null || parsed < 1 || parsed > 65535) return 80;
    return parsed;
  }

  @override
  String toString() =>
      'IkuaiConfig(host: $host, port: $port, https: $useHttps, '
      'a: $gatewayA, b: $gatewayB)';
}

/// 终端设备（DHCP 静态分配列表项）。
class Device {
  const Device({
    required this.mac,
    required this.name,
    required this.ip,
    required this.gateway,
    required this.isA,
    required this.isB,
    this.hidden = false,
  });

  /// MAC 地址，作为终端唯一标识。
  final String mac;

  /// 设备名 / 备注，为空时回落到 MAC。
  final String name;

  final String ip;

  /// 当前网关（空串表示爱快里的「自动」）。
  final String gateway;

  /// 当前网关是否等于网关 A。
  final bool isA;

  /// 当前网关是否等于网关 B。
  final bool isB;

  /// 是否已被用户隐藏。
  final bool hidden;

  /// 列表展示用名称。
  String get displayName => name.trim().isEmpty ? mac : name;

  Device copyWith({bool? hidden}) => Device(
    mac: mac,
    name: name,
    ip: ip,
    gateway: gateway,
    isA: isA,
    isB: isB,
    hidden: hidden ?? this.hidden,
  );
}

/// 网关切换结果。
class ToggleResult {
  const ToggleResult({
    required this.mac,
    required this.oldGateway,
    required this.newGateway,
  });

  final String mac;
  final String oldGateway;
  final String newGateway;

  @override
  String toString() =>
      'ToggleResult($mac: ${oldGateway.isEmpty ? '自动' : oldGateway} → $newGateway)';
}
