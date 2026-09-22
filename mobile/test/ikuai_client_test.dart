/// 爱快客户端核心逻辑单元测试。
///
/// 与 Web 版 `web/tests/test_ikuai_client.py` 用例一一对应，覆盖：
/// 认证编码（MD5/Base64）、A/B 决策、成功判断兼容、字段兼容、
/// 列表提取、请求参数组装、切换编排、会话过期自动重登。
library;

import 'dart:convert';

import 'package:aikuaidhcp/models/models.dart';
import 'package:aikuaidhcp/services/ikuai_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 构造一个 JSON 响应。
http.Response jsonResponse(Object data, {int status = 200}) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response Function(http.Request) always(Object data) =>
    (_) => jsonResponse(data);

/// 登录成功的响应。
http.Response Function(http.Request) get loginOk =>
    always({'Result': 10000, 'ErrMsg': 'Success'});

/// 测试用请求记录器。
///
/// - `/Action/login` 固定返回 [loginResponse]（默认成功），让测试专注业务调用；
/// - 其余 `/Action/call` 请求按顺序消费 [callResponses]，超出后复用最后一个。
class _Harness {
  _Harness(this.callResponses, {http.Response Function(http.Request)? loginResponse})
    : _loginResponse = loginResponse ?? loginOk;

  final List<http.Response Function(http.Request)> callResponses;
  final http.Response Function(http.Request) _loginResponse;

  final List<http.Request> requests = [];
  int _callIndex = 0;

  http.Client get client => MockClient((request) async {
    requests.add(request);
    if (request.url.path == '/Action/login') {
      return _loginResponse(request);
    }
    final index = _callIndex++;
    final handler = callResponses[index >= callResponses.length
        ? callResponses.length - 1
        : index];
    return handler(request);
  });

  /// 仅业务调用（`/Action/call`）的请求列表。
  List<http.Request> get callRequests =>
      requests.where((r) => r.url.path == '/Action/call').toList();

  Map<String, dynamic> bodyAt(List<http.Request> list, int index) =>
      jsonDecode(list[index].body) as Map<String, dynamic>;
}

IkuaiClient makeClient(http.Client transport) => IkuaiClient(
  host: '192.168.1.1',
  username: 'admin',
  password: 'admin',
  transport: transport,
);

/// 建立测试用客户端并完成登录（后续业务调用才是断言对象）。
Future<IkuaiClient> _loggedInClient(_Harness harness) async {
  final client = makeClient(harness.client);
  await client.ensureLogin();
  return client;
}

