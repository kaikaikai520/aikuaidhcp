import 'package:flutter/material.dart';

import '../models/device.dart';
import '../models/gateway_config.dart';

/// 网关 A/B 二选一开关。
///
/// 当前是 A 则高亮 A，点击 B 侧触发切换（反过来同理）。
class GatewayAbSwitch extends StatelessWidget {
  const GatewayAbSwitch({
    super.key,
    required this.currentGateway,
    required this.gatewayA,
    required this.gatewayB,
    required this.onToggle,
    this.enabled = true,
    this.loading = false,
  });

  final String currentGateway;
  final String gatewayA;
  final String gatewayB;

  /// 点击非当前侧时触发切换回调。
  final VoidCallback onToggle;

  final bool enabled;
  final bool loading;

  bool get _isB => gatewayB.isNotEmpty && currentGateway == gatewayB;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: enabled ? scheme.outline : scheme.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segment(context, 'A', active: !_isB),
          _segment(context, 'B', active: _isB),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, {required bool active}) {
    final scheme = Theme.of(context).colorScheme;
    final canTap = enabled && !active;
    return InkWell(
      onTap: canTap ? onToggle : null,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: active ? scheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active
                ? scheme.onPrimary
                : (enabled ? scheme.onSurface : scheme.outline),
          ),
        ),
      ),
    );
  }
}

/// 终端行：展示设备信息与 A/B 开关。
class DeviceTile extends StatelessWidget {
  const DeviceTile({
    super.key,
    required this.device,
    required this.gateways,
    required this.isSwitching,
    required this.onToggle,
  });

  final Device device;
  final GatewayConfig gateways;
  final bool isSwitching;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canToggle = gateways.isConfigured && !gateways.isSame;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.secondaryContainer,
              child: Icon(
                Icons.devices,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.displayName,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${device.ip.isEmpty ? '-' : device.ip} · ${device.mac}',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '当前网关：${device.gateway.isEmpty ? '未设置' : device.gateway}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            GatewayAbSwitch(
              currentGateway: device.gateway,
              gatewayA: gateways.gatewayA,
              gatewayB: gateways.gatewayB,
              enabled: canToggle,
              loading: isSwitching,
              onToggle: onToggle,
            ),
          ],
        ),
      ),
    );
  }
}
