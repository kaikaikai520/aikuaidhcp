/// 终端设备。
///
/// 从爱快 DHCP 静态分配列表解析而来。MAC 作为唯一标识，用于定位与更新。
class Device {
  const Device({
    required this.mac,
    required this.name,
    required this.ip,
    required this.gateway,
  });

  /// MAC 地址，唯一标识，用于定位终端。
  final String mac;

  /// 设备名 / 备注。
  final String name;

  /// 分配到的 IP 地址。
  final String ip;

  /// 当前网关地址。
  final String gateway;

  /// 展示名称：优先用备注/设备名，为空时回退到 MAC。
  String get displayName => name.trim().isNotEmpty ? name.trim() : mac;

  /// 从爱快返回的原始字段映射为 [Device]。
  ///
  /// 爱快不同固件版本的字段命名存在差异，这里做字段兼容：
  /// - 名称：`name` / `hostname` / `comment` / `remark`
  /// - IP：`ip` / `ip_addr`
  /// - 网关：`gateway` / `gw`
  factory Device.fromMap(Map<String, dynamic> map) {
    String str(dynamic v, [String fallback = '']) =>
        (v ?? fallback).toString().trim();

    final mac = str(map['mac']);
    final ip = str(map['ip'] ?? map['ip_addr']);
    final name =
        str(map['name'] ?? map['hostname'] ?? map['comment'] ?? map['remark']);
    final gateway = str(map['gateway'] ?? map['gw']);

    return Device(mac: mac, name: name, ip: ip, gateway: gateway);
  }

  /// 生成一个更新后的副本（切换网关后刷新本地状态用）。
  Device copyWith({String? name, String? ip, String? gateway}) {
    return Device(
      mac: mac,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      gateway: gateway ?? this.gateway,
    );
  }
}
