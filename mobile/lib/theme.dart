/// 应用主题与配色。
///
/// 与 Web 版 `web/static/style.css` 的 CSS 变量保持一致，保证两端观感一致。
library;

import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color bg = Color(0xFFF5F6F8);
  static const Color card = Color(0xFFFFFFFF);
  static const Color text = Color(0xFF1F2329);
  static const Color textSub = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
  static const Color primary = Color(0xFF2563EB);
  static const Color primaryDark = Color(0xFF1D4ED8);

  /// 网关 A 侧标识色。
  static const Color gatewayA = Color(0xFF2563EB);

  /// 网关 B 侧标识色。
  static const Color gatewayB = Color(0xFFEA580C);

  static const Color danger = Color(0xFFDC2626);
  static const Color ok = Color(0xFF16A34A);

  /// 网关 A 胶囊底色。
  static const Color chipA = Color(0xFFE8EFFE);

  /// 网关 B 胶囊底色。
  static const Color chipB = Color(0xFFFDEFE7);

  /// 中性胶囊底色。
  static const Color chipNeutral = Color(0xFFF3F4F6);
}

/// 构建全局 Material 3 主题。
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    error: AppColors.danger,
    surface: AppColors.card,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.card,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      shape: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: AppColors.card,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.primary, width: 1.4),
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: AppColors.text),
      bodySmall: TextStyle(color: AppColors.textSub),
    ),
  );
}

/// 等宽字体样式（IP / MAC 展示用）。
const TextStyle monospaceStyle = TextStyle(
  fontFamily: 'monospace',
  fontFamilyFallback: ['Roboto Mono', 'monospace'],
);
