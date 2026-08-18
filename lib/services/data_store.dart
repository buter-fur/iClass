import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/course.dart';
import '../models/topology.dart';
import '../utils/date_utils.dart';
import 'storage_service.dart';
import 'time_service.dart';
import 'week_service.dart';

/// 数据唯一事实来源：课程、拓扑、设置三份数据，改动即自动保存并通知界面刷新。
class DataStore extends ChangeNotifier {
  DataStore._();
  static final DataStore instance = DataStore._();

  List<Course> courses = [];
  Topology topology = Topology();
  AppSettings settings = AppSettings();

  /// 外部入口（托盘「选择当前位置」）请求打开主界面「我在哪」下拉菜单：
  /// 自增计数触发监听。用独立的 ValueNotifier，不触发全局 notifyListeners 重建。
  final ValueNotifier<int> locationMenuRequest = ValueNotifier(0);

  void requestLocationMenu() => locationMenuRequest.value++;

  /// 启动时加载三份数据；文件缺失或损坏时用默认值。
  Future<void> loadAll() async {
    final s = StorageService.instance;

    // 先读设置：旧版课程（周次）换算成日期需要学年日历配置
    final settingsJson = await s.load('settings.json');
    if (settingsJson != null) {
      settings = AppSettings.fromJson(settingsJson);
    }

    final coursesJson = await s.load('courses.json');
    if (coursesJson != null) {
      final now = TimeService.instance.now();
      courses = ((coursesJson['courses'] as List<dynamic>?) ?? [])
          .map((e) {
            final map = e as Map<String, dynamic>;
            _migrateCourseDates(map, now);
            return Course.fromJson(map);
          })
          .toList();
    }

    final topologyJson = await s.load('topology.json');
    if (topologyJson != null) {
      topology = Topology.fromJson(topologyJson);
    }

    // 首次运行（或文件被删）：立即把默认值落盘，方便用户直接查看/修改 JSON
    if (coursesJson == null || topologyJson == null || settingsJson == null) {
      await saveAll();
    }
    notifyListeners();
  }

  /// 旧版课程只有「开始周/结束周」：按当前学年日历换算成具体日期。
  /// 只改内存里的 JSON（下次保存课程时自动落盘成新格式），不改原文件。
  void _migrateCourseDates(Map<String, dynamic> json, DateTime now) {
    if (json['startDate'] != null) return;
    final startWeek = (json['startWeek'] as num?)?.toInt();
    final endWeek = (json['endWeek'] as num?)?.toInt();
    if (startWeek == null || endWeek == null) return;
    final (s, e) = WeekService.migrateWeeksToDates(
      startWeek: startWeek,
      endWeek: endWeek,
      now: now,
      settings: settings,
    );
    json['startDate'] = formatDate(s);
    json['endDate'] = formatDate(e);
  }

  Future<void> saveAll() async {
    await _saveCourses();
    await _saveTopology();
    await _saveSettings();
  }

  Future<void> _saveCourses() => StorageService.instance
      .save('courses.json', {'version': 1, 'courses': courses.map((c) => c.toJson()).toList()});

  Future<void> _saveTopology() => StorageService.instance
      .save('topology.json', {'version': 1, ...topology.toJson()});

  Future<void> _saveSettings() =>
      StorageService.instance.save('settings.json', settings.toJson());

  // ---------------- 课程 CRUD ----------------

  String newCourseId() {
    var n = courses.length + 1;
    while (courses.any((c) => c.id == 'c_$n')) {
      n++;
    }
    return 'c_$n';
  }

  Future<void> addCourse(Course course) async {
    courses.add(course);
    await _saveCourses();
    notifyListeners();
  }

  Future<void> updateCourse(Course course) async {
    final i = courses.indexWhere((c) => c.id == course.id);
    if (i >= 0) courses[i] = course;
    await _saveCourses();
    notifyListeners();
  }

  Future<void> deleteCourse(String id) async {
    courses.removeWhere((c) => c.id == id);
    await _saveCourses();
    notifyListeners();
  }

  /// 「删除本节」：只删除课程在 [date] 这一天的课次，其余课次不变。
  /// 做法是把这一天加入 excludedDates；不重复课只有这一次，直接整条删除。
  Future<void> deleteCourseOccurrence(Course course, DateTime date) async {
    if (course.parity == 'once') {
      await deleteCourse(course.id);
      return;
    }
    final d = formatDate(date);
    if (course.excludedDates.contains(d)) return;
    course.excludedDates.add(d);
    await _saveCourses();
    notifyListeners();
  }

