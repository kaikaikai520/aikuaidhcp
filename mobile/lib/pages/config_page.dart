/// 设置页：填写路由器连接信息 + 网关 A/B 预设。
///
/// 对应 Web 版 `index.html` 的 `#config-view`。
/// 保存流程：写入本地存储 → 用新配置试登录 → 成功则返回列表页。
library;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/config_store.dart';
import '../services/ikuai_client.dart';
import '../theme.dart';

class ConfigPage extends StatefulWidget {
  const ConfigPage({
    super.key,
    required this.configStore,
    required this.initial,
    this.firstRun = false,
  });

  final ConfigStore configStore;
  final IkuaiConfig initial;

  /// 首次启动（列表页无内容可返回）时为 true。
  final bool firstRun;

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _gatewayA;
  late final TextEditingController _gatewayB;
  bool _useHttps = false;

  bool _saving = false;
  bool _savedOnce = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final cfg = widget.initial;
    _host = TextEditingController(text: cfg.host);
    _port = TextEditingController(text: cfg.port.toString());
    _username = TextEditingController(text: cfg.username);
    _password = TextEditingController(text: cfg.password);
    _gatewayA = TextEditingController(text: cfg.gatewayA);
    _gatewayB = TextEditingController(text: cfg.gatewayB);
    _useHttps = cfg.useHttps;
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _username.dispose();
    _password.dispose();
    _gatewayA.dispose();
    _gatewayB.dispose();
    super.dispose();
  }

  IkuaiConfig _readForm() {
    final port = int.tryParse(_port.text.trim()) ?? 80;
    return IkuaiConfig(
      host: _host.text.trim(),
      port: (port < 1 || port > 65535) ? 80 : port,
      useHttps: _useHttps,
      username: _username.text.trim(),
      password: _password.text,
      gatewayA: _gatewayA.text.trim(),
      gatewayB: _gatewayB.text.trim(),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final cfg = _readForm();
    if (cfg.gatewayA.isNotEmpty &&
        cfg.gatewayB.isNotEmpty &&
        cfg.gatewayA == cfg.gatewayB) {
      setState(() => _message = '网关 A 与网关 B 不能相同');
      return;
    }

    setState(() {
      _saving = true;
      _message = null;
    });

    await widget.configStore.save(cfg);
    _savedOnce = true;

    // 用新配置试登录；失败不阻塞返回，仅提示（配置已落盘）
    final client = IkuaiClient.fromConfig(cfg);
    try {
      await client.login();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      return;
    } on IkuaiError catch (exc) {
      if (!mounted) return;
      setState(() => _message = '配置已保存，但连接失败：${exc.message}');
    } finally {
      client.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 首次进入且尚未保存过配置时，不提供返回（没有可返回的列表页）。
  bool get _canLeave =>
      !widget.firstRun || _savedOnce || widget.initial.isConfigured;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: AppColors.text,
        ),
        leading: _canLeave
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: '返回列表',
                onPressed: () => Navigator.of(context).pop(_savedOnce),
              )
            : null,
        automaticallyImplyLeading: false,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _sectionTitle('路由器连接'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: _field(
                    label: '地址',
                    controller: _host,
                    hint: '192.168.1.1',
                    keyboardType: TextInputType.url,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? '请填写路由器地址' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _field(
                    label: '端口',
                    controller: _port,
                    hint: '80',
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final text = (v ?? '').trim();
                      if (text.isEmpty) return null;
                      final port = int.tryParse(text);
                      if (port == null || port < 1 || port > 65535) {
                        return '端口无效';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _useHttps,
              onChanged: (v) => setState(() => _useHttps = v),
              title: const Text('使用 HTTPS', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '自动忽略自签名证书',
                style: TextStyle(fontSize: 12, color: AppColors.textSub),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    label: '用户名',
                    controller: _username,
                    hint: 'admin',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    label: '密码',
                    controller: _password,
                    obscure: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _sectionTitle('网关 A/B 预设'),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _field(
                    label: '网关 A',
                    controller: _gatewayA,
                    hint: '192.168.1.1',
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    label: '网关 B',
                    controller: _gatewayB,
                    hint: '192.168.1.2',
                    keyboardType: TextInputType.url,
                  ),
                ),
              ],
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              _Banner(message: _message!),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('保存并连接'),
                  ),
                ),
                if (_canLeave) ...[
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(_savedOnce),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppColors.border),
                      foregroundColor: AppColors.textSub,
                    ),
                    child: const Text('返回列表'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              '网关 A/B 为两个预设地址，点击终端开关即可在其间切换。\n'
              '设备需与爱快路由器处于同一内网（同一 WiFi / 局域网）。',
              style: TextStyle(fontSize: 12, color: AppColors.textSub),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
    ),
  );

  Widget _field({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textSub),
          ),
          const SizedBox(height: 5),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            validator: validator,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message});

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
