import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../models/gateway_config.dart';
import '../services/config_service.dart';
import '../services/dhcp_service.dart';
import '../services/errors.dart';
import '../services/ikuai_client.dart';
import 'router_provider.dart';

/// 终端列表 + 网关切换状态（状态层）。
///
/// 负责：拉取终端列表、编排 A/B 切换逻辑、维护切换中的加载态。
class DeviceProvider extends ChangeNotifier {
  DeviceProvider(this._configService);

  final ConfigService _configService;

  RouterProvider? _router;

  List<Device> _devices = [];
  bool _loading = false;
  String? _errorMessage;
  final Set<String> _switching = {};

  List<Device> get devices => List.unmodifiable(_devices);
  bool get isLoading => _loading;
  String? get errorMessage => _errorMessage;

  /// 当前网关 A/B 预设。
  GatewayConfig get gatewayConfig => _configService.gatewayConfig;

  /// 供 [ChangeNotifierProxyProvider] 注入路由器状态。
  set router(RouterProvider? value) => _router = value;

  /// 指定 MAC 的终端是否正在切换中。
  bool isSwitching(String mac) => _switching.contains(mac.toLowerCase());

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  DhcpService _service() {
    final client = _router?.client;
    if (client == null) {
      throw IkuaiException(-1, '尚未连接路由器');
    }
    return DhcpService(client);
  }

  /// 拉取终端列表。
  Future<void> refresh() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _devices = await _service().listDevices();
    } catch (e) {
      _errorMessage = friendlyErrorMessage(e);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 切换指定终端的网关（A ↔ B）。
  ///
  /// 成功后更新本地状态；失败抛出 [IkuaiException]，开关状态不变（不乐观更新）。
  Future<void> toggleGateway(Device device) async {
    final gateways = gatewayConfig;
    if (!gateways.isConfigured) {
      throw IkuaiException(-1, '请先在设置中配置网关 A 与网关 B');
    }
    if (gateways.isSame) {
      throw IkuaiException(-1, '网关 A 与网关 B 相同，无法切换');
    }

    final target = decideTargetGateway(
      current: device.gateway,
      a: gateways.gatewayA,
      b: gateways.gatewayB,
    );

    _switching.add(device.mac.toLowerCase());
    notifyListeners();

    try {
      await _service().updateGateway(device.mac, target);
      _replaceDevice(device.mac, target);
    } finally {
      _switching.remove(device.mac.toLowerCase());
      notifyListeners();
    }
  }

  void _replaceDevice(String mac, String newGateway) {
    final index =
        _devices.indexWhere((d) => d.mac.toLowerCase() == mac.toLowerCase());
    if (index >= 0) {
      _devices[index] = _devices[index].copyWith(gateway: newGateway);
    }
  }
}
