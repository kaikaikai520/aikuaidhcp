/// 本地配置持久化单元测试。
///
/// 与 Web 版 `web/tests/test_config.py` 的 HiddenStore 用例一一对应，
/// 并补充 ConfigStore 的读写与容错用例。
library;

import 'dart:convert';

import 'package:aikuaidhcp/models/models.dart';
import 'package:aikuaidhcp/services/config_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HiddenStore', () {
    test('初始为空', () {
      expect(HiddenStore(MemoryStore()).load(), isEmpty);
    });

    test('添加后去重（大小写不敏感）', () async {
      final store = HiddenStore(MemoryStore());
      await store.add('AA:BB:CC:DD:EE:FF');
      await store.add('aa:bb:cc:dd:ee:ff');
      await store.add('11:22:33:44:55:66');
      expect(store.load(), ['aa:bb:cc:dd:ee:ff', '11:22:33:44:55:66']);
    });

    test('恢复（移除）后不再隐藏', () async {
      final store = HiddenStore(MemoryStore());
      await store.add('AA:BB:CC:DD:EE:FF');
      await store.remove('aa:bb:cc:dd:ee:ff');
      expect(store.load(), isEmpty);
    });

    test('移除不存在的 mac 为无操作', () async {
      final store = HiddenStore(MemoryStore());
      await store.add('AA:BB:CC:DD:EE:FF');
      await store.remove('00:00:00:00:00:00');
      expect(store.load(), ['aa:bb:cc:dd:ee:ff']);
    });

    test('重新实例化后仍可读到（验证已落盘）', () async {
      final backing = MemoryStore();
      final store = HiddenStore(backing);
      await store.add('AA:BB:CC:DD:EE:FF');
      expect(HiddenStore(backing).load(), ['aa:bb:cc:dd:ee:ff']);
    });

    test('空 mac 不写入', () async {
      final store = HiddenStore(MemoryStore());
      await store.add('');
      expect(store.load(), isEmpty);
    });

    test('存储内容损坏时回落为空列表', () {
      final backing = MemoryStore();
      backing.setString(HiddenStore.storageKey, '{not-json');
      expect(HiddenStore(backing).load(), isEmpty);
    });
  });

  group('ConfigStore', () {
    test('未保存时返回默认空配置', () {
      final cfg = ConfigStore(MemoryStore()).load();
      expect(cfg.host, '');
      expect(cfg.port, 80);
      expect(cfg.isConfigured, isFalse);
    });

    test('保存后可完整读回', () async {
      final store = ConfigStore(MemoryStore());
      const cfg = IkuaiConfig(
        host: '192.168.31.252',
        port: 8080,
        useHttps: true,
        username: 'admin',
        password: 'secret',
        gatewayA: '192.168.31.1',
        gatewayB: '192.168.31.2',
      );
      await store.save(cfg);

      final loaded = store.load();
      expect(loaded.host, '192.168.31.252');
      expect(loaded.port, 8080);
      expect(loaded.useHttps, isTrue);
      expect(loaded.username, 'admin');
      expect(loaded.password, 'secret');
      expect(loaded.gatewayA, '192.168.31.1');
      expect(loaded.gatewayB, '192.168.31.2');
      expect(loaded.isConfigured, isTrue);
      expect(loaded.hasGateways, isTrue);
    });

    test('持久化格式为 JSON 且字段名为下划线风格', () async {
      final backing = MemoryStore();
      await ConfigStore(
        backing,
      ).save(const IkuaiConfig(host: '10.0.0.1', gatewayA: 'a', gatewayB: 'b'));

      final decoded =
          jsonDecode(backing.getString(ConfigStore.storageKey)!)
              as Map<String, dynamic>;
      expect(decoded['host'], '10.0.0.1');
      expect(decoded['use_https'], isFalse);
      expect(decoded['gateway_a'], 'a');
      expect(decoded['gateway_b'], 'b');
    });

    test('存储内容损坏时回落为空配置', () {
      final backing = MemoryStore();
      backing.setString(ConfigStore.storageKey, '不是 json');
      expect(ConfigStore(backing).load().isConfigured, isFalse);
    });

    test('端口越界时回落为 80', () {
      final backing = MemoryStore();
      backing.setString(
        ConfigStore.storageKey,
        jsonEncode({'host': '10.0.0.1', 'port': 70000}),
      );
      expect(ConfigStore(backing).load().port, 80);
    });

    test('仅配置一个网关时 hasGateways 为 false', () {
      const cfg = IkuaiConfig(host: '10.0.0.1', gatewayA: '1.1.1.1');
      expect(cfg.isConfigured, isTrue);
      expect(cfg.hasGateways, isFalse);
    });
  });
}
