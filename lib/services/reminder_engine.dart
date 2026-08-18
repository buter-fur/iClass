import 'dart:async';

import '../models/app_settings.dart';
import '../models/course_instance.dart';
import '../models/day_periods.dart';
import '../models/walk_estimate.dart';
import '../utils/date_utils.dart';
import '../widgets/course_card.dart';
import 'data_store.dart';
import 'notification_service.dart';
import 'sound_service.dart';
import 'time_service.dart';
import 'walk_estimator.dart';
import 'week_service.dart';

/// 提醒引擎：每 2 分钟检查一次"现在出发是否来得及"，来不及立即提醒。
/// 每节课只提醒一次（fired key 持久化，重启不重复）。
///
/// 关键规则（与需求文档确认）：
/// - desired（期望到达）= 上课时间 − 提前分钟
/// - ideal（理想提醒时刻）= 有步行时长 ? desired − 步行 : 上课时间 − 固定提前
/// - 检查窗口开始 = min(上课前 20 分钟, ideal − 5 分钟) —— 步行时间长时提前检查
/// - 窗口内：现在出发的预计到达 > desired → 立即提醒
/// - 已上课（迟到）且没提醒过 → 补提醒一次；课已结束 → 不再提醒
class ReminderEngine {
  ReminderEngine._();
  static final ReminderEngine instance = ReminderEngine._();

  Timer? _timer;
  bool _running = false;

  void start() {
    if (_running) return;
    _running = true;
    tick(); // 启动立即检查一次（可能刚开机就处于提醒窗口内）
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => tick());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  /// 立即执行一次检查。设置/课程/拓扑/当前位置变化后调用，无需等下一个 2 分钟。
  void tick() {
    final store = DataStore.instance;
    final settings = store.settings;
    final now = TimeService.instance.now();
    final today = DateTime(now.year, now.month, now.day);

    // 没有节次配置时跳过（全局一份节次表，所有天共用）
    if (settings.periods.isEmpty) return;

    // 只收集"今天"要上的课（星期 + 周次范围 + 单双周过滤），别把其他日期的课搞串
    final dps = DayPeriods(settings.periods);
    final upcoming = <CourseInstance>[];
    var inClass = false; // 提醒触发时是否仍在上课（此时只通知不响铃）
    for (final course in store.courses) {
      if (!WeekService.courseActiveOn(course, now, settings)) {
        continue;
      }
      final instance = CourseInstance.fromCourse(course, today, dps);
      if (instance == null) continue; // 节次配置与课程不匹配，跳过
      if (!instance.start.isAfter(now) && instance.end.isAfter(now)) {
        inClass = true; // 有课正在进行（含已提醒过的课）
      }
      if (settings.firedReminderKeys.contains(instance.key)) continue; // 已提醒过
      if (!now.isBefore(instance.end)) continue; // 已结束，错过不再提醒
      upcoming.add(instance);
    }
    if (upcoming.isEmpty) return;

    // 每次 tick 只提醒即将上课的下一节（按上课时间最早的一节），
    // 后面的课等轮到它成为"下一节"时再提醒，避免多节课一起出发提醒
    upcoming.sort((a, b) => a.start.compareTo(b.start));
    final next = upcoming.first;

    final (shouldFire, est) = _evaluate(next, settings, now);
    if (shouldFire) _fire(next, est, now, settings, inClass: inClass);
  }

  /// 判断是否该提醒，并返回本次的步行估算（供提醒内容使用）。
  (bool, WalkEstimate) _evaluate(
      CourseInstance instance, AppSettings settings, DateTime now) {
    final est = WalkEstimator.estimate(
      course: instance.course,
      currentLocationNodeId: settings.currentLocationNodeId,
      topology: DataStore.instance.topology,
      fallbackAdvanceMinutes: settings.fallbackAdvanceMinutes,
    );

    final desired = instance.start.subtract(Duration(minutes: settings.earlyMinutes));
    final ideal = est.walkMinutes != null
        ? desired.subtract(Duration(minutes: est.walkMinutes!))
        : instance.start.subtract(Duration(minutes: settings.fallbackAdvanceMinutes));

    // 检查窗口开始时间 = min(上课前 20 分钟, ideal − 5 分钟)
    final tMinus20 = instance.start.subtract(const Duration(minutes: 20));
    final idealMinus5 = ideal.subtract(const Duration(minutes: 5));
    final windowStart = idealMinus5.isBefore(tMinus20) ? idealMinus5 : tMinus20;

    if (now.isBefore(windowStart)) return (false, est); // 窗口未开始
    if (!now.isBefore(instance.end)) return (false, est); // 课已结束，错过不再提醒

    if (!now.isBefore(instance.start)) return (true, est); // 已上课（迟到），补提醒一次

    if (est.walkMinutes != null) {
      // 现在出发的预计到达时间 > 期望到达时间 → 立即提醒
      return (now.add(Duration(minutes: est.walkMinutes!)).isAfter(desired), est);
    }
    // 无步行时长 → 到理想提醒时刻就提醒
    return (!now.isBefore(ideal), est);
  }

  /// 触发提醒：系统通知 + 提示音，然后写入 fired key（立即持久化）。
  /// 迟到补发（已上课）时：不播放提示音，内容只保留课程名 / 上课时间 / 地点。
  /// 提醒触发时仍在上一节课中（[inClass]）：只发通知不响铃，避免打扰课堂。
  void _fire(
      CourseInstance instance, WalkEstimate est, DateTime now, AppSettings settings,
      {bool inClass = false}) {
    final course = instance.course;
    final desired = instance.start.subtract(Duration(minutes: settings.earlyMinutes));
    final late = !now.isBefore(instance.start);
    final place = CourseCard.placeText(course);

    final title = late ? 'iClass：${course.name} 已上课' : 'iClass：该出发了！';
    final body = late
        ? [
            '本节课：${course.name}',
            '上课时间：${formatTime(instance.start)}',
            if (place != null) '地点：$place',
          ].join('\n')
        : [
            '下一节课：${course.name}',
            '上课时间：${formatTime(instance.start)}${course.room.isEmpty ? '' : '（${course.room}）'}',
            '请于 ${formatTime(desired)} 前到达',
            est.walkMinutes != null ? '步行约 ${est.walkMinutes} 分钟' : est.hint,
          ].join('\n');

    if (settings.notificationEnabled) {
      NotificationService.instance.show(title, body);
    }
    // 迟到补发、上课中触发的出发提醒都不响铃，只发通知
    if (settings.soundEnabled && !late && !inClass) {
      SoundService.instance.play();
    }
    DataStore.instance.markFired(instance.key);
  }

  /// 测试提醒：直接发一条示例通知 + 声音，不写 fired key，不影响去重。
  Future<void> fireTest() async {
    final settings = DataStore.instance.settings;
    final now = TimeService.instance.now();
    final title = 'iClass：测试提醒';
    final body = [
      '这是一条测试提醒（当前时间 ${formatTime(now)}）',
      '如果收到通知和声音，说明提醒功能正常',
    ].join('\n');
    if (settings.notificationEnabled) {
      await NotificationService.instance.show(title, body);
    }
    if (settings.soundEnabled) {
      await SoundService.instance.play();
    }
  }
}
