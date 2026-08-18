import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/day_periods.dart';
import '../models/period.dart';
import '../services/data_store.dart';
import '../services/time_service.dart';
import '../services/week_service.dart';
import '../theme.dart';
import '../utils/date_utils.dart';
import 'course_card.dart';
import 'delete_course_dialog.dart';

/// 周课表网格：横轴星期（可在设置里配置显示哪些天）、纵轴按时间比例定位。
/// 顶部导航条可无限翻看任意周（学年日历自动区分学期与寒暑假）；课程卡片按实际起止时间定位，
/// 自定义时间的课可以跨越节次分界线；已结束的课减淡显示。
/// 左键点卡片编辑、右键弹菜单，点空格新建课程（自动带上星期、节次和那一天的日期）。
class TimetableGrid extends StatefulWidget {
  final void Function(Course course, DateTime date) onCourseTap; // 左键点卡片（弹详情小窗）
  final void Function(Course course, DateTime date) onCourseEdit; // 右键菜单"编辑课程"（直接进编辑页）
  final void Function(int weekday, int period, DateTime date) onEmptyTap; // date=点击的那一天

  const TimetableGrid({
    super.key,
    required this.onCourseTap,
    required this.onCourseEdit,
    required this.onEmptyTap,
  });

  static const double headerH = 52;
  static const double leftW = 64;
  static const double dayW = 150;
  static const double rowH = 64;

  @override
  State<TimetableGrid> createState() => _TimetableGridState();
}

class _TimetableGridState extends State<TimetableGrid> {
  int _weekOffset = 0; // 0=本周，−1=上一周，+1=下一周

  /// 删除确认对话框：删除全部（整条课程）/ 删除本节（只删 [date] 这一天）。
  Future<void> _confirmDelete(Course course, DateTime date) async {
    await showDeleteCourseDialog(context, course: course, occurrenceDate: date);
  }

