import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/data_store.dart';
import '../services/reminder_engine.dart';
import '../utils/date_utils.dart';

/// 删除课程确认对话框：两种删除方式。
///
/// - 删除全部：移除这条课程过去与未来的全部课次（不同时间段的相同课程不受影响）；
/// - 删除本节：只删除 [occurrenceDate] 这一天的课次，其余课次不变
///   （把当天写入课程的 excludedDates）。
///
/// [occurrenceDate] 为 null 时只有「删除全部」；不重复课只有一次课，直接整条删除。
/// 返回 'all' / 'occurrence'，取消返回 null。
Future<String?> showDeleteCourseDialog(
  BuildContext context, {
  required Course course,
  DateTime? occurrenceDate,
}) async {
  final once = course.parity == 'once';
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('删除课程'),
      content: once
          ? Text('「${course.name}」是不重复课程，只有一次课，确定删除吗？')
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '「${course.name}」（${weekdayName(course.dayOfWeek)}）',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                if (occurrenceDate != null) ...[
                  const Text('· 删除全部：移除这条课程过去与未来的全部课次，其他课程不受影响'),
                  Text(
                    '· 删除本节：只删除 ${formatDate(occurrenceDate)}'
                    '（${weekdayName(occurrenceDate.weekday)}）这一次，其余课次保留',
                  ),
                ] else
                  const Text('删除全部：移除这条课程过去与未来的全部课次，其他课程不受影响'),
              ],
            ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        if (!once && occurrenceDate != null)
          OutlinedButton(
            onPressed: () => Navigator.pop(context, 'occurrence'),
            child: const Text('删除本节'),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(context, 'all'),
          child: Text(once ? '删除' : '删除全部'),
        ),
      ],
    ),
  );
  if (choice == null) return null;
  if (choice == 'occurrence') {
    await DataStore.instance.deleteCourseOccurrence(course, occurrenceDate!);
  } else {
    await DataStore.instance.deleteCourse(course.id);
  }
  ReminderEngine.instance.tick();
  return choice;
}
