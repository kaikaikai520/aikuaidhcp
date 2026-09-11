import 'package:flutter_test/flutter_test.dart';

import 'package:aikuaidhcp/services/dhcp_service.dart';
import 'package:aikuaidhcp/services/ikuai_client.dart';

/// 内存版 IkuaiApi，供测试依赖注入。
class FakeIkuaiApi implements IkuaiApi {
  FakeIkuaiApi(this.bindings);

  List<Map<String, dynamic>> bindings;
  int saveCalls = 0;
  bool? lastIsEdit;
  Map<String, dynamic>? lastSaved;

  @override
  Future<void> login() async {}

  @override
  Future<dynamic> call(String funcName, String action,
      [Map<String, dynamic>? param]) async {
    return {'Result': 10000, 'ErrMsg': 'Success'};
  }

  @override
  Future<List<Map<String, dynamic>>> getDhcpBindings() async {
    return bindings.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  @override
  Future<void> saveDhcpBinding(Map<String, dynamic> item,
      {required bool isEdit}) async {
    saveCalls++;
    lastIsEdit = isEdit;
    lastSaved = item;
    final idx = bindings.indexWhere((b) => b['mac'] == item['mac']);
    if (idx >= 0) bindings[idx] = item;
  }
}

void main() {
  group('decideTargetGateway', () {
    test('当前为 A 切到 B', () {
      expect(
        decideTargetGateway(current: '1.1.1.1', a: '1.1.1.1', b: '2.2.2.2'),
        '2.2.2.2',
      );
    });

    test('当前为 B 切到 A', () {
      expect(
        decideTargetGateway(current: '2.2.2.2', a: '1.1.1.1', b: '2.2.2.2'),
        '1.1.1.1',
      );
    });

    test('无法匹配时按「当前≈A」处理，切到 B', () {
      expect(
        decideTargetGateway(current: '9.9.9.9', a: '1.1.1.1', b: '2.2.2.2'),
        '2.2.2.2',
      );
      expect(
        decideTargetGateway(current: '', a: '1.1.1.1', b: '2.2.2.2'),
        '2.2.2.2',
      );
    });
  });

  group('DhcpService.updateGateway', () {
    test('按 MAC 定位并更新 gateway 字段', () async {
      final fake = FakeIkuaiApi([
        {'mac': 'AA:BB:CC:DD:EE:FF', 'ip_addr': '192.168.1.10', 'gateway': '1.1.1.1'},
      ]);
      final service = DhcpService(fake);

      await service.updateGateway('aa:bb:cc:dd:ee:ff', '2.2.2.2');

      expect(fake.saveCalls, 1);
      expect(fake.lastIsEdit, isTrue);
      expect(fake.lastSaved!['gateway'], '2.2.2.2');
    });

    test('兼容 gw 字段命名', () async {
      final fake = FakeIkuaiApi([
        {'mac': 'AA:BB:CC:DD:EE:FF', 'ip_addr': '192.168.1.10', 'gw': '1.1.1.1'},
      ]);
      final service = DhcpService(fake);

      await service.updateGateway('AA:BB:CC:DD:EE:FF', '2.2.2.2');

      expect(fake.lastSaved!['gw'], '2.2.2.2');
      expect(fake.lastSaved!.containsKey('gateway'), isFalse);
    });

    test('未找到 MAC 时抛出异常', () async {
      final fake = FakeIkuaiApi([]);
      final service = DhcpService(fake);

      expect(
        () => service.updateGateway('00:00:00:00:00:00', '2.2.2.2'),
        throwsA(isA<IkuaiException>()),
      );
    });
  });

  group('DhcpService.listDevices', () {
    test('映射为 Device 列表', () async {
      final fake = FakeIkuaiApi([
        {'mac': 'AA:BB:CC:DD:EE:FF', 'ip': '192.168.1.10', 'name': 'NAS', 'gateway': '1.1.1.1'},
        {'mac': '11:22:33:44:55:66', 'ip': '192.168.1.11', 'hostname': 'TV', 'gateway': '2.2.2.2'},
      ]);
      final devices = await DhcpService(fake).listDevices();
      expect(devices, hasLength(2));
      expect(devices[0].displayName, 'NAS');
      expect(devices[1].displayName, 'TV');
    });
  });
}
