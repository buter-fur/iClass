import 'period.dart';
import '../utils/date_utils.dart';

/// 某一天（星期几）的节次表，提供按节次查时间、解析上课起止等辅助方法。
class DayPeriods {
  /// 按节次 index 从小到大排序的节次列表。
  final List<Period> periods;

  DayPeriods(this.periods);

  bool get isEmpty => periods.isEmpty;

  /// 第 [index] 节的时段，不存在返回 null。
  Period? periodAt(int index) {
    for (final p in periods) {
      if (p.index == index) return p;
    }
    return null;
  }

  /// 该天总节数（= 最大节次 index）。
  int get maxPeriodIndex => periods.isEmpty ? 0 : periods.map((p) => p.index).reduce((a, b) => a > b ? a : b);

  /// 第 [startPeriod] 节开始上、连上 [count] 节：返回 (开始, 结束)。
  /// 任何一节不存在时返回 null（表示节次配置与课程不匹配）。
  (DateTime, DateTime)? classTimeRange(DateTime date, int startPeriod, int count) {
    final first = periodAt(startPeriod);
    final last = periodAt(startPeriod + count - 1);
    if (first == null || last == null) return null;
    final start = DateTime(date.year, date.month, date.day)
        .add(parseHm(first.start));
    final end = DateTime(date.year, date.month, date.day)
        .add(parseHm(last.end));
    return (start, end);
  }
}
