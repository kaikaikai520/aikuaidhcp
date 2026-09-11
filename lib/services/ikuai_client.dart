import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import '../models/router_config.dart';

/// 爱快 API 异常，携带错误码与可读信息。
///
/// UI 层只消费友好文案，不暴露堆栈。
class IkuaiException implements Exception {
  const IkuaiException(this.code, this.message);

  /// 错误码（对应爱快 `Result`，或本客户端自定义的网络错误码）。
  final int code;

  /// 可读的错误信息。
  final String message;

  @override
  String toString() => 'IkuaiException($code): $message';
}

/// 爱快登录认证编码工具（纯函数，便于单元测试）。
class IkuaiAuth {
  IkuaiAuth._();

  /// `MD5(明文密码)`，返回 32 位小写十六进制字符串。
  static String md5Password(String password) =>
      md5.convert(utf8.encode(password)).toString();

  /// `Base64(salt 前缀 + 明文密码)`。
  ///
  /// 爱快前端 JS 校验用该编码，salt 前缀随固件版本变化（如 `salt_11`、
  /// `salt_113` 等），登录时需逐个尝试。
  static String encodePass(String password, String salt) =>
      base64Encode(utf8.encode('$salt$password'));

  /// 返回 `(passwd, pass)` 元组，供登录请求体使用。
  static (String, String) encodeCredentials(String password, String salt) =>
      (md5Password(password), encodePass(password, salt));
}

/// 爱快网络层接口，抽象出来便于依赖注入与单元测试。
abstract class IkuaiApi {
  Future<void> login();

  /// 通用业务调用，返回服务端响应（成功时）。
  Future<dynamic> call(String funcName, String action,
      [Map<String, dynamic>? param]);

  /// 读取 DHCP 静态分配列表（原始字段）。
  Future<List<Map<String, dynamic>>> getDhcpBindings();

  /// 保存（新增或编辑）一条 DHCP 静态绑定记录。
  Future<void> saveDhcpBinding(Map<String, dynamic> item,
      {required bool isEdit});
}

