/// 网关 A/B 预设。
///
/// 核心功能：终端在两个预设网关之间做 A/B 二选一切换。
class GatewayConfig {
  const GatewayConfig({this.gatewayA = '', this.gatewayB = ''});

  /// 网关 A 地址。
  final String gatewayA;

  /// 网关 B 地址。
  final String gatewayB;

  /// 是否已配置完成（两个网关均已填写）。
  bool get isConfigured => gatewayA.trim().isNotEmpty && gatewayB.trim().isNotEmpty;

  /// 两个网关地址是否相同（相同则无法切换，开关需禁用）。
  bool get isSame => gatewayA.trim().isNotEmpty && gatewayA.trim() == gatewayB.trim();

  GatewayConfig copyWith({String? gatewayA, String? gatewayB}) {
    return GatewayConfig(
      gatewayA: gatewayA ?? this.gatewayA,
      gatewayB: gatewayB ?? this.gatewayB,
    );
  }
}
