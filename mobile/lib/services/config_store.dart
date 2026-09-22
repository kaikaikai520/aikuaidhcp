/// 本地配置持久化。
///
/// 对应 Web 版的 `web/app/config.py`：
/// - [ConfigStore] ⇔ config.json（连接信息 + 网关 A/B 预设）
/// - [HiddenStore] ⇔ hidden.json（隐藏的终端 mac 列表）
///
/// 安卓端改用 `SharedPreferences` 存储；通过 [KeyValueStore] 抽象出存储接口，
/// 便于单元测试注入内存实现（无需真实插件）。
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

/// 最小键值存储接口（仓储层抽象）。
abstract class KeyValueStore {
  String? getString(String key);

  Future<void> setString(String key, String value);

  Future<void> remove(String key);
}

/// 基于 `SharedPreferences` 的真实实现。
class PrefsStore implements KeyValueStore {
  PrefsStore(this._prefs);

  final SharedPreferences _prefs;

  /// 打开存储（App 启动时调用一次）。
  static Future<PrefsStore> open() async =>
      PrefsStore(await SharedPreferences.getInstance());

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// 内存实现，仅用于测试。
class MemoryStore implements KeyValueStore {
  final Map<String, String> _data = {};

  @override
  String? getString(String key) => _data[key];

  @override
  Future<void> setString(String key, String value) async => _data[key] = value;

  @override
  Future<void> remove(String key) async => _data.remove(key);
}

/// 连接配置读写。
class ConfigStore {
  ConfigStore(this._store);

  static const String storageKey = 'router_config';

  final KeyValueStore _store;

  /// 读取配置；无配置或数据损坏时返回默认空配置。
  IkuaiConfig load() {
    final raw = _store.getString(storageKey);
    if (raw == null || raw.isEmpty) return const IkuaiConfig();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const IkuaiConfig();
      return IkuaiConfig.fromJson(Map<String, dynamic>.from(decoded));
    } on FormatException {
      return const IkuaiConfig();
    }
  }

  Future<void> save(IkuaiConfig config) =>
      _store.setString(storageKey, jsonEncode(config.toJson()));
}

/// 隐藏终端 mac 列表（独立存储，避免保存配置时被覆盖）。
class HiddenStore {
  HiddenStore(this._store);

  static const String storageKey = 'hidden_macs';

  final KeyValueStore _store;

  /// 返回已隐藏的 mac 列表（统一小写）。
  List<String> load() {
    final raw = _store.getString(storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Object>()
          .map((e) => e.toString().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toList();
    } on FormatException {
      return [];
    }
  }

  Future<void> _save(List<String> macs) =>
      _store.setString(storageKey, jsonEncode(macs));

  /// 隐藏一台终端（大小写不敏感，自动去重）。
  Future<void> add(String mac) async {
    final macs = load();
    final key = mac.toLowerCase();
    if (key.isEmpty || macs.contains(key)) return;
    macs.add(key);
    await _save(macs);
  }

  /// 取消隐藏（不存在时静默忽略）。
  Future<void> remove(String mac) async {
    final macs = load();
    final key = mac.toLowerCase();
    if (!macs.contains(key)) return;
    macs.remove(key);
    await _save(macs);
  }
}
