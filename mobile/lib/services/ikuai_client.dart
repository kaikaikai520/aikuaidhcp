/// 爱快（iKuai）路由器 API 客户端（Dart 移植版）。
///
/// 由 Web 版 `web/app/ikuai_client.py` 完整移植，行为保持一致：
/// 登录认证（MD5 + Base64 + salt 多版本重试）、会话管理、通用调用、
/// DHCP 静态分配列表读取、网关 A/B 切换、字段兼容。
///
/// 爱快 API 关键结论（联调实测）：
/// - 登录：`POST /Action/login`，body `{username, passwd: MD5(密码),
///   pass: Base64(salt+密码), remember_password: null}`。
///   salt 前缀随固件变化（salt_123 / salt_113 / salt_11 / salt_13 …），逐个尝试。
/// - 业务：`POST /Action/call`，body `{func_name, action, param}`。
///   **成功判断（关键坑）**：不是只看 `Result` 码，而是
///   `Result == 10000`（旧版）或 `code == 0`（企业版 4.x）或 `ErrMsg == "Success"`。
/// - DHCP 静态分配：`func_name=dhcp_static`，读用
///   `TYPE=static_total,static_data`（配置视角，含网关字段）；
///   写用 edit/add，param 为平铺字段，缺 `enabled` 会报「参数错误」。
/// - 会话：登录后 `sess_key` cookie；会话过期码 10001，自动重登重试一次。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../models/models.dart';

/// 爱快 API 异常，携带错误码与可读信息。
class IkuaiError implements Exception {
  IkuaiError(this.code, this.message);

  /// 错误码：401 认证失败 / 404 记录不存在 / 503 网络不可达 / 其他为爱快返回码。
  final int code;

  /// 面向用户的可读信息。
  final String message;

  @override
  String toString() => '[$code] $message';
}

// ---- 认证编码工具（纯函数，便于单元测试）----

/// `MD5(明文密码)`，返回 32 位小写十六进制。
String md5Password(String password) =>
    md5.convert(utf8.encode(password)).toString();

/// `Base64(salt 前缀 + 明文密码)`。
String encodePass(String password, String salt) =>
    base64.encode(utf8.encode('$salt$password'));

/// 返回 `[passwd, pass]`，供登录请求体使用。
List<String> encodeCredentials(String password, String salt) =>
    [md5Password(password), encodePass(password, salt)];

// ---- 网关 A/B 决策（纯函数）----

/// 当前网关 == B → 切到 A；其余（含无法匹配）按「当前≈A」处理，切到 B。
String decideTargetGateway(String current, String gatewayA, String gatewayB) =>
    current == gatewayB ? gatewayA : gatewayB;

// ---- 字段兼容工具 ----