/// 爱快 API 客户端（网络层）。
///
/// 职责：登录认证、会话管理、通用调用、会话过期自动重登。
/// 只负责「与爱快通信」，不掺杂业务判断。
class IkuaiClient implements IkuaiApi {
  IkuaiClient({
    required RouterConfig config,
    Dio? dio,
    List<String>? saltList,
  })  : _config = config,
        _saltList = saltList ?? defaultSaltList,
        _dio = dio ?? _buildDio(config) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          _attachHeaders(options);
          handler.next(options);
        },
      ),
    );
  }

  /// 爱快各固件版本可能使用的 salt 前缀，登录时逐个尝试。
  ///
  /// 实测中常见的取值有 `salt_11`、`salt_113`、`salt_123` 等，若遇其他
  /// 版本，可在此处追加。
  static const List<String> defaultSaltList = [
    'salt_123',
    'salt_113',
    'salt_11',
    'salt_13',
  ];

  /// 登录成功返回码。
  static const int successCode = 10000;

  /// 「未登录 / 会话过期」错误码（用于触发自动重登）。
  static const int sessionExpiredCode = 10001;

  /// 凭据错误（用户名或密码错误）。
  static const int errUnauthorized = 401;

  /// 网络不可达。
  static const int errNetwork = 503;

  /// 请求超时。
  static const int errTimeout = 504;

  /// 证书校验失败。
  static const int errCert = 495;

  /// 资源未找到（如未找到静态绑定记录）。
  static const int errNotFound = 404;

  final RouterConfig _config;
  final List<String> _saltList;
  final Dio _dio;

  String? _sessionCookie;
  bool _loggingIn = false;

  /// 当前会话 Cookie（供测试与调试观察）。
  String? get sessionCookie => _sessionCookie;

  static Dio _buildDio(RouterConfig config) {
    final dio = Dio(
      BaseOptions(
        baseUrl: config.baseUrl,
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 20),
        followRedirects: false,
        responseType: ResponseType.json,
      ),
    );
    // 爱快默认使用自签名 HTTPS 证书，忽略证书校验。
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.badCertificateCallback = (_, _, _) => true;
        return client;
      },
    );
    return dio;
  }

  void _attachHeaders(RequestOptions options) {
    options.headers['Content-Type'] = 'application/json;charset=UTF-8';
    options.headers['Accept'] = 'application/json, text/plain, */*';
    if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
      options.headers['Cookie'] = _sessionCookie;
    }
  }

  @override
  Future<void> login() async {
    if (_loggingIn) return;
    _loggingIn = true;
    try {
      final errors = <String>[];
      for (final salt in _saltList) {
        try {
          await _tryLogin(salt);
          return;
        } on IkuaiException catch (e) {
          if (e.code == errNetwork ||
              e.code == errTimeout ||
              e.code == errCert) {
            // 网络 / 超时 / 证书问题，换 salt 无意义，直接抛出。
            rethrow;
          }
          errors.add(e.message);
        }
      }
      throw IkuaiException(errUnauthorized, '用户名或密码错误');
    } finally {
      _loggingIn = false;
    }
  }

  Future<void> _tryLogin(String salt) async {
    final (passwd, pass) =
        IkuaiAuth.encodeCredentials(_config.password, salt);
    final body = <String, dynamic>{
      'username': _config.username,
      'passwd': passwd,
      'pass': pass,
      'remember_password': null,
    };

    final Response<dynamic> resp;
    try {
      resp = await _dio.post<dynamic>('/Action/login', data: body);
    } on DioException catch (e) {
      throw _toIkuaiException(e);
    }

    final data = resp.data;
    final result = _extractResult(data);
    if (result != successCode) {
      throw IkuaiException(result, _extractErrMsg(data) ?? '登录失败');
    }

    _sessionCookie = _extractSessionCookie(resp, data);
  }

  @override
  Future<dynamic> call(String funcName, String action,
      [Map<String, dynamic>? param]) async {
    final body = <String, dynamic>{
      'func_name': funcName,
      'action': action,
      'param': ?param,
    };

    Response<dynamic> resp;
    try {
      resp = await _dio.post<dynamic>('/Action/call', data: body);
    } on DioException catch (e) {
      throw _toIkuaiException(e);
    }

    // 会话过期：自动重登并重试一次。
    if (_isSessionExpired(resp.data)) {
      await login();
      try {
        resp = await _dio.post<dynamic>('/Action/call', data: body);
      } on DioException catch (e) {
        throw _toIkuaiException(e);
      }
    }

    final data = resp.data;
    final result = _extractResult(data);
    if (result == successCode) {
      return data;
    }
    throw IkuaiException(result, _extractErrMsg(data) ?? '调用失败');
  }

  @override
  Future<List<Map<String, dynamic>>> getDhcpBindings() async {
    final data = await call('dhcp_addr_bind', 'show', {'TYPE': 'data'});
    return _extractList(data);
  }

  @override
  Future<void> saveDhcpBinding(Map<String, dynamic> item,
      {required bool isEdit}) async {
    await call(
      'dhcp_addr_bind',
      isEdit ? 'edit' : 'add',
      {'data': item},
    );
  }

  // ---- 解析工具 ----

  int _extractResult(dynamic data) {
    if (data is Map) {
      final v = data['Result'] ??
          data['result'] ??
          data['code'] ??
          data['Code'] ??
          data['ret'];
      if (v is int) return v;
      if (v is String) return int.tryParse(v) ?? -1;
      if (v is num) return v.toInt();
    }
    return -1;
  }

  String? _extractErrMsg(dynamic data) {
    if (data is Map) {
      final v = data['ErrMsg'] ?? data['errmsg'] ?? data['message'] ?? data['msg'];
      return v?.toString();
    }
    return null;
  }

  /// 判断是否为「会话过期」：返回码等于未登录码，或返回非 JSON（多为登录页跳转）。
  bool _isSessionExpired(dynamic data) {
    if (data is! Map) return true;
    return _extractResult(data) == sessionExpiredCode;
  }

  /// 从登录响应中提取会话 Cookie。
  String? _extractSessionCookie(Response<dynamic> resp, dynamic data) {
    // 优先从 Set-Cookie 响应头取值。
    final setCookies = resp.headers['set-cookie'];
    if (setCookies != null && setCookies.isNotEmpty) {
      for (final c in setCookies) {
        final raw = c.toString();
        if (raw.toLowerCase().contains('sess_key') ||
            raw.toLowerCase().contains('session')) {
          return raw.split(';').first;
        }
      }
      // 兜底：取第一个 cookie。
      return setCookies.first.toString().split(';').first;
    }

    // 其次从响应体 JSON 中取值。
    if (data is Map) {
      final key = data['sess_key'] ??
          data['SessionKey'] ??
          data['session_key'] ??
          data['sesskey'];
      if (key != null && key.toString().isNotEmpty) {
        return 'sess_key=$key';
      }
    }
    return null;
  }

  /// 从业务响应中提取列表数据（兼容多种容器字段）。
  List<Map<String, dynamic>> _extractList(dynamic data) {
    dynamic list;
    if (data is Map) {
      final d = data['Data'] ?? data['data'] ?? data['result'];
      if (d is List) {
        list = d;
      } else if (d is Map) {
        list = d['data'] ?? d['list'] ?? d['items'] ?? d['rows'] ?? [];
      } else {
        list = data['list'] ?? data['items'] ?? data['rows'] ?? [];
      }
    } else if (data is List) {
      list = data;
    }

    if (list is! List) return [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  IkuaiException _toIkuaiException(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return IkuaiException(errTimeout, '连接路由器超时');
      case DioExceptionType.connectionError:
        return IkuaiException(errNetwork, '无法连接路由器，请检查网络与地址');
      case DioExceptionType.badCertificate:
        return IkuaiException(errCert, '证书校验失败');
      case DioExceptionType.badResponse:
        final status = e.response?.statusCode;
        if (status != null && (status == 401 || status == 403)) {
          return IkuaiException(errUnauthorized, '用户名或密码错误');
        }
        return IkuaiException(status ?? -1, '请求失败（HTTP $status）');
      default:
        return IkuaiException(-1, e.message ?? '网络请求失败');
    }
  }
}
