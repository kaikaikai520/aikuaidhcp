import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aikuaidhcp/models/router_config.dart';
import 'package:aikuaidhcp/services/ikuai_client.dart';

/// 验证爱快 API 客户端的 DHCP 静态分配请求组装是否正确。
///
/// 通过 mock Dio 拦截器捕获请求体，断言 func_name / action / param 结构，
/// 覆盖真实固件联调中踩过的坑：
/// - func_name 应为 `dhcp_static`（而非社区误传的 `dhcp_addr_bind`）；
/// - 列表读取用 `TYPE=total,data` + 分页 limit；
/// - add/edit 的 param 是「平铺字段」，不能用 `{"data": item}` 包装。
void main() {
  group('IkuaiClient DHCP 静态分配接口', () {
    late Dio dio;
    late List<Map<String, dynamic>> capturedBodies;

    setUp(() {
      capturedBodies = [];
      dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.data;
            if (data is Map) {
              capturedBodies.add(Map<String, dynamic>.from(data));
            }
            handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'Result': 10000,
                  'ErrMsg': 'Success',
                  'Data': {
                    'data': [
                      {
                        'id': 1,
                        'mac': 'AA:BB:CC:DD:EE:FF',
                        'ip_addr': '192.168.1.10',
                        'gateway': '1.1.1.1',
                        'comment': 'NAS',
                      },
                    ],
                  },
                },
              ),
            );
          },
        ),
      );
    });

    IkuaiClient buildClient() => IkuaiClient(
          config: const RouterConfig(
            host: '192.168.1.1',
            port: 80,
            username: 'admin',
            password: 'admin',
          ),
          dio: dio,
        );

    test('getDhcpBindings 使用 func_name=dhcp_static + total,data 分页', () async {
      final bindings = await buildClient().getDhcpBindings();

      expect(bindings, hasLength(1));
      final body = capturedBodies.single;
      expect(body['func_name'], 'dhcp_static');
      expect(body['action'], 'show');
      final param = body['param'] as Map;
      expect(param['TYPE'], 'total,data');
      expect(param['limit'], '0,500');
    });

    test('saveDhcpBinding 编辑时用平铺 param（无 data 包装）', () async {
      await buildClient().saveDhcpBinding(
        {
          'id': 1,
          'mac': 'AA:BB:CC:DD:EE:FF',
          'ip_addr': '192.168.1.10',
          'gateway': '2.2.2.2',
        },
        isEdit: true,
      );

      final body = capturedBodies.single;
      expect(body['func_name'], 'dhcp_static');
      expect(body['action'], 'edit');
      final param = body['param'] as Map;
      expect(param['gateway'], '2.2.2.2');
      expect(param['mac'], 'AA:BB:CC:DD:EE:FF');
      // 关键：绝不能有 {"data": {...}} 包装。
      expect(param.containsKey('data'), isFalse);
    });

    test('saveDhcpBinding 新增时 action=add', () async {
      await buildClient().saveDhcpBinding(
        {'mac': 'AA:BB:CC:DD:EE:FF', 'ip_addr': '192.168.1.10'},
        isEdit: false,
      );

      final body = capturedBodies.single;
      expect(body['func_name'], 'dhcp_static');
      expect(body['action'], 'add');
    });
  });
}
