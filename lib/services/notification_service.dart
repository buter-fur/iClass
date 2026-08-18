import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Windows 系统通知（flutter_local_notifications）。
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// 初始化；成功返回 true。失败时应用仍可运行（提示音兜底）。
  Future<bool> init() async {
    try {
      const settings = InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: 'iClass',
          appUserModelId: 'com.iclass.iclass',
          guid: '9f4c2a3e-8b1d-4e6f-a2c5-7d0b3e6f9a1c',
        ),
      );
      final ok = await _plugin.initialize(settings: settings);
      _ready = ok ?? false;
      return _ready;
    } catch (e) {
      debugPrint('通知初始化失败: $e');
      return false;
    }
  }

  Future<void> show(String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: 1,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(windows: WindowsNotificationDetails()),
      );
    } catch (e) {
      debugPrint('通知发送失败: $e');
    }
  }
}