void main() {
  group('认证编码', () {
    test('md5Password 返回 32 位小写十六进制', () {
      expect(md5Password('admin'), '21232f297a57a5a743894a0e4a801fc3');
    });

    test('encodePass = Base64(salt 前缀 + 明文密码)', () {
      expect(
        encodePass('123456', 'salt_11'),
        base64.encode(utf8.encode('salt_11123456')),
      );
    });

    test('encodeCredentials 同时返回 passwd 与 pass', () {
      final creds = encodeCredentials('admin', 'salt_11');
      expect(creds[0], md5Password('admin'));
      expect(creds[1], encodePass('admin', 'salt_11'));
    });
  });

  group('网关 A/B 决策', () {
    test('当前为 B → 切到 A', () {
      expect(decideTargetGateway('2.2.2.2', '1.1.1.1', '2.2.2.2'), '1.1.1.1');
    });

    test('当前为 A → 切到 B', () {
      expect(decideTargetGateway('1.1.1.1', '1.1.1.1', '2.2.2.2'), '2.2.2.2');
    });

    test('当前网关为空 / 无法匹配 → 按「当前≈A」切到 B', () {
      expect(decideTargetGateway('', '1.1.1.1', '2.2.2.2'), '2.2.2.2');
      expect(decideTargetGateway('9.9.9.9', '1.1.1.1', '2.2.2.2'), '2.2.2.2');
    });
  });

  group('成功判断兼容', () {
    test('Result == 10000 → 成功', () {
      expect(IkuaiClient.isSuccess({'Result': 10000}), isTrue);
    });

    test('code == 0（企业版）→ 成功', () {
      expect(IkuaiClient.isSuccess({'code': 0}), isTrue);
    });

    test('只有 ErrMsg == "Success"（无 Result 字段）→ 成功', () {
      expect(IkuaiClient.isSuccess({'ErrMsg': 'Success'}), isTrue);
    });

    test('Result == -1 且 ErrMsg 非 success → 失败', () {
      expect(IkuaiClient.isSuccess({'Result': -1, 'ErrMsg': 'error'}), isFalse);
    });

    test('edit 成功码 30000 + ErrMsg == "Success" → 成功', () {
      expect(
        IkuaiClient.isSuccess({'Result': 30000, 'ErrMsg': 'Success'}),
        isTrue,
      );
    });
  });

  group('字段兼容', () {
    test('按优先级取多字段命名', () {
      final item = <String, dynamic>{
        'name': 'NAS',
        'ip_addr': '10.0.0.2',
        'gw': '10.0.0.1',
      };
      expect(getField(item, ['name', 'hostname', 'comment']), 'NAS');
      expect(getField(item, ['ip', 'ip_addr']), '10.0.0.2');
      expect(getField(item, ['gw', 'gateway']), '10.0.0.1');
    });

    test('字段缺失或为空串时回落为空串', () {
      expect(getField({}, ['a', 'b']), '');
      expect(getField({'a': ''}, ['a', 'b']), '');
      expect(getField({'a': null}, ['a', 'b']), '');
    });
  });

  group('列表提取', () {
    test('旧版 Data 容器', () {
      expect(IkuaiClient.extractList({
        'Data': [
          {'mac': 'aa:bb'},
        ],
      }), [
        {'mac': 'aa:bb'},
      ]);
    });

    test('企业版 results 容器', () {
      expect(IkuaiClient.extractList({
        'results': [
          {'mac': 'aa:bb'},
        ],
      }), [
        {'mac': 'aa:bb'},
      ]);
    });

    test('嵌套 Data.data 容器', () {
      expect(IkuaiClient.extractList({
        'Data': {
          'data': [
            {'mac': 'aa:bb'},
          ],
        },
      }), [
        {'mac': 'aa:bb'},
      ]);
    });

    test('配置视角 static_data 容器', () {
      expect(
        IkuaiClient.extractList({
          'ErrMsg': 'Success',
          'Data': {
            'static_total': 1,
            'static_data': [
              {'mac': 'aa:bb', 'gateway': '1.1.1.1', 'enabled': 'yes'},
            ],
          },
        }),
        [
          {'mac': 'aa:bb', 'gateway': '1.1.1.1', 'enabled': 'yes'},
        ],
      );
    });

    test('空数据返回空列表', () {
      expect(IkuaiClient.extractList({}), isEmpty);
      expect(IkuaiClient.extractList({'Data': null}), isEmpty);
    });
  });

  group('请求组装', () {
    test('登录请求体正确（首个 salt 即成功）', () async {
      final harness = _Harness([always({'ErrMsg': 'Success'})]);
      final client = makeClient(harness.client);

      await client.login();

      expect(harness.requests.single.url.path, '/Action/login');
      final body = harness.bodyAt(harness.requests, 0);
      expect(body['username'], 'admin');
      expect(body['passwd'], md5Password('admin'));
      expect(body['pass'], encodePass('admin', 'salt_123'));
      expect(body['remember_password'], isNull);
      expect(client.isLoggedIn, isTrue);
    });

    test('所有 salt 均失败 → 401', () async {
      final harness = _Harness(
        [always({'ErrMsg': 'Success'})],
        loginResponse: always({'Result': -1, 'ErrMsg': 'bad'}),
      );
      final client = makeClient(harness.client);

      await expectLater(
        client.login(),
        throwsA(
          isA<IkuaiError>()
              .having((e) => e.code, 'code', 401)
              .having((e) => e.message, 'message', contains('登录失败')),
        ),
      );
      // 默认 4 个 salt，各尝试一次
      expect(harness.requests.length, IkuaiClient.defaultSaltList.length);
    });

    test('读取 DHCP 静态分配使用配置视角参数', () async {
      final harness = _Harness([always({'ErrMsg': 'Success', 'Data': []})]);
      final client = await _loggedInClient(harness);

      await client.getDhcpBindings();

      expect(harness.callRequests.single.url.path, '/Action/call');
      final body = harness.bodyAt(harness.callRequests, 0);
      expect(body['func_name'], 'dhcp_static');
      expect(body['action'], 'show');
      expect(body['param'], {
        'TYPE': 'static_total,static_data',
        'limit': '0,500',
      });
    });

    test('saveDhcpBinding(isEdit: true) 提交 action=edit', () async {
      final harness = _Harness([always({'ErrMsg': 'Success'})]);
      final client = await _loggedInClient(harness);

      await client.saveDhcpBinding({
        'mac': 'aa',
        'ip_addr': '10.0.0.2',
      }, isEdit: true);

      expect(harness.bodyAt(harness.callRequests, 0)['action'], 'edit');
    });
  });

  group('切换编排', () {
    Map<String, dynamic> binding({
      Object? id = 40,
      Object? enabled = 'yes',
      String gateway = '1.1.1.1',
    }) => {
      'id': id,
      'enabled': enabled,
      'interface': 'auto',
      'mac': 'AA:BB:CC:DD:EE:FF',
      'ip_addr': '10.0.0.2',
      'gateway': gateway,
      'dns1': '',
      'dns2': '',
      'comment': 'NAS',
    };

    test('A → B：返回原/新网关，edit 字段完整', () async {
      final harness = _Harness([
        always({
          'ErrMsg': 'Success',
          'Data': {
            'static_total': 1,
            'static_data': [binding()],
          },
        }),
        always({'ErrMsg': 'Success'}),
      ]);
      final client = await _loggedInClient(harness);

      final result = await client.toggleGateway(
        'aa:bb:cc:dd:ee:ff',
        '1.1.1.1',
        '2.2.2.2',
      );

      expect(result.oldGateway, '1.1.1.1');
      expect(result.newGateway, '2.2.2.2');

      final editBody = harness.bodyAt(harness.callRequests, 1);
      expect(editBody['action'], 'edit');
      final param = editBody['param'] as Map<String, dynamic>;
      expect(param['gateway'], '2.2.2.2');
      expect(param['enabled'], 'yes');
      expect(param['id'], 40);
      expect(param['mac'], 'AA:BB:CC:DD:EE:FF');
      expect(param['ip_addr'], '10.0.0.2');
      expect(param['comment'], 'NAS');
    });

    test('enabled 缺失时默认补 yes（否则爱快报参数错误）', () async {
      final harness = _Harness([
        always({
          'ErrMsg': 'Success',
          'Data': {
            'static_data': [binding(id: 1, enabled: null, gateway: '')],
          },
        }),
        always({'ErrMsg': 'Success'}),
      ]);
      final client = await _loggedInClient(harness);

      final result = await client.toggleGateway(
        'aa:bb:cc:dd:ee:ff',
        '1.1.1.1',
        '2.2.2.2',
      );

      expect(result.oldGateway, '');
      expect(result.newGateway, '2.2.2.2');
      final param = harness.bodyAt(harness.callRequests, 1)['param']
          as Map<String, dynamic>;
      expect(param['enabled'], 'yes');
      expect(param['gateway'], '2.2.2.2');
    });

    test('B → A：当前为网关 B 时切回 A', () async {
      final harness = _Harness([
        always({
          'ErrMsg': 'Success',
          'Data': {
            'static_data': [binding(gateway: '2.2.2.2')],
          },
        }),
        always({'ErrMsg': 'Success'}),
      ]);
      final client = await _loggedInClient(harness);

      final result = await client.toggleGateway(
        'aa:bb:cc:dd:ee:ff',
        '1.1.1.1',
        '2.2.2.2',
      );

      expect(result.oldGateway, '2.2.2.2');
      expect(result.newGateway, '1.1.1.1');
    });

    test('MAC 不存在 → 404', () async {
      final harness = _Harness([always({'ErrMsg': 'Success', 'Data': []})]);
      final client = await _loggedInClient(harness);

      await expectLater(
        client.toggleGateway('aa:bb:cc:dd:ee:ff', '1.1.1.1', '2.2.2.2'),
        throwsA(isA<IkuaiError>().having((e) => e.code, 'code', 404)),
      );
    });
  });

  group('会话管理', () {
    test('会话过期（10001）自动重登并重试一次', () async {
      var callCount = 0;
      final client = makeClient(
        MockClient((request) async {
          if (request.url.path == '/Action/login') {
            return jsonResponse({'Result': 10000, 'ErrMsg': 'Success'});
          }
          callCount++;
          if (callCount == 1) {
            return jsonResponse({'Result': 10001, 'ErrMsg': 'no login'});
          }
          return jsonResponse({'ErrMsg': 'Success', 'Data': []});
        }),
      );

      final result = await client.call('dhcp_static', 'show');

      expect(callCount, 2);
      expect(IkuaiClient.isSuccess(result), isTrue);
      expect(client.isLoggedIn, isTrue);
    });

    test('返回非 JSON / 未登录提示识别为会话失效', () {
      expect(IkuaiClient.isSessionExpired({'raw': '<html>'}), isTrue);
      expect(IkuaiClient.isSessionExpired('not a map'), isTrue);
      expect(IkuaiClient.isSessionExpired({'ErrMsg': '未登录'}), isTrue);
      expect(IkuaiClient.isSessionExpired({'ErrMsg': 'Success'}), isFalse);
    });

    test('sending to kernel 前缀的响应体可正常解析', () {
      final response = http.Response(
        'sending to kernel {"ErrMsg":"Success","Data":[]}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      final data = IkuaiClient.toJson(response);
      expect(IkuaiClient.isSuccess(data), isTrue);
      expect(IkuaiClient.extractList(data), isEmpty);
    });

    test('网络异常 → 登录失败 401，且信息包含连接提示', () async {
      final client = makeClient(
        MockClient((_) async => throw Exception('Connection refused')),
      );
      await expectLater(
        client.login(),
        throwsA(
          isA<IkuaiError>()
              .having((e) => e.code, 'code', 401)
              .having((e) => e.message, 'message', contains('登录失败'))
              .having((e) => e.message, 'message', contains('无法连接路由器')),
        ),
      );
    });
  });

  group('客户端构造', () {
    test('fromConfig 正确映射字段与 baseUrl', () {
      const cfg = IkuaiConfig(
        host: '192.168.31.1',
        port: 8080,
        useHttps: true,
        username: 'admin',
        password: 'pw',
        gatewayA: '1.1.1.1',
        gatewayB: '2.2.2.2',
      );
      final client = IkuaiClient.fromConfig(cfg);
      expect(client.baseUrl, 'https://192.168.31.1:8080');
      expect(client.host, '192.168.31.1');
      expect(client.port, 8080);
      expect(client.useHttps, isTrue);
      client.dispose();
    });
  });
}
