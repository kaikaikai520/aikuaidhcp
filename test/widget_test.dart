import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:aikuaidhcp/main.dart';
import 'package:aikuaidhcp/models/device.dart';
import 'package:aikuaidhcp/models/gateway_config.dart';
import 'package:aikuaidhcp/services/config_service.dart';
import 'package:aikuaidhcp/widgets/device_tile.dart';

void main() {
  group('应用启动', () {
    testWidgets('无本地配置时进入连接页', (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final configService = ConfigService();
      await configService.init();

      await tester.pumpWidget(IkuaiDhcpApp(configService: configService));
      await tester.pumpAndSettle();

      expect(find.text('爱快网关切换'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '连接'), findsOneWidget);
    });
  });

  group('GatewayAbSwitch', () {
    testWidgets('当前为 A 时点击 B 触发切换回调', (WidgetTester tester) async {
      var toggled = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayAbSwitch(
              currentGateway: '1.1.1.1',
              gatewayA: '1.1.1.1',
              gatewayB: '2.2.2.2',
              onToggle: () => toggled++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('B'));
      await tester.pump();
      expect(toggled, 1);

      // 点击当前侧 A 不触发
      await tester.tap(find.text('A'));
      await tester.pump();
      expect(toggled, 1);
    });

    testWidgets('禁用时不触发切换', (WidgetTester tester) async {
      var toggled = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GatewayAbSwitch(
              currentGateway: '1.1.1.1',
              gatewayA: '1.1.1.1',
              gatewayB: '2.2.2.2',
              enabled: false,
              onToggle: () => toggled++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('B'));
      await tester.pump();
      expect(toggled, 0);
    });
  });

  group('DeviceTile', () {
    testWidgets('展示设备信息与当前网关', (WidgetTester tester) async {
      const device = Device(
        mac: 'AA:BB:CC:DD:EE:FF',
        name: 'NAS',
        ip: '192.168.1.10',
        gateway: '1.1.1.1',
      );
      const gateways = GatewayConfig(gatewayA: '1.1.1.1', gatewayB: '2.2.2.2');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DeviceTile(
              device: device,
              gateways: gateways,
              isSwitching: false,
              onToggle: () {},
            ),
          ),
        ),
      );

      expect(find.text('NAS'), findsOneWidget);
      expect(find.text('当前网关：1.1.1.1'), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    });
  });
}
