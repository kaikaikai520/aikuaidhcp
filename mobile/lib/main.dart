/// 爱快 DHCP 网关切换助手（安卓版）入口。
///
/// 原生直连版：App 自身直接访问内网爱快路由器，读取 DHCP 静态分配列表，
/// 并对每台终端在预设的两个网关之间一键切换，不依赖任何服务端。
///
/// 代码由本仓库 Web 版移植而来：
/// - `web/app/ikuai_client.py` → `lib/services/ikuai_client.dart`
/// - `web/app/config.py`       → `lib/services/config_store.dart`
/// - `web/app/schemas.py`      → `lib/models/models.dart`
/// - `web/static/*`            → `lib/pages/*`、`lib/widgets/*`
library;

import 'package:flutter/material.dart';

import 'pages/home_page.dart';
import 'services/config_store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await PrefsStore.open();
  runApp(
    AikuaidhcpApp(
      configStore: ConfigStore(store),
      hiddenStore: HiddenStore(store),
    ),
  );
}

class AikuaidhcpApp extends StatelessWidget {
  const AikuaidhcpApp({
    super.key,
    required this.configStore,
    required this.hiddenStore,
  });

  final ConfigStore configStore;
  final HiddenStore hiddenStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '爱快网关切换',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: HomePage(configStore: configStore, hiddenStore: hiddenStore),
      builder: (context, child) {
        // 限制文字缩放上限，避免系统超大字体撑坏列表布局。
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