  /// 恢复被「删除本节」排除的某一天（编辑页点停课标签 ✕，立即生效）。
  Future<void> restoreCourseDate(Course course, String date) async {
    if (!course.excludedDates.remove(date)) return;
    await _saveCourses();
    notifyListeners();
  }

  /// 批量导入课程（Excel 导入用）。
  Future<void> addCourses(List<Course> newCourses) async {
    courses.addAll(newCourses);
    await _saveCourses();
    notifyListeners();
  }

  /// 拓扑数据导入/修改后调用：课程里暂存的地点名称（导入课表时地图里还没有
  /// 对应节点）按名称重新匹配到节点——匹配到的课程自动关联节点并清空暂存名称，
  /// 显示恢复为节点名。返回本次匹配到的课程名列表（为空表示没有匹配，不写盘）。
  Future<List<String>> relinkCourseLocations() async {
    final matchedNames = <String>[];
    for (final c in courses) {
      final name = c.locationName;
      if (name == null || name.isEmpty) continue;
      TopologyNode? node;
      for (final n in topology.nodes) {
        if (n.name == name) {
          node = n;
          break;
        }
      }
      if (node == null) continue;
      c.locationNodeId = node.id;
      c.locationName = null;
      matchedNames.add(c.name);
    }
    if (matchedNames.isNotEmpty) {
      await _saveCourses();
      notifyListeners();
    }
    return matchedNames;
  }

  // ---------------- 拓扑 ----------------

  Future<void> saveTopology(Topology t) async {
    topology = t;
    await _saveTopology();
    notifyListeners();
  }

  Future<void> addNode(TopologyNode node) async {
    topology.nodes.add(node);
    await _saveTopology();
    notifyListeners();
  }

  Future<void> updateNode(TopologyNode node) async {
    final i = topology.nodes.indexWhere((n) => n.id == node.id);
    if (i >= 0) topology.nodes[i] = node;
    await _saveTopology();
    notifyListeners();
  }

  Future<void> deleteNode(String id) async {
    topology.nodes.removeWhere((n) => n.id == id);
    topology.edges.removeWhere((e) => e.from == id || e.to == id);
    if (settings.currentLocationNodeId == id) {
      settings.currentLocationNodeId = null;
    }
    await _saveTopology();
    await _saveSettings();
    notifyListeners();
  }

  Future<void> addEdge(TopologyEdge edge) async {
    topology.edges.add(edge);
    await _saveTopology();
    notifyListeners();
  }

  Future<void> deleteEdge(int index) async {
    if (index >= 0 && index < topology.edges.length) {
      topology.edges.removeAt(index);
      await _saveTopology();
      notifyListeners();
    }
  }

  // ---------------- 一键清除 ----------------

  /// 清除所有数据：课程、拓扑、设置全部恢复默认（数据文件立即重写）。
  /// 数据文件夹位置（自定义路径）不受影响。
  Future<void> resetAll() async {
    courses = [];
    topology = Topology();
    settings = AppSettings();
    await saveAll();
    notifyListeners();
  }

  /// 按勾选恢复初始状态：清空课程 / 节次表与休息时间恢复默认 / 清空地图。
  /// 只重置所选内容，其余数据（设置偏好、提醒记录等）保留。
  Future<void> resetSelected({
    bool clearCourses = false,
    bool clearPeriods = false,
    bool clearTopology = false,
  }) async {
    if (clearCourses) courses = [];
    if (clearPeriods) {
      settings.periods = AppSettings.defaultPeriods();
      settings.breaks = AppSettings.defaultBreaks();
    }
    if (clearTopology) {
      topology = Topology();
      settings.currentLocationNodeId = null; // 地图清空后原位置节点已不存在
    }
    await saveAll();
    notifyListeners();
  }

  // ---------------- 设置 ----------------

  Future<void> saveSettings() async {
    await _saveSettings();
    notifyListeners();
  }

  Future<void> setCurrentLocation(String? nodeId) async {
    settings.currentLocationNodeId = nodeId;
    await saveSettings();
  }

  /// 记录一次已提醒的课（去重），并清理 21 天前的旧记录。
  Future<void> markFired(String key) async {
    settings.firedReminderKeys.add(key);
    _pruneFiredKeys();
    await saveSettings();
  }

  void _pruneFiredKeys() {
    final cutoff = DateTime.now().subtract(const Duration(days: 21));
    settings.firedReminderKeys.removeWhere((k) {
      final d = parseDate(k.split('|').first);
      return d != null && d.isBefore(cutoff);
    });
  }
}
