import '../models/app_settings.dart';
import '../models/course.dart';
import '../utils/date_utils.dart';

/// 学年日历阶段：春季学期 → 暑假 → 秋季学期 → 寒假 →（次年春季）循环。
enum CalendarPhase { spring, summerVacation, fall, winterVacation }

extension CalendarPhaseLabel on CalendarPhase {
  String get label => switch (this) {
        CalendarPhase.spring => '春季学期',
        CalendarPhase.summerVacation => '暑假',
        CalendarPhase.fall => '秋季学期',
        CalendarPhase.winterVacation => '寒假',
      };
}

/// 某个日历周（周一~周日）的阶段信息。
class WeekContext {
  final CalendarPhase phase;
  final int week; // 学期内 1..N 周；假期为上一学期的 N+1.. 连续编号（已含周次偏移）

  WeekContext({required this.phase, required this.week});
}

/// 学年日历计算：春秋学期 + 寒暑假无限循环，任意日期都能定位到阶段与周次。
///
/// 规则：
/// - 学期第 1 周 = 包含开学日的那一周（周一为一周开始）；
/// - 学期结束后的假期周次连续编号（第 N+1、N+2…周），单双周判断延续；
/// - 周次偏移（设置）直接加在周数上，显示、单双周、课程过滤统一使用；
/// - 课程按日期范围生效（只在这段日期内出现，不会自动复制到其他学期）。
class WeekService {
  /// [date] 所在周的阶段与周次。
  static WeekContext contextOf(DateTime date, AppSettings settings) {
    final info = _phaseOf(date, settings);
    final inSemester = info.idx < info.sem.weeks;
    return WeekContext(
      phase: inSemester ? info.sem.phase : info.sem.vacationPhase,
      week: info.idx + 1 + settings.weekOffset,
    );
  }

  /// 课程在 [date] 这天是否有课（星期 + 日期范围 + 单双周/不重复）。
  /// 提醒引擎、下一节课卡片用。
  static bool courseActiveOn(Course course, DateTime date, AppSettings settings) {
    if (course.dayOfWeek != date.weekday) return false;
    final day = DateTime(date.year, date.month, date.day);
    if (course.excludedDates.contains(formatDate(day))) return false; // 删除本节停课的日子
    if (course.parity == 'once') return day == course.startDate;
    if (day.isBefore(course.startDate) || day.isAfter(course.endDate)) return false;
    return _parityMatches(course.parity, contextOf(day, settings).week);
  }

  /// 课程在 [date] 所在的那一周是否有课（只看日期范围 + 单双周，不比较星期几）。
  /// 课表网格用：整周的课都要显示，包括已经过去的课。
  static bool courseActiveInWeek(Course course, DateTime date, AppSettings settings) {
    final monday = _mondayOf(date);
    final sunday = monday.add(const Duration(days: 6));
    if (course.parity == 'once') {
      if (course.startDate.isBefore(monday) || course.startDate.isAfter(sunday)) {
        return false;
      }
      return !course.excludedDates.contains(formatDate(course.startDate));
    }
    if (course.endDate.isBefore(monday) || course.startDate.isAfter(sunday)) return false;
    if (!_parityMatches(course.parity, contextOf(monday, settings).week)) return false;
    // 这一周里课程出现的那一天：不在日期范围内或被「删除本节」排除 → 整周不显示
    final occDate = monday.add(Duration(days: course.dayOfWeek - 1));
    if (occDate.isBefore(course.startDate) || occDate.isAfter(course.endDate)) return false;
    return !course.excludedDates.contains(formatDate(occDate));
  }

  static bool _parityMatches(String parity, int week) {
    switch (parity) {
      case 'odd':
        return week.isOdd;
      case 'even':
        return week.isEven;
      default:
        return true; // all
    }
  }

