/// 终端列表页（首页）。
///
/// 对应 Web 版 `index.html` 的 `#list-view` + `app.js` 的交互逻辑：
/// 拉取终端列表 → 渲染 A/B 开关 → 一键切换网关 → 隐藏/恢复终端。
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/config_store.dart';
import '../services/ikuai_client.dart';
import '../theme.dart';
import '../widgets/device_tile.dart';
import 'config_page.dart';

enum _ConnStatus { idle, ok, error }

/// 客户端工厂：默认按配置直连爱快；测试时可注入 mock 传输层。
typedef IkuaiClientFactory = IkuaiClient Function(IkuaiConfig config);

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.configStore,
    required this.hiddenStore,
    this.clientFactory,
  });

  final ConfigStore configStore;
  final HiddenStore hiddenStore;

  /// 可选的客户端构造钩子（注入 mock 便于界面测试与联调）。
  final IkuaiClientFactory? clientFactory;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  IkuaiConfig _config = const IkuaiConfig();
  IkuaiClient? _client;

  List<Device> _devices = const [];
  bool _loading = false;
  bool _showHidden = false;
  String? _error;
  _ConnStatus _status = _ConnStatus.idle;

  /// 正在切换 / 正在隐藏的终端 mac，防止重复提交。
  final Set<String> _toggling = {};
  final Set<String> _hiding = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _client?.dispose();
    super.dispose();
  }

  // ---- 生命周期 ----

  Future<void> _bootstrap() async {
    _config = widget.configStore.load();
    if (!_config.isConfigured) {
      await _openConfigPage(firstRun: true);
    } else {
      await _loadDevices();
    }
  }

  /// 按当前配置取客户端；配置变更时重建。
  IkuaiClient _ensureClient() {
    final existing = _client;
    if (existing != null &&
        existing.host == _config.host &&
        existing.port == _config.port &&
        existing.username == _config.username &&
        existing.password == _config.password &&
        existing.useHttps == _config.useHttps) {
      return existing;
    }
    existing?.dispose();
    _client =
        widget.clientFactory?.call(_config) ?? IkuaiClient.fromConfig(_config);
    return _client!;
  }

  Future<void> _openConfigPage({bool firstRun = false}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ConfigPage(
          configStore: widget.configStore,
          initial: _config,
          firstRun: firstRun,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true || !_config.isConfigured) {
      _config = widget.configStore.load();
      _client?.dispose();
      _client = null;
      await _loadDevices();
    }
  }

  // ---- 数据加载 ----

  Future<void> _loadDevices() async {
    if (!_config.isConfigured) return;
    if (!_config.hasGateways) {
      setState(() {
        _status = _ConnStatus.error;
        _error = '请先配置网关 A/B';
        _devices = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final client = _ensureClient();
      await client.ensureLogin();
      final bindings = await client.getDhcpBindings();
      final hidden = widget.hiddenStore.load().toSet();
      final devices = bindings.map((item) {
        final mac = getField(item, ['mac']);
        final name = getField(item, ['name', 'hostname', 'comment', 'remark']);
        final ip = getField(item, ['ip', 'ip_addr']);
        final gateway = getField(item, ['gateway', 'gw']);
        return Device(
          mac: mac,
          name: name.isEmpty ? mac : name,
          ip: ip,
          gateway: gateway,
          isA: gateway.isNotEmpty && gateway == _config.gatewayA,
          isB: gateway.isNotEmpty && gateway == _config.gatewayB,
          hidden: hidden.contains(mac.toLowerCase()),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _devices = devices;
        _status = _ConnStatus.ok;
        _error = null;
      });
    } on IkuaiError catch (exc) {
      if (!mounted) return;
      setState(() {
        _status = _ConnStatus.error;
        _error = exc.message;
        _devices = const [];
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---- 动作 ----

  Future<void> _toggleGateway(Device device) async {
    setState(() => _toggling.add(device.mac));
    try {
      final client = _ensureClient();
      await client.ensureLogin();
      final result = await client.toggleGateway(
        device.mac,
        _config.gatewayA,
        _config.gatewayB,
      );
      _showToast(
        '已切换：${result.oldGateway.isEmpty ? '自动' : result.oldGateway}'
        ' → ${result.newGateway}',
      );
    } on IkuaiError catch (exc) {
      _showToast('切换失败：${exc.message}', error: true);
    } finally {
      if (mounted) setState(() => _toggling.remove(device.mac));
      await _loadDevices();
    }
  }

  Future<void> _toggleHidden(Device device) async {
    setState(() => _hiding.add(device.mac));
    try {
      if (device.hidden) {
        await widget.hiddenStore.remove(device.mac);
        _showToast('已恢复显示 ${device.displayName}');
      } else {
        await widget.hiddenStore.add(device.mac);
        _showToast('已隐藏 ${device.displayName}');
      }
    } finally {
      if (mounted) setState(() => _hiding.remove(device.mac));
      await _loadDevices();
    }
  }

  void _showToast(String message, {bool error = false}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? AppColors.danger
            : const Color(0xE61F2329),
        duration: const Duration(milliseconds: 2500),
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  // ---- 渲染 ----

  @override
  Widget build(BuildContext context) {
    final hiddenCount = _devices.where((d) => d.hidden).length;
    final visible = _devices
        .where((d) => !d.hidden || _showHidden)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.swap_horiz, size: 20, color: AppColors.primary),
            SizedBox(width: 8),
            Text(
              '爱快 DHCP 网关切换',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.text,
              ),
            ),
          ],
        ),
        actions: [
          _StatusBadge(status: _status),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: _openConfigPage,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDevices,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _toolbar(hiddenCount),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 12),
            if (_loading && _devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (visible.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48, horizontal: 16),
                child: Text(
                  '暂无终端。请先在爱快「网络设置 → DHCP设置 → DHCP静态分配」'
                  '中添加静态绑定记录。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.textSub),
                ),
              )
            else
              for (final device in visible) ...[
                DeviceTile(
                  key: ValueKey(device.mac),
                  device: device,
                  toggling: _toggling.contains(device.mac),
                  hiding: _hiding.contains(device.mac),
                  onToggle: () => _toggleGateway(device),
                  onToggleHidden: () => _toggleHidden(device),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }

  Widget _toolbar(int hiddenCount) {
    final summary = _showHidden
        ? '共 ${_devices.length} 台终端（含 $hiddenCount 台隐藏）'
        : '共 ${_devices.length - hiddenCount} 台终端'
              '${hiddenCount > 0 ? '（已隐藏 $hiddenCount 台）' : ''}';

    return Row(
      children: [
        Expanded(
          child: Text(
            summary,
            style: const TextStyle(fontSize: 13, color: AppColors.textSub),
          ),
        ),
        if (hiddenCount > 0)
          TextButton(
            onPressed: () => setState(() => _showHidden = !_showHidden),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSub,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(fontSize: 13),
            ),
            child: Text(_showHidden ? '收起隐藏' : '隐藏的终端 ($hiddenCount)'),
          ),
        const SizedBox(width: 4),
        OutlinedButton.icon(
          onPressed: _loading ? null : _loadDevices,
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('刷新'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            side: const BorderSide(color: AppColors.border),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            textStyle: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final _ConnStatus status;

  @override
  Widget build(BuildContext context) {
    final (String label, Color background, Color foreground) = switch (status) {
      _ConnStatus.ok => ('已连接', const Color(0xFFE7F6EC), AppColors.ok),
      _ConnStatus.error => ('错误', const Color(0xFFFDECEC), AppColors.danger),
      _ConnStatus.idle => ('未连接', const Color(0xFFEEF0F3), AppColors.textSub),
    };

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        border: Border.all(color: const Color(0xFFF5C6C6)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }
}
