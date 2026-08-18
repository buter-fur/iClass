import '../utils/date_utils.dart';
import 'period_break.dart';

/// 一节的时间段。开始/结束时间用 "HH:mm" 字符串保存，与 JSON 一致。
/// [name] 为自定义节次名称（如"早读"），空字符串表示用默认的"第 N 节"。
class Period {
  final int index; // 第几节，从 1 开始
  String start; // "HH:mm"
  String end; // "HH:mm"
  String name; // 自定义名称，空 = 默认
  int breakAfterMinutes; // 课后课间时长：本节结束到下一节开始的分钟数；当日最后一节恒为 0

  Period({
    required this.index,
    required this.start,
    required this.end,
    this.name = '',
    this.breakAfterMinutes = 0,
  });

  factory Period.fromJson(Map<String, dynamic> json) => Period(
        index: json['index'] as int,
        start: json['start'] as String,
        end: json['end'] as String,
        name: (json['name'] as String?) ?? '',
        breakAfterMinutes: (json['breakAfterMinutes'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'index': index,
        'start': start,
        'end': end,
        'name': name,
        'breakAfterMinutes': breakAfterMinutes,
      };

  Period copy() => Period(
      index: index,
      start: start,
      end: end,
      name: name,
      breakAfterMinutes: breakAfterMinutes);

  /// 按上课时间顺序重算每节的 [breakAfterMinutes]：
  /// 本节结束到下一节开始之间的分钟数（负值按 0 计，即允许重叠时取 0）；
  /// 当日最后一节恒为 0。任何增/删/改节次或休息时间的操作后都必须调用。
  static void recomputeBreakGaps(List<Period> periods) {
    if (periods.length < 2) {
      for (final p in periods) {
        p.breakAfterMinutes = 0;
      }
      return;
    }
    final sorted = [...periods]..sort((a, b) {
        final byStart = hmToMinutes(a.start).compareTo(hmToMinutes(b.start));
        if (byStart != 0) return byStart;
        final byEnd = hmToMinutes(a.end).compareTo(hmToMinutes(b.end));
        if (byEnd != 0) return byEnd;
        return a.index.compareTo(b.index);
      });
    for (var i = 0; i < sorted.length - 1; i++) {
      final gap = hmToMinutes(sorted[i + 1].start) - hmToMinutes(sorted[i].end);
      sorted[i].breakAfterMinutes = gap < 0 ? 0 : gap;
    }
    sorted.last.breakAfterMinutes = 0;
  }

  /// 自动生成连续节次：首节从 [startMinutes]（00:00 起）开始，
  /// 每节 [durationMinutes] 分钟，课间 [breakMinutes] 分钟，共 [count] 节。
  /// 下一节起点若落在某个 [breaks]（休息时间）内，则顺延到该休息结束。
  static List<Period> generate({
    required int startMinutes,
    required int durationMinutes,
    required int breakMinutes,
    required int count,
    List<PeriodBreak> breaks = const [],
  }) {
    final list = <Period>[];
    var t = startMinutes;
    for (var i = 1; i <= count; i++) {
      list.add(Period(index: i, start: hm(t), end: hm(t + durationMinutes)));
      t += durationMinutes + breakMinutes;
      for (final b in breaks) {
        if (b.containsMinute(t)) t = b.endMinutes;
      }
    }
    recomputeBreakGaps(list); // 每节课后课间时长按真实间隔填充（含休息时间）
    return list;
  }
}
