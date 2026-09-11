import 'ikuai_client.dart';

/// 将异常映射为面向用户的可读文案，不暴露堆栈。
String friendlyErrorMessage(Object e) {
  if (e is IkuaiException) {
    switch (e.code) {
      case IkuaiClient.errUnauthorized:
        return '用户名或密码错误';
      case IkuaiClient.errNetwork:
        return '无法连接路由器，请检查网络与地址';
      case IkuaiClient.errTimeout:
        return '连接路由器超时，请检查网络';
      case IkuaiClient.errCert:
        return '证书校验失败，请确认是否已允许自签名证书';
      case IkuaiClient.errNotFound:
        return '未找到对应终端记录，请刷新后重试';
      default:
        return e.message;
    }
  }
  return e.toString();
}
