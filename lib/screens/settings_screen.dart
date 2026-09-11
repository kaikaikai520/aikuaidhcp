import 'package:flutter/material.dart' hide RouterConfig;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/gateway_config.dart';
import '../models/router_config.dart';
import '../providers/router_provider.dart';
import '../services/config_service.dart';

/// 设置页：预设网关 A/B、修改路由器连接信息、清除凭据。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _gatewayFormKey = GlobalKey<FormState>();
  final _routerFormKey = GlobalKey<FormState>();

  late final TextEditingController _gatewayACtrl;
  late final TextEditingController _gatewayBCtrl;

  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _passCtrl;

  bool _useHttps = false;
  bool _savingGateway = false;
  bool _reconnecting = false;

  @override
  void initState() {
    super.initState();
    final configService = context.read<ConfigService>();
    final gateways = configService.gatewayConfig;
    _gatewayACtrl = TextEditingController(text: gateways.gatewayA);
    _gatewayBCtrl = TextEditingController(text: gateways.gatewayB);

    final config = context.read<RouterProvider>().config;
    _hostCtrl = TextEditingController(text: config?.host ?? '');
    _portCtrl = TextEditingController(text: (config?.port ?? 80).toString());
    _userCtrl = TextEditingController(text: config?.username ?? '');
    _passCtrl = TextEditingController(text: config?.password ?? '');
    _useHttps = config?.useHttps ?? false;
  }

  @override
  void dispose() {
    _gatewayACtrl.dispose();
    _gatewayBCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveGateway() async {
    if (!(_gatewayFormKey.currentState?.validate() ?? false)) return;
    setState(() => _savingGateway = true);
    final config = GatewayConfig(
      gatewayA: _gatewayACtrl.text.trim(),
      gatewayB: _gatewayBCtrl.text.trim(),
    );
    await context.read<ConfigService>().saveGatewayConfig(config);
    if (!mounted) return;
    setState(() => _savingGateway = false);
    _snack('网关预设已保存');
  }

  Future<void> _saveRouterAndReconnect() async {
    if (!(_routerFormKey.currentState?.validate() ?? false)) return;
    setState(() => _reconnecting = true);
    final config = RouterConfig(
      host: _hostCtrl.text.trim(),
      port: int.parse(_portCtrl.text.trim()),
      username: _userCtrl.text.trim(),
      password: _passCtrl.text,
      useHttps: _useHttps,
    );
    final ok = await context.read<RouterProvider>().connect(config);
    if (!mounted) return;
    setState(() => _reconnecting = false);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      final err = context.read<RouterProvider>().errorMessage ?? '保存失败';
      _snack(err);
    }
  }

  Future<void> _clearCredentials() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除登录凭据'),
        content: const Text('将清除已保存的用户名与密码，并回到连接页。确定继续？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await context.read<RouterProvider>().logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('网关预设', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Form(
            key: _gatewayFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _gatewayACtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '网关 A',
                    hintText: '例如 192.168.1.1',
                    prefixIcon: Icon(Icons.flag),
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateIp,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _gatewayBCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '网关 B',
                    hintText: '例如 192.168.2.1',
                    prefixIcon: Icon(Icons.outlined_flag),
                    border: OutlineInputBorder(),
                  ),
                  validator: _validateIp,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _savingGateway ? null : _saveGateway,
                    icon: const Icon(Icons.save),
                    label: const Text('保存网关预设'),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 40),

          Text('路由器连接', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Form(
            key: _routerFormKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _hostCtrl,
                  decoration: const InputDecoration(
                    labelText: '路由器地址',
                    prefixIcon: Icon(Icons.dns),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入路由器地址' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _portCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '端口',
                    prefixIcon: Icon(Icons.settings_ethernet),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final p = int.tryParse(v?.trim() ?? '');
                    if (p == null || p <= 0 || p > 65535) return '端口无效';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _userCtrl,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入用户名' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    prefixIcon: Icon(Icons.lock),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('使用 HTTPS'),
                  value: _useHttps,
                  onChanged: (v) => setState(() => _useHttps = v),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _reconnecting ? null : _saveRouterAndReconnect,
                    icon: const Icon(Icons.link),
                    label: const Text('保存并重新连接'),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 40),

          OutlinedButton.icon(
            onPressed: _clearCredentials,
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            icon: const Icon(Icons.logout),
            label: const Text('清除登录凭据'),
          ),
        ],
      ),
    );
  }

  String? _validateIp(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return null; // 允许留空，稍后由 banner 提示
    // 简单 IPv4 校验
    final parts = v.split('.');
    if (parts.length != 4) return '网关地址格式不正确';
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return '网关地址格式不正确';
    }
    return null;
  }
}
