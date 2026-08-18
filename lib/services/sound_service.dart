import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 提示音播放（assets/sounds/reminder.wav）。
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  AudioPlayer? _player;

  Future<void> play() async {
    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.play(AssetSource('sounds/reminder.wav'));
    } catch (e) {
      debugPrint('提示音播放失败: $e');
    }
  }

  /// 退出前释放音频引擎：Windows 上未释放的 AudioPlayer 会让进程退出挂起
  /// （卡几秒甚至未响应），退出时调用一次。
  void dispose() {
    try {
      _player?.dispose();
    } catch (_) {}
    _player = null;
  }
}
