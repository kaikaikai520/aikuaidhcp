import 'package:flutter_test/flutter_test.dart';

import 'package:aikuaidhcp/models/device.dart';
import 'package:aikuaidhcp/models/gateway_config.dart';
import 'package:aikuaidhcp/models/router_config.dart';

void main() {
  group('Device 字段兼容映射', () {
    test('标准字段', () {
      final d = Device.fromMap({
        'mac': 'AA:BB:CC:DD:EE:FF',
        'ip': '192.168.1.10',
        'name': 'NAS',
        'gateway': '192.168.1.1',
      });
      expect(d.mac, 'AA:BB:CC:DD:EE:FF');
      expect(d.ip, '192.168.1.10');
      expect(d.name, 'NAS');
      expect(d.gateway, '192.168.1.1');
    });

    test('兼容 ip_addr / hostname / gw', () {
      final d = Device.fromMap({
        'mac': 'aa:bb:cc:dd:ee:ff',
        'ip_addr': '10.0.0.2',
        'hostname': 'box',
        'gw': '10.0.0.1',
      });
      expect(d.ip, '10.0.0.2');
      expect(d.name, 'box');
      expect(d.gateway, '10.0.0.1');
    });

    test('displayName 为空时回退 MAC', () {
      final d = Device.fromMap({'mac': 'AA:BB:CC:DD:EE:FF'});
      expect(d.displayName, 'AA:BB:CC:DD:EE:FF');
    });
  });

  group('GatewayConfig', () {
    test('isConfigured 需两个网关均非空', () {
      expect(const GatewayConfig(gatewayA: '1.1.1.1', gatewayB: '2.2.2.2').isConfigured,
          isTrue);
      expect(const GatewayConfig(gatewayA: '1.1.1.1').isConfigured, isFalse);
      expect(const GatewayConfig().isConfigured, isFalse);
    });

    test('isSame 判断两网关相同', () {
      expect(const GatewayConfig(gatewayA: '1.1.1.1', gatewayB: '1.1.1.1').isSame,
          isTrue);
      expect(const GatewayConfig(gatewayA: '1.1.1.1', gatewayB: '2.2.2.2').isSame,
          isFalse);
    });
  });

  group('RouterConfig', () {
    test('baseUrl 组装', () {
      const http = RouterConfig(
          host: '192.168.1.1', port: 80, username: 'a', password: 'b');
      expect(http.baseUrl, 'http://192.168.1.1:80');

      const https = RouterConfig(
          host: '192.168.1.1',
          port: 443,
          username: 'a',
          password: 'b',
          useHttps: true);
      expect(https.baseUrl, 'https://192.168.1.1:443');
    });

    test('isComplete 校验', () {
      const ok = RouterConfig(
          host: '192.168.1.1', port: 80, username: 'a', password: 'b');
      expect(ok.isComplete, isTrue);

      const noHost =
          RouterConfig(host: '', port: 80, username: 'a', password: 'b');
      expect(noHost.isComplete, isFalse);
    });
  });
}
