import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aikuaidhcp/services/ikuai_client.dart';

void main() {
  group('IkuaiAuth 认证编码', () {
    test('md5Password 返回 32 位小写十六进制', () {
      final hash = IkuaiAuth.md5Password('admin');
      expect(hash, hasLength(32));
      expect(hash, '21232f297a57a5a743894a0e4a801fc3');
    });

    test('encodePass 为 Base64(salt+password)', () {
      final pass = IkuaiAuth.encodePass('123456', 'salt_11');
      expect(pass, base64Encode(utf8.encode('salt_11123456')));
    });

    test('encodeCredentials 返回 (passwd, pass) 元组', () {
      final (passwd, pass) = IkuaiAuth.encodeCredentials('123456', 'salt_11');
      expect(passwd, IkuaiAuth.md5Password('123456'));
      expect(pass, IkuaiAuth.encodePass('123456', 'salt_11'));
    });
  });

  group('IkuaiException', () {
    test('携带错误码与信息', () {
      const e = IkuaiException(401, '用户名或密码错误');
      expect(e.code, 401);
      expect(e.message, '用户名或密码错误');
      expect(e.toString(), contains('401'));
    });
  });
}
