import 'period.dart';
import 'period_break.dart';

/// 应用全部设置（保存在 settings.json）。
class AppSettings {
  // ---- 学年日历（春秋学期 + 寒暑假无限循环）----
  // 开学日期只取月/日（年份固定 2020 无意义，JSON 里存 "MM-dd"）
  DateTime springStart; // 春季学期开学月日，默认 3 月 1 日
  int springWeeks; // 春季学期周数，默认 20（之后是暑假）
  DateTime fallStart; // 秋季学期开学月日，默认 9 月 1 日
  int fallWeeks; // 秋季学期周数，默认 20（之后是寒假）

  int earlyMinutes; // 提前到达分钟，默认 2
  int fallbackAdvanceMinutes; // 无位置/无节点时的固定提前分钟，默认 15
  String? currentLocationNodeId; // 当前所在拓扑节点（Windows 版手动选择）
  List<int> shownWeekdays; // 课表显示的星期，1=周一 … 7=周日
  bool notificationEnabled; // Windows 系统通知
  bool soundEnabled; // 提示音
  bool autoStart; // 开机自启动（默认开启：首次启动时自动写入注册表）
  List<Period> periods; // 全局一份节次表（所有星期共用）
  List<PeriodBreak> breaks; // 休息时间（午休/晚休等），生成节次时自动跳过
  int autoBreakMinutes; // Excel 导入节次时间表时，相邻节次间隔 ≥ 此分钟数即自动识别为休息时间，默认 30
  int weekOffset; // 周次显示偏移：显示周次 = 计算的周次 + 偏移（显示、单双周、课程过滤同步生效）
  String themeMode; // 外观："light"（浅色）| "dark"（深色）| "system"（跟随系统，默认）
  Set<String> firedReminderKeys; // 已提醒的课，键格式 "日期|课程id|开始节次"
  DateTime? simulatedNow; // 调试用：模拟当前时间，null = 用真实时间
  bool devOptionsUnlocked; // 开发者选项是否解锁（设置 → 关于 里连点版本号 10 次）

