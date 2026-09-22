/// 单个终端卡片：设备名 / IP / MAC / 当前网关胶囊 + 隐藏按钮 + A/B 开关。
///
/// 对应 Web 版 `renderDevices()` 生成的 `.device-item` 结构。
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

class DeviceTile extends StatelessWidget {
  const DeviceTile({
    super.key,
    required this.device,
    required this.toggling,
    required this.hiding,
    required this.onToggle,
    required this.onToggleHidden,
  });

  final Device device;

  /// 该终端正在切换网关（开关进入 loading 态）。
  final bool toggling;

  /// 该终端正在隐藏 / 恢复。
  final bool hiding;

  final VoidCallback onToggle;
  final VoidCallback onToggleHidden;

  @override
  Widget build(BuildContext context) {
    final d = device;
    return Opacity(
      opacity: d.hidden ? 0.55 : 1,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                        decoration: d.hidden
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: AppColors.textSub,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (d.ip.isNotEmpty)
                          Text(
                            d.ip,
                            style: monospaceStyle.copyWith(
                              fontSize: 12,
                              color: AppColors.textSub,
                            ),
                          ),
                        Text(
                          d.mac,
                          style: monospaceStyle.copyWith(
                            fontSize: 12,
                            color: AppColors.textSub,
                          ),
                        ),
                        _GatewayChip(device: d),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: hiding ? null : onToggleHidden,
                style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  foregroundColor:
                      d.hidden ? AppColors.primary : AppColors.textSub,
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: Text(d.hidden ? '恢复' : '隐藏'),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 18,
                child: Text(
                  d.isA
                      ? 'A'
                      : d.isB
                      ? 'B'
                      : '—',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: d.isA
                        ? AppColors.gatewayA
                        : d.isB
                        ? AppColors.gatewayB
                        : AppColors.textSub,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _GatewaySwitch(
                on: d.isB,
                loading: toggling,
                onChanged: onToggle,
                semanticLabel: '切换 ${d.displayName} 的网关',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 当前网关状态胶囊（A 蓝 / B 橙 / 未设置灰）。
class _GatewayChip extends StatelessWidget {
  const _GatewayChip({required this.device});

  final Device device;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final Color background = d.isA
        ? AppColors.chipA
        : d.isB
        ? AppColors.chipB
        : AppColors.chipNeutral;
    final Color foreground = d.isA
        ? AppColors.gatewayA
        : d.isB
        ? AppColors.gatewayB
        : AppColors.textSub;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        d.gateway.isEmpty ? '网关未设置' : '网关 ${d.gateway}',
        style: TextStyle(fontSize: 12, color: foreground),
      ),
    );
  }
}

/// A/B 开关：关 = 网关 A，开 = 网关 B；切换中显示转圈并禁用。
class _GatewaySwitch extends StatelessWidget {
  const _GatewaySwitch({
    required this.on,
    required this.loading,
    required this.onChanged,
    required this.semanticLabel,
  });

  final bool on;
  final bool loading;
  final VoidCallback onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 48,
        height: 32,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Semantics(
      label: semanticLabel,
      child: Switch(
        value: on,
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.primary,
        inactiveThumbColor: Colors.white,
        inactiveTrackColor: const Color(0xFFCBD5E1),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: (_) => onChanged(),
      ),
    );
  }
}
