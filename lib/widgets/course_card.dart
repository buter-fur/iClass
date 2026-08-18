import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/day_periods.dart';
import '../services/data_store.dart';

/// 课程卡片（显示在课表网格中）：课程名 / 教室 / 教师 / 节次与时间。
/// 左键点击编辑；右键弹出菜单（编辑 / 删除）。
class CourseCard extends StatelessWidget {
  final Course course;
  final DateTime occurrenceDate; // 这张卡片所在的课次日期（删除本节用）
  final VoidCallback onTap; // 左键点击（现在弹课程详情小窗）
  final void Function(DateTime date)? onEdit; // 右键菜单"编辑课程"（直接进编辑页）
  final void Function(DateTime date)? onDelete; // 右键菜单"删除课程"
  final double scale; // 窗口自适应缩放比例（1.0 = 默认窗口尺寸）
  final bool? compact; // 为 null 时按节数自动判断；小卡片用紧凑布局避免溢出

  const CourseCard({
    super.key,
    required this.course,
    required this.occurrenceDate,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.scale = 1.0,
    this.compact,
  });

  /// 柔和的卡片配色（名字见 [paletteNames]，编辑页选色时提示）。
  static const List<Color> palette = [
    Color(0xFFBFD9F5),
    Color(0xFFCFE7D2),
    Color(0xFFF7E5C2),
    Color(0xFFF4D2D2),
    Color(0xFFE2D7F2),
    Color(0xFFD3EAE3),
    Color(0xFFF5E9CE),
    Color(0xFFD5E3F1),
    Color(0xFFEAD9EA),
  ];

  /// 预设配色名字，与 [palette] 一一对应。
  static const List<String> paletteNames = [
    '淡蓝', '浅草绿', '杏黄', '樱花粉', '淡紫', '青瓷绿', '奶油黄', '雾蓝', '藕荷紫',
  ];

  /// 课程卡片颜色：用户自定义的颜色优先；否则同课程名 + 同教师 → 同色（改其他字段不变色）。
  /// 详情小窗也用同一套颜色，保证课表卡片与弹窗对得上。
  static Color colorFor(Course course) {
    return course.colorValue != null
        ? Color(course.colorValue!)
        : palette[('${course.name}|${course.teacher}').hashCode.abs() % palette.length];
  }

  /// 时间行文本：自定义时间显示 "08:35-10:05"；否则"第3-4节 08:50-10:25"；
  /// 没有节次配置或节次不匹配时返回 null。
  static String? timeText(Course course) {
    if (course.customStart != null && course.customEnd != null) {
      return '${course.customStart}-${course.customEnd}';
    }
    final raw = DataStore.instance.settings.periods;
    if (raw.isEmpty) return null;
    final dayPeriods = DayPeriods(raw);
    final first = dayPeriods.periodAt(course.startPeriod);
    final last = dayPeriods.periodAt(course.startPeriod + course.periodCount - 1);
    if (first == null || last == null) return null;
    final endIndex = course.startPeriod + course.periodCount - 1;
    // 只持续一节时显示"第3节"而不是"第3-3节"
    final periodLabel = course.periodCount == 1
        ? '第${course.startPeriod}节'
        : '第${course.startPeriod}-$endIndex节';
    return '$periodLabel ${first.start}-${last.end}';
  }

  /// 地点文本：地图节点名 + 教室（如"教学楼 101"）；两者都没有时返回 null。
  /// 导入时暂存的地点名称（地图里还没有对应节点）也在此显示（如"教学楼 101"），
  /// 等之后导入地图节点数据自动匹配上后恢复为节点名。
  /// 课程详情小窗与迟到提醒共用，保证显示一致。
  static String? placeText(Course course) {
    final nodeName = course.locationNodeId == null
        ? null
        : DataStore.instance.topology.nodeById(course.locationNodeId!)?.name;
    final parts = [
      ?nodeName,
      if (course.locationName != null && course.locationName!.isNotEmpty) course.locationName!,
      if (course.room.isNotEmpty) course.room,
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final color = CourseCard.colorFor(course);
    // 小卡片（单节次或高度不足）用紧凑模式只显示两行，避免溢出
    final isCompact = compact ?? (course.periodCount <= 1 && course.customStart == null);
    final timeText = CourseCard.timeText(course);
    return GestureDetector(
      onSecondaryTapUp: (details) => _showMenu(context, details.globalPosition),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: isCompact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        course.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // 卡片恒为浅色底：文字固定深色，深色模式下也清晰
                        style: TextStyle(
                            fontSize: 12.5 * scale,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                      ),
                      Text(
                        [
                          if (course.room.isNotEmpty) course.room,
                          ?timeText,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5 * scale, color: Colors.black54),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        course.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        // 卡片恒为浅色底：文字固定深色，深色模式下也清晰
                        style: TextStyle(
                            fontSize: 12.5 * scale,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87),
                      ),
                      if (course.room.isNotEmpty)
                        Text(course.room,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11 * scale, color: Colors.black87)),
                      if (course.teacher.isNotEmpty)
                        Text(course.teacher,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11 * scale, color: Colors.black87)),
                      if (timeText != null)
                        Text(timeText,
                            style: TextStyle(fontSize: 10 * scale, color: Colors.black54)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// 右键菜单：编辑 / 删除。
  void _showMenu(BuildContext context, Offset globalPos) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPos, globalPos),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('编辑课程')),
        PopupMenuItem(value: 'delete', child: Text('删除课程')),
      ],
    ).then((value) {
      if (value == 'edit') onEdit?.call(occurrenceDate);
      if (value == 'delete') onDelete?.call(occurrenceDate);
    });
  }
}
