import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../app.dart';
import '../screens/course_edit_screen.dart';
import 'data_store.dart';
import 'sound_service.dart';

/// 系统托盘：关闭窗口时隐藏到托盘，提醒在后台照常运行。
/// 托盘菜单：显示主界面 / 退出。
class TrayService {
  TrayService._();
  static final TrayService instance = TrayService._();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await windowManager.ensureInitialized();
      // 关闭窗口时不退出，改为隐藏到托盘
      await windowManager.setPreventClose(true);
      windowManager.addListener(_WindowListener());

      // 托盘图标：把打包在 assets 里的 .ico 写到临时目录再设置
      final iconData = await rootBundle.load('assets/icons/tray.ico');
      final iconFile = File('${Directory.systemTemp.path}${Platform.pathSeparator}iclass_tray.ico');
      await iconFile.writeAsBytes(iconData.buffer.asUint8List(iconData.offsetInBytes, iconData.lengthInBytes));
      await trayManager.setIcon(iconFile.path);
      await trayManager.setToolTip('iClass - 课表提醒');

      await trayManager.setContextMenu(Menu(items: [
        MenuItem(key: 'show', label: '显示主界面'),
        MenuItem(key: 'addCourse', label: '创建课程'),
        MenuItem(key: 'location', label: '选择当前位置'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出'),
      ]));
      trayManager.addListener(_TrayListener());
      _initialized = true;
    } catch (e) {
      debugPrint('托盘初始化失败: $e');
    }
  }
}

/// 用户点关闭按钮 → 触发 onWindowClose → 隐藏窗口而不是退出。
class _WindowListener extends WindowListener {
  @override
  void onWindowClose() async {
    await windowManager.hide();
  }
}

/// 托盘图标点击 / 托盘菜单点击。
class _TrayListener extends TrayListener {
  /// 显示主窗口（并置前）。
  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void onTrayIconMouseDown() async {
    // 左键：显示主窗口
    await _showWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    // 右键：弹出菜单（tray_manager 在 Windows 上不会自动弹，需手动调用）
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show':
        await _showWindow();
        break;
      case 'addCourse':
        // 创建课程：显示窗口并打开课程编辑页（新建模式）
        await _showWindow();
        appNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const CourseEditScreen()),
        );
        break;
      case 'location':
        // 选择当前位置：先回到主界面并显示窗口，再直接弹出右上角「我在哪」下拉菜单
        appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
        await _showWindow();
        // 等窗口显示、页面转场稳定后再触发，避免菜单与转场冲突
        await Future.delayed(const Duration(milliseconds: 250));
        DataStore.instance.requestLocationMenu();
        break;
      case 'quit':
        // 快速退出：先释放音频引擎（避免退出挂起），清掉托盘图标，
        // 然后不等待窗口销毁、直接用 exit(0) 结束进程——
        // Windows 会随进程终止自动清理窗口与托盘，也跳过通知等
        // Dart 层异步清理（它们优雅关闭慢会导致退出卡顿甚至未响应）。
        SoundService.instance.dispose();
        try {
          await trayManager.destroy();
        } catch (_) {}
        windowManager.setPreventClose(false);
        windowManager.destroy();
        exit(0); // Never 类型，case 到此结束
    }
  }
}
