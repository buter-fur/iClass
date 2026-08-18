import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/autostart_service.dart';
import '../services/data_store.dart';
import '../services/reminder_engine.dart';
import '../services/storage_service.dart';
import '../theme.dart';
import '../utils/date_utils.dart';
import '../version.dart';
import '../widgets/location_dropdown.dart';

/// 设置页：学期、提前时间、显示星期、提醒方式、自启动、
/// 数据管理（恢复初始状态/数据文件夹）、关于（版本号，连点 10 次解锁开发者选项）。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _dataDir;
  bool? _autoStart;
  int _versionTaps = 0; // 连点版本号计数，到 10 解锁开发者选项

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    _dataDir = await StorageService.instance.dirPath;
    _autoStart = await AutostartService.instance.isEnabled();
    if (mounted) setState(() {});
  }

  /// 连点版本号：10 次切换开发者选项（关→开 / 开→关，两种方向都算一次）。
  void _onVersionTap() {
    final settings = DataStore.instance.settings;
    _versionTaps++;
    if (_versionTaps >= 10) {
      _versionTaps = 0;
      settings.devOptionsUnlocked = !settings.devOptionsUnlocked;
      DataStore.instance.saveSettings();
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(settings.devOptionsUnlocked
              ? '开发者选项已开启（设置页底部）'
              : '开发者选项已关闭'),
        ),
      );
    }
  }

  /// 在资源管理器里打开数据文件夹。
  Future<void> _openDataDir() async {
    await StorageService.instance.openDataDir();
  }

  /// 更改数据文件夹位置 / 恢复默认位置（数据文件会整体搬过去）。
  Future<void> _changeDataDir({required bool reset}) async {
    String? picked;
    if (!reset) {
      picked = await getDirectoryPath(confirmButtonText: '选择数据文件夹');
      if (picked == null) return;
    }
    try {
      final p = await StorageService.instance.changeDataDir(reset ? null : picked);
      if (!mounted) return;
      setState(() => _dataDir = p);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('数据文件夹已改为 $p（数据文件已搬过去）')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设置失败：$e')),
      );
    }
  }

  /// 恢复初始状态：第一步勾选要清空的内容（课表/节次/地图），第二步二次确认后执行。
  Future<void> _resetFlow() async {
    // 默认都不勾选：恢复初始状态前先想清楚要清空哪些内容
    var clearCourses = false;
    var clearPeriods = false;
    var clearTopology = false;
    final picked = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('恢复初始状态'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('勾选要清空的内容（恢复成刚安装时的默认状态）：'),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('课表'),
                subtitle: const Text('清空全部课程'),
                value: clearCourses,
                onChanged: (v) => setState(() => clearCourses = v ?? false),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('节次'),
                subtitle: const Text('节次表与休息时间恢复默认'),
                value: clearPeriods,
                onChanged: (v) => setState(() => clearPeriods = v ?? false),
              ),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('地图'),
                subtitle: const Text('清空校园地图节点与路径'),
                value: clearTopology,
                onChanged: (v) => setState(() => clearTopology = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(
              onPressed: clearCourses || clearPeriods || clearTopology
                  ? () => Navigator.pop(context, true)
                  : null,
              child: const Text('下一步'),
            ),
          ],
        ),
      ),
    );
    if (picked != true || !mounted) return;
    final labels = [
      if (clearCourses) '课表',
      if (clearPeriods) '节次',
      if (clearTopology) '地图',
    ].join('、');
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空所选内容？'),
        content: Text('将清空 $labels 并恢复初始状态。\n\n此操作不可恢复！建议先打开数据文件夹手动备份。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await DataStore.instance.resetSelected(
      clearCourses: clearCourses,
      clearPeriods: clearPeriods,
      clearTopology: clearTopology,
    );
    ReminderEngine.instance.tick();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已清空 $labels，恢复初始状态')),
      );
    }
  }

  /// 选学期开学月日（年份固定 2020，只取月/日）。
  Future<void> _pickSemesterStartDay({required bool spring}) async {
    final settings = DataStore.instance.settings;
    final base = spring ? settings.springStart : settings.fallStart;
    final picked = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2020, 12, 31),
      helpText: '选择${spring ? '春季' : '秋季'}学期开学日期（只取月/日，每年循环）',
    );
    if (picked == null) return;
    final newDate = DateTime(2020, picked.month, picked.day);
    if (spring) {
      settings.springStart = newDate;
    } else {
      settings.fallStart = newDate;
    }
    await DataStore.instance.saveSettings();
    ReminderEngine.instance.tick();
  }

  Future<void> _editNumber({
    required String title,
    required int value,
    required int min,
    required int max,
    required Future<void> Function(int) onSave,
  }) async {
    final controller = TextEditingController(text: '$value');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(hintText: '请输入 $min - $max'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text)),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result < min || result > max) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('请输入 $min - $max 之间的数字')));
      }
      return;
    }
    await onSave(result);
  }

  Future<void> _setSimulatedNow() async {
    final settings = DataStore.instance.settings;
    final base = settings.simulatedNow ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      helpText: '选择模拟日期',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
      helpText: '选择模拟时间',
    );
    if (time == null) return;
    settings.simulatedNow =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    await DataStore.instance.saveSettings();
    ReminderEngine.instance.tick();
  }

  Future<void> _clearSimulatedNow() async {
    DataStore.instance.settings.simulatedNow = null;
    await DataStore.instance.saveSettings();
    ReminderEngine.instance.tick();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DataStore.instance,
      builder: (context, _) {
        final settings = DataStore.instance.settings;
        final sim = settings.simulatedNow;
        return Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              _section('学期设置'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  '学年日历：春季学期 → 暑假 → 秋季学期 → 寒假，每年循环。'
                  '课程按日期范围生效（不会自动复制到其他学期）；日期超出学期范围时，'
                  '假期周次延续编号，单双周判断连续。',
                  style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.local_florist_outlined),
                title: const Text('春季学期开学'),
                subtitle: Text(
                    '${settings.springStart.month}月${settings.springStart.day}日 · 共 ${settings.springWeeks} 周（之后为暑假）'),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _pickSemesterStartDay(spring: true),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_view_week_outlined),
                title: const Text('春季学期周数'),
                subtitle: Text('${settings.springWeeks} 周'),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _editNumber(
                  title: '春季学期周数',
                  value: settings.springWeeks,
                  min: 1,
                  max: 30,
                  onSave: (v) async {
                    settings.springWeeks = v;
                    await DataStore.instance.saveSettings();
                    ReminderEngine.instance.tick();
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.park_outlined),
                title: const Text('秋季学期开学'),
                subtitle: Text(
                    '${settings.fallStart.month}月${settings.fallStart.day}日 · 共 ${settings.fallWeeks} 周（之后为寒假）'),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _pickSemesterStartDay(spring: false),
              ),
              ListTile(
                leading: const Icon(Icons.calendar_view_week_outlined),
                title: const Text('秋季学期周数'),
                subtitle: Text('${settings.fallWeeks} 周'),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _editNumber(
                  title: '秋季学期周数',
                  value: settings.fallWeeks,
                  min: 1,
                  max: 30,
                  onSave: (v) async {
                    settings.fallWeeks = v;
                    await DataStore.instance.saveSettings();
                    ReminderEngine.instance.tick();
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.exposure_outlined),
                title: const Text('周次显示偏移'),
                subtitle: Text(
                    '${settings.weekOffset >= 0 ? '+' : ''}${settings.weekOffset}（显示的第 N 周在此基础上加减，单双周判断同步生效）'),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _editNumber(
                  title: '周次显示偏移',
                  value: settings.weekOffset,
                  min: -10,
                  max: 10,
                  onSave: (v) async {
                    settings.weekOffset = v;
                    await DataStore.instance.saveSettings();
                    ReminderEngine.instance.tick();
                  },
                ),
              ),
              _section('通用'),
              ListTile(
                leading: const Icon(Icons.alarm_add_outlined),
                title: const Text('提前到达时间'),
                subtitle: Text('${settings.earlyMinutes} 分钟（期望在上课前几分钟到教室）'),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _editNumber(
                  title: '提前到达时间（分钟）',
                  value: settings.earlyMinutes,
                  min: 0,
                  max: 30,
                  onSave: (v) async {
                    settings.earlyMinutes = v;
                    await DataStore.instance.saveSettings();
                    ReminderEngine.instance.tick();
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.timer_outlined),
                title: const Text('兜底提前时间'),
                subtitle: Text('${settings.fallbackAdvanceMinutes} 分钟（未选位置/课程无节点时提前多久提醒）'),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _editNumber(
                  title: '兜底提前时间（分钟）',
                  value: settings.fallbackAdvanceMinutes,
                  min: 5,
                  max: 60,
                  onSave: (v) async {
                    settings.fallbackAdvanceMinutes = v;
                    await DataStore.instance.saveSettings();
                    ReminderEngine.instance.tick();
                  },
                ),
              ),
              _section('外观'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<String>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                              value: 'light',
                              label: Text('浅色模式'),
                              icon: Icon(Icons.light_mode_outlined)),
                          ButtonSegment(
                              value: 'dark',
                              label: Text('深色模式'),
                              icon: Icon(Icons.dark_mode_outlined)),
                          ButtonSegment(
                              value: 'system',
                              label: Text('跟随系统'),
                              icon: Icon(Icons.brightness_auto_outlined)),
                        ],
                        selected: {settings.themeMode},
                        onSelectionChanged: (s) async {
                          settings.themeMode = s.first;
                          await DataStore.instance.saveSettings();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              _section('显示星期'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(weekdayName(d)),
                        selected: settings.shownWeekdays.contains(d),
                        onSelected: (on) async {
                          if (on) {
                            settings.shownWeekdays.add(d);
                          } else if (settings.shownWeekdays.length > 1) {
                            settings.shownWeekdays.remove(d);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('至少显示一天')),
                            );
                            return;
                          }
                          await DataStore.instance.saveSettings();
                        },
                      ),
                  ],
                ),
              ),
              _section('当前位置'),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LocationDropdown(),
              ),
              _section('提醒'),
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Windows 系统通知'),
                value: settings.notificationEnabled,
                onChanged: (v) async {
                  settings.notificationEnabled = v;
                  await DataStore.instance.saveSettings();
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.volume_up_outlined),
                title: const Text('提示音'),
                value: settings.soundEnabled,
                onChanged: (v) async {
                  settings.soundEnabled = v;
                  await DataStore.instance.saveSettings();
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.rocket_launch_outlined),
                title: const Text('开机自启动'),
                subtitle: const Text('开机后自动在托盘运行，课表提醒不中断'),
                value: _autoStart ?? false,
                onChanged: (v) async {
                  final messenger = ScaffoldMessenger.of(context);
                  final ok = await AutostartService.instance.setEnabled(v);
                  if (mounted) {
                    setState(() => _autoStart = ok ? v : !v);
                    messenger.showSnackBar(
                      SnackBar(content: Text(ok ? '已${v ? '开启' : '关闭'}开机自启动' : '设置失败，请重试')),
                    );
                  }
                },
              ),
              // 开发者选项默认隐藏：在「关于」里连点版本号 10 次解锁
              if (settings.devOptionsUnlocked) ...[
                _section('开发者'),
                ListTile(
                  leading: const Icon(Icons.notifications_active_outlined),
                  title: const Text('测试提醒'),
                  subtitle: const Text('立即发送一条测试通知和提示音（不写入已提醒记录，不影响正式提醒）'),
                  trailing: TextButton(
                    onPressed: () => ReminderEngine.instance.fireTest(),
                    child: const Text('发送'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('模拟当前时间'),
                  subtitle: Text(sim == null
                      ? '关闭（使用真实时间）'
                      : '开启：${formatDate(sim)} ${formatTime(sim)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(onPressed: _setSimulatedNow, child: const Text('设置')),
                      if (sim != null)
                        TextButton(onPressed: _clearSimulatedNow, child: const Text('清除')),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    '说明：模拟时间用于调试提醒时机（不用真的等到上课前）。'
                    '测试完记得点"清除"恢复真实时间。',
                    style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary),
                  ),
                ),
              ],
              _section('数据管理'),
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined, color: Colors.redAccent),
                title: const Text('恢复初始状态'),
                subtitle: const Text('不可恢复，建议先备份数据文件夹'),
                onTap: _resetFlow,
              ),
              _section('关于'),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('版本'),
                // 开发者选项处于关闭状态时，这里不显示任何与开发者相关的介绍
                subtitle: Text(settings.devOptionsUnlocked ? '开发者选项已开启（连点版本号 10 次可关闭）' : 'iClass 校园课表'),
                trailing: InkWell(
                  onTap: _onVersionTap,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      kAppVersion,
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: const Text('数据文件夹'),
                subtitle: Text(_dataDir ?? '加载中...'),
                trailing: PopupMenuButton<String>(
                  tooltip: '数据文件夹操作',
                  onSelected: (v) => _changeDataDir(reset: v == 'reset'),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'change', child: Text('更改位置')),
                    PopupMenuItem(value: 'reset', child: Text('恢复默认位置')),
                  ],
                ),
                onTap: _openDataDir,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text(
                  '点上方一行可直接打开数据文件夹；点右侧按钮可把数据换到其他位置。',
                  style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Text(
                  '提示：点击窗口关闭按钮只会最小化到托盘，程序继续在后台运行提醒；'
                  '要彻底退出请右键托盘图标 → 退出。',
                  style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