  AppSettings({
    DateTime? springStart,
    this.springWeeks = 20,
    DateTime? fallStart,
    this.fallWeeks = 20,
    this.earlyMinutes = 2,
    this.fallbackAdvanceMinutes = 15,
    this.currentLocationNodeId,
    List<int>? shownWeekdays,
    this.notificationEnabled = true,
    this.soundEnabled = true,
    this.autoStart = true,
    List<Period>? periods,
    List<PeriodBreak>? breaks,
    this.autoBreakMinutes = 30,
    this.weekOffset = 0,
    this.themeMode = 'system',
    Set<String>? firedReminderKeys,
    this.simulatedNow,
    this.devOptionsUnlocked = false,
  })  : springStart = springStart ?? DateTime(2020, 3, 1),
        fallStart = fallStart ?? DateTime(2020, 9, 1),
        shownWeekdays = shownWeekdays ?? [1, 2, 3, 4, 5, 6, 7],
        periods = periods ?? defaultPeriods(),
        breaks = breaks ?? defaultBreaks(),
        firedReminderKeys = firedReminderKeys ?? {};

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    // 新格式直接读 periods；旧格式只有 periodConfigs 时取第一份非空配置（=周一）作全局表。
    // 旧数据没有 breakAfterMinutes 字段（全 0），必须按真实时间重算，
    // 否则课间时长编辑时的"变化量"计算会错。
    final periods = _periodsFromJson(json['periods']) ??
        _periodsFromOldConfigs(json['periodConfigs']);
    if (periods != null) Period.recomputeBreakGaps(periods);
    return AppSettings(
      springStart: _parseMonthDay(json['springStart'] as String?) ?? DateTime(2020, 3, 1),
      springWeeks: _clampWeeks((json['springWeeks'] as int?) ?? 20),
      fallStart: _parseMonthDay(json['fallStart'] as String?) ?? DateTime(2020, 9, 1),
      fallWeeks: _clampWeeks((json['fallWeeks'] as int?) ?? 20),
      earlyMinutes: (json['earlyMinutes'] as int?) ?? 2,
      fallbackAdvanceMinutes: (json['fallbackAdvanceMinutes'] as int?) ?? 15,
      currentLocationNodeId: json['currentLocationNodeId'] as String?,
      shownWeekdays:
          (json['shownWeekdays'] as List<dynamic>?)?.map((e) => e as int).toList(),
      notificationEnabled: (json['notificationEnabled'] as bool?) ?? true,
      soundEnabled: (json['soundEnabled'] as bool?) ?? true,
      autoStart: (json['autoStart'] as bool?) ?? true,
      periods: periods,
      weekOffset: (json['weekOffset'] as int?) ?? 0,
      themeMode: _parseThemeMode(json['themeMode']),
      firedReminderKeys: ((json['firedReminderKeys'] as List<dynamic>?) ?? [])
          .map((e) => e as String)
          .toSet(),
      simulatedNow:
          json['simulatedNow'] == null ? null : DateTime.tryParse(json['simulatedNow'] as String),
      devOptionsUnlocked: (json['devOptionsUnlocked'] as bool?) ?? false,
      breaks: _breaksFromJson(json['breaks']) ?? defaultBreaks(),
      autoBreakMinutes: (json['autoBreakMinutes'] as int?) ?? 30,
    );
  }

  Map<String, dynamic> toJson() => {
        'springStart': _formatMonthDay(springStart),
        'springWeeks': springWeeks,
        'fallStart': _formatMonthDay(fallStart),
        'fallWeeks': fallWeeks,
        'earlyMinutes': earlyMinutes,
        'fallbackAdvanceMinutes': fallbackAdvanceMinutes,
        'currentLocationNodeId': currentLocationNodeId,
        'shownWeekdays': shownWeekdays,
        'notificationEnabled': notificationEnabled,
        'soundEnabled': soundEnabled,
        'autoStart': autoStart,
        'periods': periods.map((p) => p.toJson()).toList(),
        'weekOffset': weekOffset,
        'themeMode': themeMode,
        'firedReminderKeys': firedReminderKeys.toList(),
        'simulatedNow': simulatedNow?.toIso8601String(),
        'devOptionsUnlocked': devOptionsUnlocked,
        'breaks': breaks.map((b) => b.toJson()).toList(),
        'autoBreakMinutes': autoBreakMinutes,
      };

  static List<Period>? _periodsFromJson(dynamic json) {
    if (json is! List<dynamic>) return null;
    return json.map((e) => Period.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 旧版本 settings.json 的 periodConfigs（每天一份）→ 全局节次表：取第一份非空配置。
  static List<Period>? _periodsFromOldConfigs(dynamic json) {
    if (json is! Map<String, dynamic>) return null;
    for (final value in json.values) {
      if (value is List<dynamic> && value.isNotEmpty) {
        return value.map((e) => Period.fromJson(e as Map<String, dynamic>)).toList();
      }
    }
    return null;
  }

  /// "MM-dd" ↔ DateTime(2020, m, d)（年份固定，仅作月日载体）。
  static DateTime? _parseMonthDay(String? s) {
    if (s == null) return null;
    final parts = s.split('-');
    if (parts.length != 2) return null;
    final m = int.tryParse(parts[0]);
    final d = int.tryParse(parts[1]);
    if (m == null || d == null || m < 1 || m > 12 || d < 1 || d > 31) return null;
    return DateTime(2020, m, d);
  }

  static String _formatMonthDay(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static int _clampWeeks(int n) => n < 1 ? 1 : (n > 40 ? 40 : n);

  /// 外观取值白名单：非法值一律回退跟随系统（默认）。
  static String _parseThemeMode(dynamic v) =>
      (v is String && const ['light', 'dark', 'system'].contains(v)) ? v : 'system';

  /// 休息时间列表解析：格式不对的行跳过。
  static List<PeriodBreak>? _breaksFromJson(dynamic json) {
    if (json is! List<dynamic>) return null;
    final list = <PeriodBreak>[];
    for (final e in json) {
      try {
        final b = PeriodBreak.fromJson(e as Map<String, dynamic>);
        if (b.durationMinutes > 0) list.add(b);
      } catch (_) {} // 坏行跳过
    }
    return list;
  }

  /// 默认休息时间：第 4 节后午休（11:50-13:30）、第 8 节后晚休（17:20-19:00）。
  static List<PeriodBreak> defaultBreaks() => [
        PeriodBreak(start: '11:50', end: '13:30'),
        PeriodBreak(start: '17:20', end: '19:00'),
      ];

  /// 默认节次表：12 节，08:00 开始，每节 50 分钟，课间 10 分钟；
  /// 第 5 节 13:30 上课（午休后），第 9 节 19:00 上课（晚休后）。
  static List<Period> defaultPeriods() => Period.generate(
        startMinutes: 8 * 60,
        durationMinutes: 50,
        breakMinutes: 10,
        count: 12,
        breaks: defaultBreaks(),
      );
}
