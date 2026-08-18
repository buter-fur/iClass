import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';

/// 开机自启动（Windows 注册表 HKCU Run 键）。
class AutostartService {
  AutostartService._();
  static final AutostartService instance = AutostartService._();

  bool _ready = false;

  Future<void> init() async {
    try {
      launchAtStartup.setup(
        appName: 'iClass',
        appPath: Platform.resolvedExecutable,
      );
      _ready = true;
    } catch (e) {
      debugPrint('自启动初始化失败: $e');
    }
  }

  Future<bool> isEnabled() async {
    if (!_ready) return false;
    try {
      return await launchAtStartup.isEnabled();
    } catch (_) {
      return false;
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    if (!_ready) return false;
    try {
      if (enabled) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
      return (await launchAtStartup.isEnabled()) == enabled;
    } catch (e) {
      debugPrint('设置自启动失败: $e');
      return false;
    }
  }

  /// 启动时同步：设置里开了自启但注册表没有 → 补上（如用户重装/移动了程序）。
  Future<void> syncFromSettings(bool autoStart) async {
    if (await isEnabled() != autoStart) {
      await setEnabled(autoStart);
    }
  }
}
