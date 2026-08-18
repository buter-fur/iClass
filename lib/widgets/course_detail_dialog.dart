import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/walk_estimate.dart';
import '../services/data_store.dart';
import '../services/walk_estimator.dart';
import '../theme.dart';
import '../utils/date_utils.dart';
import 'course_card.dart';

/// 课程详情小窗口：左键点课程卡片弹出（卡片式小窗，非全屏页面）。
/// 显示课程名称（标题）/ 课程时间 / 课程地点 / 授课教师 / 预计到达所需时间。
/// 预计到达一行在"我的位置"与"课程地点"都设置时才显示（任一缺失整行隐藏）。
/// 点「编辑课程」返回 'edit'（由调用方打开编辑页），其余返回 null。
Future<String?> showCourseDetailDialog(
  BuildContext context, {
  required Course course,
  required DateTime occurrenceDate,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) {
      final store = DataStore.instance;
      final settings = store.settings;

      // 课程时间：日期（星期）+ 节次/自定义时间
      final t = CourseCard.timeText(course);
      final timeValue = '${formatDate(occurrenceDate)}（${weekdayName(occurrenceDate.weekday)}）'
          '${t == null ? '' : ' · $t'}';

      // 预计到达所需时间：我的位置与课程地点**都设置**时才算得出，否则整行不显示
      final est = WalkEstimator.estimate(
        course: course,
        currentLocationNodeId: settings.currentLocationNodeId,
        topology: store.topology,
        fallbackAdvanceMinutes: settings.fallbackAdvanceMinutes,
      );
      final String? walkText = switch (est.source) {
        WalkEstimateSource.dijkstra => '步行约 ${est.walkMinutes} 分钟',
        WalkEstimateSource.straightLine =>
          '约 ${est.walkMinutes} 分钟（两点未连通，按直线距离估算）',
        WalkEstimateSource.sameNode => '0 分钟（当前位置就是上课地点）',
        _ => null, // 任一位置缺失 → 整行不显示
      };

      return AlertDialog(
        title: Row(
          children: [
            // 与课表卡片同色的小色块，一眼对上是哪门课
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: CourseCard.colorFor(course),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(course.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow(context, Icons.access_time_outlined, '课程时间', timeValue),
              _infoRow(context, Icons.place_outlined, '课程地点',
                  CourseCard.placeText(course) ?? '未填写'),
              _infoRow(context, Icons.person_outline, '授课教师',
                  course.teacher.isEmpty ? '未填写' : course.teacher),
              if (walkText != null)
                _infoRow(context, Icons.directions_walk, '预计到达所需时间', walkText),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'edit'),
            child: const Text('编辑课程'),
          ),
        ],
      );
    },
  );
}

/// 一行详情：图标 + 小字标签 + 内容。
Widget _infoRow(BuildContext context, IconData icon, String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 11, color: context.iclColors.textSecondary)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
    ),
  );
}
