import 'dart:async';

import 'package:flutter/material.dart';

import '../models/course_instance.dart';
import '../models/day_periods.dart';
import '../models/walk_estimate.dart';
import '../services/data_store.dart';
import '../services/time_service.dart';
import '../services/walk_estimator.dart';
import '../services/week_service.dart';
import '../theme.dart';
import '../utils/date_utils.dart';
import 'course_card.dart';

/// 下一节课信息（今天剩余或未来 7 天内最近的一节）。
class NextClass {
  final CourseInstance instance;
  final String dayLabel; // "今天" / "明天" / "周三"
  final WalkEstimate estimate;

  NextClass(this.instance, this.dayLabel, this.estimate);
}

/// 找下一节课：从今天起向后 7 天，取最近一节还没结束的课。
NextClass? findNextClass() {
  final store = DataStore.instance;
  final settings = store.settings;
  final now = TimeService.instance.now();

  for (var offset = 0; offset < 7; offset++) {
    final day = DateTime(now.year, now.month, now.day).add(Duration(days: offset));
    // 没有节次配置时跳过（全局一份节次表，所有天共用）
    if (settings.periods.isEmpty) continue;

    final dayPeriods = DayPeriods(settings.periods);
    final instances = <CourseInstance>[];
    for (final c in store.courses) {
      if (!WeekService.courseActiveOn(c, day, settings)) {
        continue;
      }
      final inst = CourseInstance.fromCourse(c, day, dayPeriods);
      if (inst == null) continue;
      if (offset == 0 && !inst.end.isAfter(now)) continue; // 今天已结束的课跳过
      instances.add(inst);
    }
    instances.sort((a, b) => a.start.compareTo(b.start));
    if (instances.isEmpty) continue;

    final inst = instances.first;
    final est = WalkEstimator.estimate(
      course: inst.course,
      currentLocationNodeId: settings.currentLocationNodeId,
      topology: store.topology,
      fallbackAdvanceMinutes: settings.fallbackAdvanceMinutes,
    );
    final dayLabel = offset == 0
        ? '今天'
        : offset == 1
            ? '明天'
            : weekdayName(day.weekday);
    return NextClass(inst, dayLabel, est);
  }
  return null;
}

/// 今天正在进行的课 + 紧接着的下一节（供"正在上课"提示用）。
class TodayClasses {
  final CourseInstance? current; // 正在进行的课（开始 <= now < 结束）
  final CourseInstance? next; // 今天紧接着的一节（可能没有）

  TodayClasses(this.current, this.next);
}

/// 找今天正在进行的课，以及它之后的下一节。
TodayClasses findTodayClasses() {
  final store = DataStore.instance;
  final settings = store.settings;
  final now = TimeService.instance.now();
  if (settings.periods.isEmpty) return TodayClasses(null, null);

  final today = DateTime(now.year, now.month, now.day);
  final dayPeriods = DayPeriods(settings.periods);
  final instances = <CourseInstance>[];
  for (final c in store.courses) {
    if (!WeekService.courseActiveOn(c, today, settings)) continue;
    final inst = CourseInstance.fromCourse(c, today, dayPeriods);
    if (inst == null) continue;
    instances.add(inst);
  }
  instances.sort((a, b) => a.start.compareTo(b.start));

  CourseInstance? current;
  for (final inst in instances) {
    if (!inst.start.isAfter(now) && inst.end.isAfter(now)) {
      current = inst;
      break;
    }
  }
  CourseInstance? next;
  if (current != null) {
    for (final inst in instances) {
      if (inst.start.isAfter(current.end)) {
        next = inst;
        break;
      }
    }
  }
  return TodayClasses(current, next);
}

/// 主界面顶部的"下一节课"卡片：实时显示步行时间与出发倒计时；
/// 正在上课时切换为"本节课"信息（名称 / 时间时长教师 / 下一节课）。
/// 下一节课仅在距离上课不足 4 小时时显示，太远则显示休息文案。
class NextClassCard extends StatefulWidget {
  const NextClassCard({super.key});

  @override
  State<NextClassCard> createState() => _NextClassCardState();
}

class _NextClassCardState extends State<NextClassCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 每 30 秒刷新一次倒计时
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DataStore.instance,
      builder: (context, _) {
        final next = findNextClass();
        final today = findTodayClasses();
        final now = TimeService.instance.now();
        // 下一节课提示只在距离上课不足 4 小时时触发，太远则显示休息文案
        final showNext = next != null &&
            next.instance.start.isAfter(now) &&
            next.instance.start.difference(now) < const Duration(hours: 4);
        return Card(
          elevation: 0,
          color: context.iclColors.infoCardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: today.current != null
                ? _inClassContent(today.current!, today.next)
                : showNext
                    ? _content(next)
                    : _restRow(),
          ),
        );
      },
    );
  }

  /// 没有临近的课时：休息文案 + 🎉。
  Widget _restRow() {
    return Row(
      children: [
        const Text('🎉', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        const Text('当前没有课，好好休息呀~'),
      ],
    );
  }

  Widget _content(NextClass next) {
    final inst = next.instance;
    final course = inst.course;
    final settings = DataStore.instance.settings;
    final now = TimeService.instance.now();
    final desired = inst.start.subtract(Duration(minutes: settings.earlyMinutes));

    return Row(
      children: [
        Icon(Icons.notifications_active_outlined, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '下一节课 · ${next.dayLabel}: ${course.name}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatTime(inst.start)} 开始'
                '${course.room.isEmpty ? '' : ' · ${course.room}'}'
                ' · ${next.estimate.hint}',
                style: const TextStyle(fontSize: 12.5),
              ),
              Text(
                '请于 ${formatTime(desired)} 前到达',
                style: TextStyle(fontSize: 11, color: context.iclColors.textSecondary),
              ),
            ],
          ),
        ),
        Text(
          _countdownText(now, inst.start),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: now.isBefore(inst.start)
                ? Theme.of(context).colorScheme.primary
                : Colors.redAccent,
          ),
        ),
      ],
    );
  }

  /// 正在上课时的卡片：大标题 = 本节课名称；
  /// 第二行 = 起止时间 · 时长 · 教师；第三行 = 下一节课名称与地点。
  Widget _inClassContent(CourseInstance current, CourseInstance? next) {
    final course = current.course;
    final now = TimeService.instance.now();
    final duration = current.end.difference(current.start).inMinutes;
    final nextPlace = next == null ? null : CourseCard.placeText(next.course);
    return Row(
      children: [
        // 与课表卡片同色的小圆点，表明正在上的是哪门课
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: CourseCard.colorFor(course), shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(course.name,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 3),
              Text(
                [
                  '${formatTime(current.start)}-${formatTime(current.end)}',
                  '时长 $duration 分钟',
                  if (course.teacher.isNotEmpty) course.teacher,
                ].join(' · '),
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 2),
              Text(
                next == null
                    ? '下节没有课啦~'
                    : '下一节：${next.course.name}'
                        '${nextPlace != null ? ' · $nextPlace' : ''}',
                style: TextStyle(fontSize: 11.5, color: context.iclColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('距下课', style: TextStyle(fontSize: 11, color: context.iclColors.textSecondary)),
            Text(
              _countdownText(now, current.end),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _countdownText(DateTime now, DateTime start) {
    final diff = start.difference(now);
    if (diff.isNegative) return '进行中';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟';
    return '${diff.inHours} 小时 ${diff.inMinutes % 60} 分';
  }
}