/// 按优先级取字段，返回非空字符串；兼容爱快多字段命名。
String getField(Map<String, dynamic> item, List<String> keys) {
  for (final key in keys) {
    final value = item[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

/// 爱快 API 客户端（网络层），只负责「与爱快通信」，不掺杂业务判断。
class IkuaiClient {
  IkuaiClient({
    required this.host,
    this.port = 80,
    this.username = '',
    this.password = '',
    this.useHttps = false,
    List<String>? saltList,
    this.timeout = const Duration(seconds: 20),
    http.Client? transport,
  }) : saltList = saltList ?? defaultSaltList,
       _transport = transport ?? buildDefaultTransport(timeout);

  static const List<String> defaultSaltList = [
    'salt_123',
    'salt_113',
    'salt_11',
    'salt_13',
  ];

  static const int successCode = 10000;
  static const int sessionExpiredCode = 10001;

  /// 默认传输层：忽略自签名 HTTPS 证书（爱快默认自签名）。
  static http.Client buildDefaultTransport(Duration timeout) {
    final inner = HttpClient();
    inner.badCertificateCallback = (cert, host, port) => true;
    inner.connectionTimeout = timeout;
    return IOClient(inner);
  }

  final String host;
  final int port;
  final String username;
  final String password;
  final bool useHttps;
  final List<String> saltList;
  final Duration timeout;

  final http.Client _transport;
  final Map<String, String> _cookies = {};

  bool _loggingIn = false;
  bool _loggedIn = false;

  /// 是否已完成登录（会话过期由 [call] 自动重登）。
  bool get isLoggedIn => _loggedIn;

  /// 基础地址，如 `http://192.168.1.1:80`。
  String get baseUrl => '${useHttps ? 'https' : 'http'}://$host:$port';

  /// 按当前配置构造客户端；便于上层在配置变更时重建。
  factory IkuaiClient.fromConfig(
    IkuaiConfig cfg, {
    http.Client? transport,
    List<String>? saltList,
  }) {
    return IkuaiClient(
      host: cfg.host.trim(),
      port: cfg.port,
      username: cfg.username,
      password: cfg.password,
      useHttps: cfg.useHttps,
      transport: transport,
      saltList: saltList,
    );
  }

  // ---- 登录 ----

  /// 仅在未登录时执行登录；已登录则跳过。
  Future<void> ensureLogin() async {
    if (!_loggedIn) await login();
  }

  /// 逐个 salt 尝试登录，全部失败则抛 [IkuaiError]（code = 401）。
  Future<void> login() async {
    if (_loggingIn) return;
    _loggingIn = true;
    try {
      final errors = <String>[];
      for (final salt in saltList) {
        try {
          await _tryLogin(salt);
          _loggedIn = true;
          return;
        } on IkuaiError catch (exc) {
          errors.add('[$salt] ${exc.message}');
        }
      }
      throw IkuaiError(401, '登录失败：${errors.join('；')}');
    } finally {
      _loggingIn = false;
    }
  }

  Future<void> _tryLogin(String salt) async {
    final credentials = encodeCredentials(password, salt);
    final body = <String, dynamic>{
      'username': username,
      'passwd': credentials[0],
      'pass': credentials[1],
      'remember_password': null,
    };
    final data = await _post('/Action/login', body);
    if (!isSuccess(data)) {
      throw IkuaiError(
        extractResult(data),
        extractErrMsg(data) ?? '登录失败',
      );
    }
    _storeSession(data);
  }

  // ---- 通用调用 ----

  /// 调用爱快业务接口；识别到会话过期会自动重登并重试一次。
  Future<dynamic> call(
    String funcName,
    String action, [
    Map<String, dynamic>? param,
  ]) async {
    final body = <String, dynamic>{
      'func_name': funcName,
      'action': action,
      'param': param ?? <String, dynamic>{},
    };
    var data = await _post('/Action/call', body);
    if (isSessionExpired(data)) {
      _loggedIn = false;
      _cookies.clear();
      await login();
      data = await _post('/Action/call', body);
    }
    if (!isSuccess(data)) {
      throw IkuaiError(
        extractResult(data),
        extractErrMsg(data) ?? '调用失败（原始返回：${summarize(data)}）',
      );
    }
    return data;
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (_cookies.isNotEmpty) {
      headers['Cookie'] = _cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
    }

    http.Response response;
    try {
      response = await _transport
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(timeout);
    } on TimeoutException {
      throw IkuaiError(503, '无法连接路由器：请求超时（${timeout.inSeconds} 秒）');
    } on IkuaiError {
      rethrow;
    } catch (exc) {
      throw IkuaiError(503, '无法连接路由器：$exc');
    }

    _captureCookies(response);
    return toJson(response);
  }

  // ---- DHCP 静态分配 ----

  /// 读取 DHCP 静态分配列表（原始字段，含 gateway/enabled/dns）。
  ///
  /// 注意：必须用 `TYPE=static_total,static_data`（前端同款参数），
  /// 才能拿到配置视角字段（gateway/enabled/dns1/dns2）；
  /// `TYPE=total,data` 是 ARP/租约视角，不含网关字段。
  Future<List<Map<String, dynamic>>> getDhcpBindings() async {
    final data = await call('dhcp_static', 'show', {
      'TYPE': 'static_total,static_data',
      'limit': '0,500',
    });
    return extractList(data);
  }

  /// 新增或编辑一条 DHCP 静态绑定记录（平铺字段）。
  Future<void> saveDhcpBinding(
    Map<String, dynamic> item, {
    required bool isEdit,
  }) async {
    await call('dhcp_static', isEdit ? 'edit' : 'add', item);
  }

  // ---- 切换网关（业务编排）----

  /// 切换指定终端的网关，返回原网关与新网关。
  Future<ToggleResult> toggleGateway(
    String mac,
    String gatewayA,
    String gatewayB,
  ) async {
    final bindings = await getDhcpBindings();
    Map<String, dynamic>? target;
    for (final item in bindings) {
      if (getField(item, ['mac']).toLowerCase() == mac.toLowerCase()) {
        target = item;
        break;
      }
    }
    if (target == null) {
      throw IkuaiError(404, '未找到该终端的静态绑定记录（MAC: $mac）');
    }

    final current = getField(target, ['gateway', 'gw']);
    final newGateway = decideTargetGateway(current, gatewayA, gatewayB);

    // edit 用配置视角的干净字段集（前端同款）；enabled 缺失会导致「参数错误」
    final rawEnabled = target['enabled'];
    final enabled =
        (rawEnabled == null ||
            rawEnabled == false ||
            rawEnabled.toString().trim().isEmpty)
        ? 'yes'
        : rawEnabled;

    final updated = <String, dynamic>{
      'id': target['id'],
      'enabled': enabled,
      'interface': target['interface'] ?? '',
      'mac': getField(target, ['mac']),
      'ip_addr': getField(target, ['ip_addr']),
      'gateway': newGateway,
      'dns1': target['dns1'] ?? '',
      'dns2': target['dns2'] ?? '',
      'comment': target['comment'] ?? '',
    };
    await saveDhcpBinding(updated, isEdit: true);
    return ToggleResult(
      mac: mac,
      oldGateway: current,
      newGateway: newGateway,
    );
  }

  /// 释放底层连接（页面销毁时调用）。
  void dispose() => _transport.close();

  // ---- 会话与解析工具 ----

  void _captureCookies(http.Response response) {
    final raw = response.headers['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    for (final piece in raw.split(',')) {
      final segment = piece.split(';').first.trim();
      final index = segment.indexOf('=');
      if (index <= 0) continue;
      _cookies[segment.substring(0, index)] = segment.substring(index + 1);
    }
  }

  /// 优先用 Set-Cookie（已自动捕获）；若响应体含 sess_key 则补存。
  void _storeSession(dynamic data) {
    if (data is Map) {
      for (final key in ['sess_key', 'SessionKey', 'session_key', 'sesskey']) {
        final value = data[key];
        if (value != null && value.toString().isNotEmpty) {
          _cookies['sess_key'] = value.toString();
          return;
        }
      }
    }
  }

  /// 解析响应体为 JSON；兼容带 `sending to kernel` 前缀的固件响应。
  static dynamic toJson(http.Response response) {
    final text = response.body;
    try {
      return jsonDecode(text);
    } on FormatException {
      var cleaned = text;
      if (cleaned.startsWith('sending to kernel')) {
        cleaned = cleaned.replaceFirst('sending to kernel', '').trim();
      }
      try {
        return jsonDecode(cleaned);
      } on FormatException {
        return {'raw': text};
      }
    }
  }

  /// 提取返回码（Result / result / code / Code / ret），无法解析返回 -1。
  static int extractResult(dynamic data) {
    if (data is Map) {
      for (final key in ['Result', 'result', 'code', 'Code', 'ret']) {
        if (!data.containsKey(key)) continue;
        final value = data[key];
        if (value is bool) continue;
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) {
          final parsed = int.tryParse(value);
          if (parsed != null) return parsed;
        }
      }
    }
    return -1;
  }

  /// 成功判断：`Result == 10000` / `code == 0` / `ErrMsg == "Success"` 三者任一。
  static bool isSuccess(dynamic data) {
    final result = extractResult(data);
    if (result == successCode || result == 0) return true;
    final msg = extractErrMsg(data);
    return msg != null && msg.trim().toLowerCase() == 'success';
  }

  /// 提取错误信息字段。
  static String? extractErrMsg(dynamic data) {
    if (data is Map) {
      for (final key in [
        'ErrMsg',
        'errmsg',
        'ErrorMsg',
        'error_msg',
        'message',
        'msg',
      ]) {
        if (data.containsKey(key) && data[key] != null) {
          return data[key].toString();
        }
      }
    }
    return null;
  }

  /// 是否为「无法解析为 JSON」的响应。
  ///
  /// [toJson] 遇到非 JSON 文本时会包装成 `{'raw': <原始文本>}`，
  /// 技术方案约定这类响应视为会话失效，需重新登录。
  static bool isUnparsedResponse(dynamic data) =>
      data is Map && data.length == 1 && data.containsKey('raw');

  /// 会话是否已过期（返回码 10001、响应非 JSON 或提示语含未登录/过期字样）。
  static bool isSessionExpired(dynamic data) {
    if (data is! Map) return true;
    if (isUnparsedResponse(data)) return true;
    if (extractResult(data) == sessionExpiredCode) return true;
    final msg = (extractErrMsg(data) ?? '').toLowerCase();
    return const ['no login', '未登录', 'expired', '过期']
        .any((k) => msg.contains(k));
  }

  /// 截断后的原始返回，便于排查。
  static String summarize(dynamic data) {
    String text;
    try {
      text = jsonEncode(data);
    } catch (_) {
      text = data.toString();
    }
    return text.length <= 200 ? text : '${text.substring(0, 200)}…';
  }

  /// 从响应中提取列表数据，兼容旧版 `Data` 与企业版 `results` 多层容器。
  static List<Map<String, dynamic>> extractList(dynamic data) {
    dynamic found;
    if (data is List) {
      found = data;
    } else if (data is Map) {
      dynamic container;
      for (final key in [
        'Data',
        'data',
        'result',
        'results',
        'static_data',
        'list',
        'items',
        'rows',
      ]) {
        if (data.containsKey(key)) {
          container = data[key];
          break;
        }
      }
      if (container is List) {
        found = container;
      } else if (container is Map) {
        for (final key in [
          'data',
          'result',
          'results',
          'static_data',
          'list',
          'items',
          'rows',
        ]) {
          if (container[key] is List) {
            found = container[key];
            break;
          }
        }
      }
    }
    if (found is! List) return const [];
    return found
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }
}
