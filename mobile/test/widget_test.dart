/// 界面层冒烟测试：设置页跳转、列表渲染、A/B 开关与隐藏操作。
library;

import 'dart:convert';

import 'package:aikuaidhcp/models/models.dart';
import 'package:aikuaidhcp/pages/home_page.dart';
import 'package:aikuaidhcp/services/config_store.dart';
import 'package:aikuaidhcp/services/ikuai_client.dart';
import 'package:aikuaidhcp/theme.dart';
import 'package:aikuaidhcp/widgets/device_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonResponse(Object data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// 一条 DHCP 静态绑定记录（网关为 A）。
Map<String, dynamic> bindingA() => {
  'id': 1,
  'enabled': 'yes',
  'interface': 'auto',
  'mac': 'AA:BB:CC:DD:EE:FF',
  'ip_addr': '192.168.31.10',
  'gateway': '192.168.31.1',
  'dns1': '',
  'dns2': '',
  'comment': '机顶盒',
};

const IkuaiConfig configured = IkuaiConfig(
  host: '192.168.31.252',
  port: 80,
  username: 'admin',
  password: 'admin',
  gatewayA: '192.168.31.1',
  gatewayB: '192.168.31.2',
);

Widget wrap(Widget child) => MaterialApp(theme: buildAppTheme(), home: child);

void main() {
  testWidgets('未配置时自动进入设置页', (tester) async {
    final store = MemoryStore();
    await tester.pumpWidget(
      wrap(
        HomePage(
          configStore: ConfigStore(store),
          hiddenStore: HiddenStore(store),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('路由器连接'), findsOneWidget);
    expect(find.text('网关 A/B 预设'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '保存并连接'), findsOneWidget);
  });

  testWidgets('已配置时渲染终端列表与网关胶囊', (tester) async {
    final store = MemoryStore();
    await ConfigStore(store).save(configured);

    final transport = MockClient((request) async {
      if (request.url.path == '/Action/login') {
        return jsonResponse({'Result': 10000, 'ErrMsg': 'Success'});
      }
      return jsonResponse({
        'ErrMsg': 'Success',
        'Data': {
          'static_total': 1,
          'static_data': [bindingA()],
        },
      });
    });

    await tester.pumpWidget(
      wrap(
        HomePage(
          configStore: ConfigStore(store),
          hiddenStore: HiddenStore(store),
          clientFactory: (cfg) =>
              IkuaiClient.fromConfig(cfg, transport: transport),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('爱快 DHCP 网关切换'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);
    expect(find.text('机顶盒'), findsOneWidget);
    expect(find.text('192.168.31.10'), findsOneWidget);
    expect(find.text('AA:BB:CC:DD:EE:FF'), findsOneWidget);
    expect(find.text('网关 192.168.31.1'), findsOneWidget);
    expect(find.text('共 1 台终端'), findsOneWidget);
    // 网关为 A 侧 → 开关关闭
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('点击开关触发切换并刷新列表', (tester) async {
    final store = MemoryStore();
    await ConfigStore(store).save(configured);
    var gateway = '192.168.31.1';

    final transport = MockClient((request) async {
      if (request.url.path == '/Action/login') {
        return jsonResponse({'Result': 10000, 'ErrMsg': 'Success'});
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['action'] == 'edit') {
        gateway = (body['param'] as Map<String, dynamic>)['gateway'] as String;
        return jsonResponse({'Result': 30000, 'ErrMsg': 'Success'});
      }
      return jsonResponse({
        'ErrMsg': 'Success',
        'Data': {
          'static_total': 1,
          'static_data': [bindingA()..['gateway'] = gateway],
        },
      });
    });

    await tester.pumpWidget(
      wrap(
        HomePage(
          configStore: ConfigStore(store),
          hiddenStore: HiddenStore(store),
          clientFactory: (cfg) =>
              IkuaiClient.fromConfig(cfg, transport: transport),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(gateway, '192.168.31.2');
    expect(find.text('网关 192.168.31.2'), findsOneWidget);
    expect(find.textContaining('已切换'), findsOneWidget);
  });

  testWidgets('隐藏终端后从列表消失，可在「隐藏的终端」中恢复', (tester) async {
    final store = MemoryStore();
    await ConfigStore(store).save(configured);

    final transport = MockClient((request) async {
      if (request.url.path == '/Action/login') {
        return jsonResponse({'Result': 10000, 'ErrMsg': 'Success'});
      }
      return jsonResponse({
        'ErrMsg': 'Success',
        'Data': {
          'static_total': 1,
          'static_data': [bindingA()],
        },
      });
    });

    await tester.pumpWidget(
      wrap(
        HomePage(
          configStore: ConfigStore(store),
          hiddenStore: HiddenStore(store),
          clientFactory: (cfg) =>
              IkuaiClient.fromConfig(cfg, transport: transport),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('隐藏'));
    await tester.pumpAndSettle();

    // 已隐藏：主列表不再显示该终端，出现「隐藏的终端 (1)」入口
    expect(find.text('机顶盒'), findsNothing);
    expect(find.text('隐藏的终端 (1)'), findsOneWidget);
    expect(find.text('共 0 台终端（已隐藏 1 台）'), findsOneWidget);

    await tester.tap(find.text('隐藏的终端 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('机顶盒'), findsOneWidget);
    expect(find.text('恢复'), findsOneWidget);
  });

  testWidgets('DeviceTile 在切换中显示 loading 且不显示开关', (tester) async {
    const device = Device(
      mac: 'AA:BB:CC:DD:EE:FF',
      name: 'NAS',
      ip: '192.168.31.20',
      gateway: '192.168.31.2',
      isA: false,
      isB: true,
    );

    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: DeviceTile(
            device: device,
            toggling: true,
            hiding: false,
            onToggle: () {},
            onToggleHidden: () {},
          ),
        ),
      ),
    );

    expect(find.byType(Switch), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('网关 192.168.31.2'), findsOneWidget);
  });

  testWidgets('网关未设置时胶囊提示「网关未设置」', (tester) async {
    const device = Device(
      mac: 'AA:BB:CC:DD:EE:FF',
      name: 'NAS',
      ip: '',
      gateway: '',
      isA: false,
      isB: false,
    );

    await tester.pumpWidget(
      wrap(
        Scaffold(
          body: DeviceTile(
            device: device,
            toggling: false,
            hiding: false,
            onToggle: () {},
            onToggleHidden: () {},
          ),
        ),
      ),
    );

    expect(find.text('网关未设置'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });
}