  /// [date] 所在阶段（学期或假期）的最后一天。新建课程的默认结束日期用它：
  /// 在学期里 = 学期最后一周的周日；在假期里 = 下一个学期第 1 周周一的前一天。
  static DateTime phaseEndDate(DateTime date, AppSettings settings) {
    final info = _phaseOf(date, settings);
    final monday = _mondayOf(info.sem.start);
    if (info.idx < info.sem.weeks) {
      return monday.add(Duration(days: info.sem.weeks * 7 - 1));
    }
    return info.nextMonday.subtract(const Duration(days: 1));
  }

  /// 旧数据迁移：把「开始周/结束周」换算成具体日期。
  /// 锚点学期 = 当前所在学期；若现在在假期里：周次超出上一学期周数（假期延续周）
  /// 就锚定上一学期（课程本来就在这个假期里），否则锚定下一学期（假期里录的
  /// 通常是从第 1 周开始的下学期课程）。结束日期取该周周日，保证整周都覆盖。
  static (DateTime, DateTime) migrateWeeksToDates({
    required int startWeek,
    required int endWeek,
    required DateTime now,
    required AppSettings settings,
  }) {
    final info = _phaseOf(now, settings);
    final DateTime anchor;
    if (info.idx < info.sem.weeks) {
      anchor = _mondayOf(info.sem.start); // 现在在学期内 → 锚定本学期
    } else if (startWeek > info.sem.weeks) {
      anchor = _mondayOf(info.sem.start); // 假期延续周 → 锚定上一学期
    } else {
      anchor = info.nextMonday; // 假期里录下学期的课 → 锚定下一学期
    }
    return (
      anchor.add(Duration(days: 7 * (startWeek - 1))),
      anchor.add(Duration(days: 7 * endWeek - 1)),
    );
  }

  /// 定位 [date] 所属的学期窗口（假期归属其上一学期），并附带下一学期的起始信息。
  static _PhaseInfo _phaseOf(DateTime date, AppSettings settings) {
    final d = DateTime(date.year, date.month, date.day);
    // 前后各一年的学期起点按时间排序，保证任意日期都能被覆盖
    final sems = <_SemesterStart>[
      for (var y = d.year - 1; y <= d.year + 1; y++) ...[
        _SemesterStart(
          DateTime(y, settings.springStart.month, settings.springStart.day),
          settings.springWeeks,
          CalendarPhase.spring,
          CalendarPhase.summerVacation,
        ),
        _SemesterStart(
          DateTime(y, settings.fallStart.month, settings.fallStart.day),
          settings.fallWeeks,
          CalendarPhase.fall,
          CalendarPhase.winterVacation,
        ),
      ],
    ]..sort((a, b) => a.start.compareTo(b.start));

    for (var i = 0; i < sems.length; i++) {
      final sem = sems[i];
      final startMonday = _mondayOf(sem.start);
      final idx = d.difference(startMonday).inDays ~/ 7; // 相对第 1 周的周序号
      if (idx < 0) continue;
      final nextMonday = i + 1 < sems.length
          ? _mondayOf(sems[i + 1].start)
          : startMonday.add(Duration(days: sem.weeks * 7));
      if (idx < sem.weeks) return _PhaseInfo(sem, idx, nextMonday);
      // 学期之后 = 假期：直到下一个学期第 1 周周一之前
      if (!d.isBefore(nextMonday)) continue;
      return _PhaseInfo(sem, idx, nextMonday);
    }
    // 理论不可达（覆盖前后各一年）；兜底按最后一个学期
    final last = sems.last;
    return _PhaseInfo(last, 0, _mondayOf(last.start));
  }

  /// 所在周的周一（当天 0 点）。
  static DateTime _mondayOf(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }
}

/// 一个学期的起始信息（开学日期 + 周数 + 学期/假期阶段）。
class _SemesterStart {
  final DateTime start;
  final int weeks;
  final CalendarPhase phase;
  final CalendarPhase vacationPhase;

  _SemesterStart(this.start, this.weeks, this.phase, this.vacationPhase);
}

/// 日期定位结果：所属学期窗口 + 周序号（0 起）+ 下一学期第 1 周周一。
class _PhaseInfo {
  final _SemesterStart sem;
  final int idx;
  final DateTime nextMonday;

  _PhaseInfo(this.sem, this.idx, this.nextMonday);
}
