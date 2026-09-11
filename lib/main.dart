import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/device_provider.dart';
import 'providers/router_provider.dart';
import 'screens/connect_screen.dart';
import 'screens/device_list_screen.dart';
import 'services/config_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configService = ConfigService();
  await configService.init();
  runApp(IkuaiDhcpApp(configService: configService));
}

class IkuaiDhcpApp extends StatelessWidget {
  const IkuaiDhcpApp({super.key, required this.configService});

  final ConfigService configService;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<ConfigService>.value(value: configService),
        ChangeNotifierProvider(
          create: (_) => RouterProvider(configService)..init(),
        ),
        ChangeNotifierProxyProvider<RouterProvider, DeviceProvider>(
          create: (_) => DeviceProvider(configService),
          update: (_, router, device) => device!..router = router,
        ),
      ],
      child: MaterialApp(
        title: '爱快网关切换',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        home: const RootScreen(),
      ),
    );
  }
}

/// 根据连接状态决定首页：已连接进列表页，否则进连接页。
class RootScreen extends StatelessWidget {
  const RootScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.select<RouterProvider, RouterStatus>((r) => r.status);
    switch (status) {
      case RouterStatus.connected:
        return const DeviceListScreen();
      case RouterStatus.loading:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case RouterStatus.needsConfig:
      case RouterStatus.error:
        return const ConnectScreen();
    }
  }
}
