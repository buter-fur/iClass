import '../utils/date_utils.dart';

/// 休息时间（如午休/晚休）：两节课之间的一段空闲时间，起止用 "HH:mm" 保存。
/// 生成节次表时自动跳过休息；在主界面添加休息会把后面的节次整体顺延。
class PeriodBreak {
  String start; // "HH:mm"
  String end; // "HH:mm"

  /// 是否用户手动添加（自定义）：手动添加的休息不受"自动识别阈值"约束，
  /// 任意大于 0 分钟的时长都忠实显示；false = Excel 导入自动识别或默认生成。
  bool isCustom;

  PeriodBreak({required this.start, required this.end, this.isCustom = false});

  int get startMinutes => hmToMinutes(start);
  int get endMinutes => hmToMinutes(end);

  /// 休息时长（分钟）＝ 结束 − 开始。
  int get durationMinutes => endMinutes - startMinutes;

  factory PeriodBreak.fromJson(Map<String, dynamic> json) => PeriodBreak(
        start: json['start'] as String,
        end: json['end'] as String,
        isCustom: (json['isCustom'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {'start': start, 'end': end, 'isCustom': isCustom};

  PeriodBreak copy() => PeriodBreak(start: start, end: end, isCustom: isCustom);

  /// 分钟数 [m] 是否落在本休息内（左闭右开：m == end 不算）。
  bool containsMinute(int m) => m >= startMinutes && m < endMinutes;
}
