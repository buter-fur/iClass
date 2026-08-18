import 'course.dart';
import 'day_periods.dart';
import '../utils/date_utils.dart';

/// 具体某天要上的一节课：课程 + 解析出的实际起止时间。
class CourseInstance {
  final DateTime date; // 当天 00:00
  final Course course;
  final DateTime start;
  final DateTime end;

  CourseInstance({
    required this.date,
    required this.course,
    required this.start,
    required this.end,
  });

  /// 根据课程解析当天的起止时间：
  /// 有自定义时间时直接用（结束时间不晚于开始时间视为配置错误，返回 null）；
  /// 否则按节次表解析，节次配置与课程不匹配时返回 null。
  static CourseInstance? fromCourse(Course course, DateTime date, DayPeriods dayPeriods) {
    final cs = course.customStart;
    final ce = course.customEnd;
    if (cs != null && ce != null) {
      final start = DateTime(date.year, date.month, date.day).add(parseHm(cs));
      final end = DateTime(date.year, date.month, date.day).add(parseHm(ce));
      if (!end.isAfter(start)) return null;
      return CourseInstance(date: date, course: course, start: start, end: end);
    }
    final range = dayPeriods.classTimeRange(date, course.startPeriod, course.periodCount);
    if (range == null) return null;
    return CourseInstance(date: date, course: course, start: range.$1, end: range.$2);
  }

  /// 提醒去重键："日期|课程id|开始节次"；自定义时间的课用自定义开始时间去重。
  String get key {
    final startPart = course.customStart ?? '${course.startPeriod}';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}|${course.id}|$startPart';
  }
}
