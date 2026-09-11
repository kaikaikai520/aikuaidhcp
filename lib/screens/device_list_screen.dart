import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../providers/device_provider.dart';
import '../providers/router_provider.dart';
import '../services/errors.dart';
import '../widgets/device_tile.dart';
import 'settings_screen.dart';

/// 终端列表页：展示所有终端及其网关 A/B 开关。
class DeviceListScreen extends StatefulWidget {
  const DeviceListScreen({super.key});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<DeviceProvider>().refresh();
      }
    });
  }

  Future<void> _toggle(Device device) async {
    final provider = context.read<DeviceProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await provider.toggleGateway(device);
      messenger.showSnackBar(
        SnackBar(content: Text('已切换「${device.displayName}」的网关')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    // 从设置返回后刷新列表（网关预设可能已变化）。
    if (mounted) {
      await context.read<DeviceProvider>().refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('终端列表'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
            onPressed: () => context.read<DeviceProvider>().refresh(),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '设置',
            onPressed: _openSettings,
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'logout') {
                await context.read<RouterProvider>().logout();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'logout', child: Text('退出登录')),
            ],
          ),
        ],
      ),
      body: Consumer<DeviceProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.devices.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.errorMessage != null && provider.devices.isEmpty) {
            return _ErrorView(
              message: provider.errorMessage!,
              onRetry: provider.refresh,
            );
          }

          final gateways = provider.gatewayConfig;
          final devices = provider.devices;

          return RefreshIndicator(
            onRefresh: provider.refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _GatewayBanner(gatewayA: gateways.gatewayA, gatewayB: gateways.gatewayB),
                if (devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('暂无终端数据，请下拉刷新'),
                    ),
                  )
                else
                  ...devices.map((d) => DeviceTile(
                        device: d,
                        gateways: gateways,
                        isSwitching: provider.isSwitching(d.mac),
                        onToggle: () => _toggle(d),
                      )),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 顶部网关 A/B 预设提示条。
class _GatewayBanner extends StatelessWidget {
  const _GatewayBanner({required this.gatewayA, required this.gatewayB});

  final String gatewayA;
  final String gatewayB;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configured = gatewayA.isNotEmpty && gatewayB.isNotEmpty;
    final same = configured && gatewayA == gatewayB;

    final (text, color) = !configured
        ? ('尚未配置网关 A/B，请到设置中配置', theme.colorScheme.tertiary)
        : same
            ? ('网关 A 与网关 B 相同，开关已禁用', theme.colorScheme.error)
            : ('网关 A：$gatewayA　·　网关 B：$gatewayB', theme.colorScheme.primary);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}