  @override
  Widget build(BuildContext context) {
    final store = DataStore.instance;
    final settings = store.settings;
    final now = TimeService.instance.now();
    final dps = DayPeriods(settings.periods);
    final maxPeriods = dps.maxPeriodIndex;
    if (maxPeriods == 0) {
      return const Center(child: Text('还没有配置节次时间\n请点右上角"节次设置"配置'));
    }

    // 显示的星期 = 设置里勾选的天 + 有课但没勾选的天（保证任何一天添加的课程都能看到）
    final weekdays = <int>{
      ...settings.shownWeekdays,
      ...store.courses.map((c) => c.dayOfWeek),
    }.toList()..sort();

    final thisWeekMonday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    // 日历无限翻页：查看周可前后任意移动，周次与学期/假期阶段由学年日历计算
    final viewedMonday = thisWeekMonday.add(Duration(days: 7 * _weekOffset));
    final ctx = WeekService.contextOf(viewedMonday, settings);
    final viewedWeek = ctx.week;
    final isCurrentWeek = viewedMonday == thisWeekMonday;

    // 查看周要上的课（周次范围 + 单双周；已过去的课也显示，由减淡区分）
    final visibleCourses = <Course>[];
    for (final c in store.courses) {
      if (!weekdays.contains(c.dayOfWeek)) continue;
      if (!WeekService.courseActiveInWeek(c, viewedMonday, settings)) {
        continue;
      }
      visibleCourses.add(c);
    }

    // 纵向时间映射：t0=显示范围最早、t1=最晚；自定义课程超出节次表时自动扩展
    final baseTop = hmToMinutes(dps.periods.first.start);
    final baseBottom = hmToMinutes(dps.periods.last.end);
    var t0 = baseTop, t1 = baseBottom;
    for (final c in visibleCourses) {
      final (s, e) = _courseTimeRange(c, dps);
      if (s == null || e == null) continue;
      if (s < t0) t0 = s;
      if (e > t1) t1 = e;
    }

    return Column(
      children: [
        _weekNavBar(viewedWeek, viewedMonday, ctx.phase.label, isCurrentWeek),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 窗口自适应：以默认窗口宽 1280 为基准等比例缩放
              final scale = (constraints.maxWidth / 1280).clamp(0.5, 2.0);
              final headerH = TimetableGrid.headerH * scale;
              final leftW = TimetableGrid.leftW * scale;
              final dayW = TimetableGrid.dayW * scale;
              final rowH = TimetableGrid.rowH * scale;
              final baseSpan = baseBottom - baseTop;
              final pxPerMin = maxPeriods * rowH / baseSpan;
              final bodyH = (t1 - t0) * pxPerMin;
              double timeToY(int min) => headerH + (min - t0) * pxPerMin;
              final totalW = leftW + weekdays.length * dayW;
              final totalH = headerH + bodyH;

              // 横线位置：顶部边界 + 每节开始 + 底部边界（去重排序）
              final rowLines = <double>{headerH, headerH + bodyH};
              for (final p in dps.periods) {
                rowLines.add(timeToY(hmToMinutes(p.start)));
              }
              final sortedLines = rowLines.toList()..sort();

              return SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalW,
                    height: totalH,
                    child: Stack(
                      children: [
                        // 0. 今天所在整列的淡色背景（本周视图），让当天列更醒目
                        if (isCurrentWeek && weekdays.contains(now.weekday))
                          Positioned(
                            left: leftW + weekdays.indexOf(now.weekday) * dayW,
                            top: 0,
                            width: dayW,
                            height: totalH,
                            child: ColoredBox(color: context.iclColors.todayColumnBg),
                          ),
                        // 1. 网格线背景
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _GridPainter(
                              dayCount: weekdays.length,
                              leftW: leftW,
                              dayW: dayW,
                              headerH: headerH,
                              bodyH: bodyH,
                              rowLines: sortedLines,
                              lineColor: context.iclColors.gridLine,
                            ),
                          ),
                        ),
                        // 2. 表头（星期 + 日期）
                        for (var i = 0; i < weekdays.length; i++)
                          Positioned(
                            left: leftW + i * dayW,
                            top: 0,
                            width: dayW,
                            height: headerH,
                            child: _DayHeader(
                              weekday: weekdays[i],
                              date: viewedMonday.add(Duration(days: weekdays[i] - 1)),
                              isToday: isCurrentWeek && weekdays[i] == now.weekday,
                              scale: scale,
                            ),
                          ),
                        // 3. 左侧节次标签
                        for (final p in dps.periods)
                          Positioned(
                            left: 0,
                            top: timeToY(hmToMinutes(p.start)),
                            width: leftW,
                            height: timeToY(hmToMinutes(p.end)) - timeToY(hmToMinutes(p.start)),
                            child: _PeriodLabel(
                              periodIndex: p.index,
                              periodName: p.name,
                              timeText: '${p.start}-${p.end}',
                              scale: scale,
                            ),
                          ),
                        // 4. 空格点击区域（在卡片下层）
                        for (var i = 0; i < weekdays.length; i++)
                          for (final p in dps.periods)
                            if (!_hasCourseAt(visibleCourses, dps, weekdays[i], p.index))
                              Positioned(
                                left: leftW + i * dayW,
                                top: timeToY(hmToMinutes(p.start)),
                                width: dayW,
                                height: _rowHeight(p, dps, baseBottom, timeToY),
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => widget.onEmptyTap(
                                    weekdays[i],
                                    p.index,
                                    viewedMonday.add(Duration(days: weekdays[i] - 1)),
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                        // 5. 当前时间红线（仅本周视图）
                        if (isCurrentWeek)
                          ..._timeIndicator(now, weekdays, leftW, dayW, baseTop, baseBottom, timeToY),
                        // 6. 课程卡片（最上层；普通课先画，自定义课后画在上层）
                        for (final c in visibleCourses.where((c) => c.customStart == null || c.customEnd == null))
                          _courseCard(c, weekdays, dps, now, viewedMonday, leftW, dayW, timeToY, scale),
                        for (final c in visibleCourses.where((c) => c.customStart != null && c.customEnd != null))
                          _courseCard(c, weekdays, dps, now, viewedMonday, leftW, dayW, timeToY, scale),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 课程当天实际的 (开始分钟, 结束分钟)；自定义时间异常或节次不匹配时返回 (null, null)。
  (int?, int?) _courseTimeRange(Course c, DayPeriods dps) {
    final cs = c.customStart, ce = c.customEnd;
    if (cs != null && ce != null) {
      final s = hmToMinutes(cs), e = hmToMinutes(ce);
      return e > s ? (s, e) : (null, null);
    }
    final first = dps.periodAt(c.startPeriod);
    final last = dps.periodAt(c.startPeriod + c.periodCount - 1);
    if (first == null || last == null) return (null, null);
    return (hmToMinutes(first.start), hmToMinutes(last.end));
  }

  /// 第 [period] 节是否被课程占用：按时间区间与节次时段的重叠判断
  /// （自定义时间的课也能挡住它跨过的每一节）。
  bool _hasCourseAt(List<Course> courses, DayPeriods dps, int weekday, int period) {
    final p = dps.periodAt(period);
    if (p == null) return false;
    final ps = hmToMinutes(p.start), pe = hmToMinutes(p.end);
    for (final c in courses) {
      if (c.dayOfWeek != weekday) continue;
      final (s, e) = _courseTimeRange(c, dps);
      if (s == null || e == null) continue;
      if (s < pe && e > ps) return true;
    }
    return false;
  }

  /// 第 [p] 节的可点击行高：从本节开始到下一节开始（最后一节到节次表结束）。
  double _rowHeight(Period p, DayPeriods dps, int baseBottom, double Function(int) timeToY) {
    final next = dps.periodAt(p.index + 1);
    final endMin = next != null ? hmToMinutes(next.start) : baseBottom;
    return timeToY(endMin) - timeToY(hmToMinutes(p.start));
  }

  Widget _courseCard(Course c, List<int> weekdays, DayPeriods dps, DateTime now,
      DateTime viewedMonday, double leftW, double dayW,
      double Function(int) timeToY, double scale) {
    final (s, e) = _courseTimeRange(c, dps);
    final col = weekdays.indexOf(c.dayOfWeek);
    if (s == null || e == null || col < 0) return const SizedBox.shrink();
    // 文本缩放系数（Windows 显示缩放下字体变大，卡片高度要跟着保证放得下内容）
    final tc = MediaQuery.textScalerOf(context).scale(100) / 100;
    var height = timeToY(e) - timeToY(s) - 8;
    // 高度放不下教室/教师分行时用紧凑模式，并保证至少放得下两行（名称 + 教室·时间）
    final compact = height < 12 + 80 * scale * tc;
    final minH = 12 + 36 * scale * tc;
    if (height < minH) height = minH;
    // 已结束的课减淡：以查看周为基准，结束时间早于现在的课变淡
    // （本周 = 之前上完的课；翻到过去周 = 整周减淡；未来周 = 不减淡）
    final courseDate =
        viewedMonday.add(Duration(days: c.dayOfWeek - 1)).add(Duration(minutes: e));
    final dimmed = courseDate.isBefore(now);
    final occurrenceDate = viewedMonday.add(Duration(days: c.dayOfWeek - 1));
    final card = CourseCard(
      course: c,
      occurrenceDate: occurrenceDate,
      onTap: () => widget.onCourseTap(c, occurrenceDate),
      onEdit: (date) => widget.onCourseEdit(c, date),
      onDelete: (date) => _confirmDelete(c, date),
      scale: scale,
      compact: compact,
    );
    return Positioned(
      left: leftW + col * dayW + 4,
      top: timeToY(s) + 4,
      width: dayW - 8,
      height: height,
      child: dimmed ? Opacity(opacity: 0.45, child: card) : card,
    );
  }

  List<Widget> _timeIndicator(DateTime now, List<int> weekdays, double leftW, double dayW,
      int baseTop, int baseBottom, double Function(int) timeToY) {
    final col = weekdays.indexOf(now.weekday);
    if (col < 0) return const [];
    final current = now.difference(DateTime(now.year, now.month, now.day)).inMinutes;
    if (current < baseTop || current > baseBottom) return const [];
    final y = timeToY(current);
    return [
      Positioned(
        left: leftW,
        top: y,
        width: weekdays.length * dayW,
        height: 2,
        child: Container(
          color: Colors.redAccent,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    ];
  }

  /// 顶部周次导航条：◀ 第 N 周 · 阶段 · 日期范围（回到本周在日期右侧）▶。
  /// ▶ 始终固定在最右端；日历可无限翻页，两个箭头始终可用。
  Widget _weekNavBar(int viewedWeek, DateTime viewedMonday, String phaseLabel, bool isCurrentWeek) {
    final weekEnd = viewedMonday.add(const Duration(days: 6));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: '上一周',
            onPressed: () => setState(() => _weekOffset--),
          ),
          Expanded(
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '第 $viewedWeek 周 · $phaseLabel · ${formatDate(viewedMonday)} ~ ${formatDate(weekEnd)}'
                    '${isCurrentWeek ? '（本周）' : ''}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (_weekOffset != 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: TextButton.icon(
                        onPressed: () => setState(() => _weekOffset = 0),
                        icon: const Icon(Icons.today_outlined, size: 16),
                        label: const Text('回到本周'),
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: '下一周',
            onPressed: () => setState(() => _weekOffset++),
          ),
        ],
      ),
    );
  }
}

/// 表头：星期名 + 日期，今天高亮（仅本周视图）。
class _DayHeader extends StatelessWidget {
  final int weekday;
  final DateTime date;
  final bool isToday;
  final double scale;

  const _DayHeader({required this.weekday, required this.date, required this.isToday, required this.scale});

  @override
  Widget build(BuildContext context) {
    final icl = context.iclColors;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: isToday ? icl.headerTodayBg : icl.headerBg,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            weekdayName(weekday),
            style: TextStyle(
              fontSize: 14 * scale,
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              color: isToday ? scheme.primary : scheme.onSurface,
            ),
          ),
          Text(
            '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
            style: TextStyle(fontSize: 10 * scale, color: icl.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// 左侧节次标签：第 N 节（或自定义名称）+ 时间（全局节次表，各列同一份）。
class _PeriodLabel extends StatelessWidget {
  final int periodIndex;
  final String periodName; // 自定义节次名称，空 = 显示"第 N 节"
  final String timeText;
  final double scale;

  const _PeriodLabel({
    required this.periodIndex,
    required this.periodName,
    required this.timeText,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final icl = context.iclColors;
    return Container(
      color: icl.headerBg,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            periodName.isEmpty ? '第$periodIndex节' : periodName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12 * scale, fontWeight: FontWeight.w500),
          ),
          Text(timeText, style: TextStyle(fontSize: 9 * scale, color: icl.textSecondary)),
        ],
      ),
    );
  }
}

/// 网格线：竖线按天、横线按节次边界（按时间映射的位置）。
class _GridPainter extends CustomPainter {
  final int dayCount;
  final double leftW;
  final double dayW;
  final double headerH;
  final double bodyH;
  final List<double> rowLines;
  final Color lineColor;

  _GridPainter({
    required this.dayCount,
    required this.leftW,
    required this.dayW,
    required this.headerH,
    required this.bodyH,
    required this.rowLines,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1;
    for (var i = 0; i <= dayCount; i++) {
      final x = leftW + i * dayW;
      canvas.drawLine(Offset(x, 0), Offset(x, headerH + bodyH), paint);
    }
    for (final y in rowLines) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) {
    if (oldDelegate.dayCount != dayCount ||
        oldDelegate.leftW != leftW ||
        oldDelegate.dayW != dayW ||
        oldDelegate.headerH != headerH ||
        oldDelegate.bodyH != bodyH ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.rowLines.length != rowLines.length) {
      return true;
    }
    for (var i = 0; i < rowLines.length; i++) {
      if (oldDelegate.rowLines[i] != rowLines[i]) return true;
    }
    return false;
  }
}
