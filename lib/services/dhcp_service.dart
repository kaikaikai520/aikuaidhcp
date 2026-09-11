import '../models/device.dart';
import 'ikuai_client.dart';

/// 网关 A/B 切换的目标网关决策（纯函数，便于单元测试）。
///
/// 规则：
/// - 当前网关 == B → 切到 A；
/// - 其余情况（当前 == A，或无法匹配）→ 按「当前≈A」处理，切到 B。
String decideTargetGateway({
  required String current,
  required String a,
  required String b,
}) {
  if (current == b) return a;
  return b;
}

/// DHCP 配置读写（服务层）。
///
/// 封装业务逻辑：读取静态绑定列表映射为 [Device]、定位 MAC 并更新网关。
class DhcpService {
  DhcpService(this._client);

  final IkuaiApi _client;

  /// 读取终端列表。
  Future<List<Device>> listDevices() async {
    final raw = await _client.getDhcpBindings();
    return raw.map(Device.fromMap).toList();
  }

  /// 更新指定终端的网关地址。
  ///
  /// 定位到目标 MAC 对应的静态绑定记录，替换网关字段后提交保存。
  /// 若未找到该 MAC 的绑定记录，抛出 [IkuaiException]。
  Future<void> updateGateway(String mac, String gateway) async {
    final raw = await _client.getDhcpBindings();

    Map<String, dynamic>? target;
    for (final item in raw) {
      final itemMac = (item['mac'] ?? '').toString().toLowerCase();
      if (itemMac == mac.toLowerCase()) {
        target = item;
        break;
      }
    }

    if (target == null) {
      throw IkuaiException(IkuaiClient.errNotFound, '未找到该终端的静态绑定记录（MAC: $mac）');
    }

    final updated = Map<String, dynamic>.from(target);
    _setGatewayField(updated, gateway);
    await _client.saveDhcpBinding(updated, isEdit: true);
  }

  /// 兼容爱快 `gateway` / `gw` 两种字段命名。
  void _setGatewayField(Map<String, dynamic> item, String gateway) {
    if (item.containsKey('gw') && !item.containsKey('gateway')) {
      item['gw'] = gateway;
    } else {
      item['gateway'] = gateway;
    }
  }
}
