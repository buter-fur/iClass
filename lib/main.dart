import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/autostart_service.dart';
import 'services/data_store.dart';
import 'services/notification_service.dart';
import 'services/reminder_engine.dart';
import 'services/tray_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 窗口：尺寸、最小尺寸、居中
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    size: Size(1200, 760),
    minimumSize: Size(900, 600),
    center: true,
    title: 'iClass',
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  // 加载数据（课程 / 拓扑 / 设置）
  await DataStore.instance.loadAll();

  // 通知、托盘、开机自启
  await NotificationService.instance.init();
  await TrayService.instance.init();
  await AutostartService.instance.init();
  await AutostartService.instance
      .syncFromSettings(DataStore.instance.settings.autoStart);

  // 提醒引擎：每 2 分钟检查一次
  ReminderEngine.instance.start();

  runApp(const IClassApp());
}
