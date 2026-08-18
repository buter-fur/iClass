import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'services/data_store.dart';
import 'theme.dart';

/// 全局导航 key：托盘菜单等窗口外逻辑用它跳转页面。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// 应用根组件：浅色/深色双主题（设置里切换，或跟随系统）+ 中文本地化。
class IClassApp extends StatelessWidget {
  const IClassApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 主题模式存在设置里：改动时 DataStore 通知，这里重建立即生效
    return ListenableBuilder(
      listenable: DataStore.instance,
      builder: (context, _) {
        final mode = DataStore.instance.settings.themeMode;
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          title: 'iClass',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(Brightness.light),
          darkTheme: _buildTheme(Brightness.dark),
          themeMode: switch (mode) {
            'dark' => ThemeMode.dark,
            'system' => ThemeMode.system,
            _ => ThemeMode.light,
          },
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const HomeScreen(),
        );
      },
    );
  }

  /// 浅色/深色两套主题：结构完全一致只换颜色；自定义语义色挂在 extensions 上。
  ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF5B9BD5), // 淡蓝主色
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // 接近白色的淡蓝（深色下为近黑的蓝灰）
      scaffoldBackgroundColor: dark ? const Color(0xFF11151B) : const Color(0xFFF4F8FC),
      fontFamily: 'Microsoft YaHei',
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF1B222C) : const Color(0xFFE8F1FA),
        foregroundColor: dark ? const Color(0xFFE4EBF3) : const Color(0xFF2C3E50),
        elevation: 0,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5B9BD5)),
      ),
      extensions: [dark ? IClassColors.dark : IClassColors.light],
    );
  }
}
