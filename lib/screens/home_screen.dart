import 'package:flutter/material.dart';

import '../models/course.dart';
import '../services/data_store.dart';
import '../services/reminder_engine.dart';
import '../theme.dart';
import '../widgets/course_detail_dialog.dart';
import '../widgets/next_class_card.dart';
import '../widgets/timetable_grid.dart';
import 'course_edit_screen.dart';
import 'import_screen.dart';
import 'period_settings_screen.dart';
import 'settings_screen.dart';
import 'topology_screen.dart';

/// 主界面：下一节课卡片 + 当前位置选择 + 周课表网格。
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DataStore.instance,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('iClass 课表'),
            actions: [
              _locationPill(context),
              IconButton(
                icon: const Icon(Icons.file_upload_outlined),
                tooltip: '导入课表',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ImportScreen()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.schedule_outlined),
                tooltip: '节次设置',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PeriodSettingsScreen()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.map_outlined),
                tooltip: '校园地图',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TopologyScreen()),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: '设置',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: NextClassCard(),
              ),
              const Divider(height: 1),
              Expanded(
                child: TimetableGrid(
                  onCourseTap: (course, date) => _showCourseDetail(context, course, date),
                  onCourseEdit: (course, date) => _openCourse(context, course, date),
                  onEmptyTap: (weekday, period, date) => _openNewCourse(context, weekday, period, date),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () => _openNewCourse(context, null, null, null),
            tooltip: '添加课程',
            child: const Icon(Icons.add),
          ),
        );
      },
    );
  }

  /// 右上角「我在哪」胶囊按钮：大头针图标 + 当前位置名，点击弹出选择菜单。
  /// 托盘菜单「选择当前位置」通过 [DataStore.requestLocationMenu] 直接弹出本菜单。
  /// 注意不能写成 const：否则父级重建时相同 const 实例会被 Flutter 复用、
  /// 不触发本组件的 build，位置切换后胶囊显示不会刷新。
  Widget _locationPill(BuildContext context) => _LocationPill();


  /// 左键点课程卡片：弹课程详情小窗；点小窗里的「编辑课程」再进编辑页。
  Future<void> _showCourseDetail(BuildContext context, Course course, DateTime date) async {
    final action = await showCourseDetailDialog(context, course: course, occurrenceDate: date);
    if (action == 'edit' && context.mounted) {
      _openCourse(context, course, date);
    }
  }

  void _openCourse(BuildContext context, Course course, DateTime date) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CourseEditScreen(course: course, occurrenceDate: date)),
    );
  }

  void _openNewCourse(BuildContext context, int? weekday, int? period, DateTime? date) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CourseEditScreen(
          initialWeekday: weekday,
          initialPeriod: period,
          initialDate: date,
        ),
      ),
    );
  }
}

/// 右上角「我在哪」胶囊按钮：大头针图标 + 当前位置名，点击弹出选择菜单。
/// 托盘菜单「选择当前位置」会请求自动弹出本菜单（不触发全局重建）。
class _LocationPill extends StatefulWidget {
  const _LocationPill();

  @override
  State<_LocationPill> createState() => _LocationPillState();
}

class _LocationPillState extends State<_LocationPill> {
  final _menuKey = GlobalKey<PopupMenuButtonState<String>>();

  @override
  void initState() {
    super.initState();
    DataStore.instance.locationMenuRequest.addListener(_onRequest);
  }

  @override
  void dispose() {
    DataStore.instance.locationMenuRequest.removeListener(_onRequest);
    super.dispose();
  }

  /// 托盘请求弹出：等下一帧（窗口显示、页面转场稳定）再打开菜单，避免时机冲突。
  void _onRequest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _menuKey.currentState?.showButtonMenu();
    });
  }

  @override
  Widget build(BuildContext context) {
    // 内部监听 DataStore：位置在任何页面（设置/托盘）变化后胶囊都立即刷新
    return ListenableBuilder(
      listenable: DataStore.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final store = DataStore.instance;
    final nodes = store.topology.nodes;
    final current = store.settings.currentLocationNodeId;
    final name = nodes.where((n) => n.id == current).map((n) => n.name).firstOrNull;
    final icl = context.iclColors;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: PopupMenuButton<String>(
        key: _menuKey,
        tooltip: '我在哪（选择当前位置）',
        onSelected: (v) async {
          // 注意：菜单项值不能用 null（PopupMenuButton 会把 null 当"取消菜单"处理）
          await store.setCurrentLocation(v.isEmpty ? null : v);
          ReminderEngine.instance.tick(); // 位置变了立即重新计算提醒
        },
        itemBuilder: (context) => [
          const PopupMenuItem<String>(
            value: '',
            child: Text('未选择（按固定提前时间提醒）'),
          ),
          ...nodes.map(
            (n) => PopupMenuItem<String>(value: n.id, child: Text(n.name)),
          ),
        ],
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: icl.pillBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: icl.gridLine),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.place_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  name ?? '未选择位置',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: scheme.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
