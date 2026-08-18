import 'package:flutter/material.dart';

import '../models/course.dart';
import '../models/day_periods.dart';
import '../services/data_store.dart';
import '../services/reminder_engine.dart';
import '../services/time_service.dart';
import '../services/week_service.dart';
import '../theme.dart';
import '../utils/date_utils.dart';
import '../widgets/color_picker_dialog.dart';
import '../widgets/course_card.dart';
import '../widgets/delete_course_dialog.dart';

/// 添加/编辑课程。传入 [course] 表示编辑；否则是新建。
/// 从课表空格新建：预填星期、节次和点击的那一天（默认「不重复」，只上这一次）；
/// 从右下角按钮新建：默认从今天开始、每周重复到所在阶段（学期/假期）结束。
class CourseEditScreen extends StatefulWidget {
  final Course? course;
  final int? initialWeekday;
  final int? initialPeriod;
  final DateTime? initialDate; // 从课表空格新建时 = 点击的那一天
  final DateTime? occurrenceDate; // 点课表卡片进来时 = 那张卡片所在的那一天（删除本节用）

  const CourseEditScreen({
    super.key,
    this.course,
    this.initialWeekday,
    this.initialPeriod,
    this.initialDate,
    this.occurrenceDate,
  });

  @override
  State<CourseEditScreen> createState() => _CourseEditScreenState();
}

class _CourseEditScreenState extends State<CourseEditScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(text: widget.course?.name ?? '');
  late final TextEditingController _teacher = TextEditingController(text: widget.course?.teacher ?? '');
  late final TextEditingController _room = TextEditingController(text: widget.course?.room ?? '');
  late final TextEditingController _startPeriod =
      TextEditingController(text: '${widget.course?.startPeriod ?? widget.initialPeriod ?? 1}');
  late final TextEditingController _periodCount =
      TextEditingController(text: '${widget.course?.periodCount ?? 1}');
  late int _dayOfWeek = widget.course?.dayOfWeek ??
      widget.initialWeekday ??
      TimeService.instance.now().weekday; // 没指定星期时默认今天
  late String _parity = widget.course?.parity ??
      (widget.initialDate != null ? 'once' : 'all'); // 点空格 = 不重复，右下角 = 每周
  late DateTime _startDate = widget.course?.startDate ??
      widget.initialDate ??
      TimeService.instance.now();
  late DateTime _endDate = widget.course?.endDate ??
      widget.initialDate ??
      WeekService.phaseEndDate(_startDate, DataStore.instance.settings);
  late String? _locationNodeId = widget.course?.locationNodeId;
  /// 导入课表时暂存的地点名称（地图里还没有对应节点）；用户已手动选了节点时为 null。
  String? get _pendingLocationName =>
      _locationNodeId == null ? widget.course?.locationName : null;

  /// 课程关联的节点 id 已不在当前地图节点列表中（拓扑被替换或节点被删除）；
  /// 此时下拉框需要补占位项，否则 items 里没有对应 value 会断言崩溃。
  String? get _orphanNodeId {
    final id = _locationNodeId;
    if (id == null || id.isEmpty) return null;
    for (final n in DataStore.instance.topology.nodes) {
      if (n.id == id) return null;
    }
    return id;
  }
  late final List<String> _excludedDates = [...(widget.course?.excludedDates ?? [])]; // 停课日期
  late int? _colorValue = widget.course?.colorValue; // null = 自动配色
  late bool _useCustomTime =
      widget.course?.customStart != null && widget.course?.customEnd != null;
  late TimeOfDay _customStart = _defaultCustomTime(isStart: true);
  late TimeOfDay _customEnd = _defaultCustomTime(isStart: false);

  /// 自定义时间的默认值：已有自定义时间用之，否则取当前节次配置算出的时间。
  TimeOfDay _defaultCustomTime({required bool isStart}) {
    final custom = isStart ? widget.course?.customStart : widget.course?.customEnd;
    if (custom != null) return parseTimeOfDay(custom);
    final startPeriod = int.tryParse(_startPeriod.text) ?? 1;
    final count = int.tryParse(_periodCount.text) ?? 1;
    final dps = DayPeriods(DataStore.instance.settings.periods);
    final p = dps.periodAt(isStart ? startPeriod : startPeriod + count - 1);
    if (p != null) return parseTimeOfDay(isStart ? p.start : p.end);
    return isStart ? const TimeOfDay(hour: 8, minute: 0) : const TimeOfDay(hour: 8, minute: 45);
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _room.dispose();
    _startPeriod.dispose();
    _periodCount.dispose();
    super.dispose();
  }

  Future<void> _pickCustomTime({required bool isStart}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: isStart ? _customStart : _customEnd,
      helpText: isStart ? '自定义开始时间' : '自定义结束时间',
    );
    if (t == null) return;
    setState(() {
      if (isStart) {
        _customStart = t;
      } else {
        _customEnd = t;
      }
    });
  }

  /// 选择开始/结束日期。开始日期晚于结束日期时结束日期自动跟随；
  /// 结束日期早于开始日期时拒绝并提示。
  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2040, 12, 31),
      helpText: isStart ? '课程开始日期' : '课程结束日期',
    );
    if (picked == null) return;
    if (!isStart && picked.isBefore(_startDate)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('结束日期不能早于开始日期')),
        );
      }
      return;
    }
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    String? customStart;
    String? customEnd;
    if (_useCustomTime) {
      final s = _customStart.hour * 60 + _customStart.minute;
      final e = _customEnd.hour * 60 + _customEnd.minute;
      if (e <= s) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('结束时间必须晚于开始时间')),
        );
        return;
      }
      customStart = timeOfDayToHm(_customStart);
      customEnd = timeOfDayToHm(_customEnd);
    }
    final course = Course(
      id: widget.course?.id ?? DataStore.instance.newCourseId(),
      name: _name.text.trim(),
      teacher: _teacher.text.trim(),
      room: _room.text.trim(),
      dayOfWeek: _dayOfWeek,
      startPeriod: int.parse(_startPeriod.text),
      periodCount: int.parse(_periodCount.text),
      startDate: _startDate,
      endDate: _parity == 'once' ? _startDate : _endDate,
      parity: _parity,
      locationNodeId: _locationNodeId,
      // 仍"未关联"时保留导入暂存的地点名称；手动选了节点后清空暂存
      locationName: _locationNodeId == null ? widget.course?.locationName : null,
      customStart: customStart,
      customEnd: customEnd,
      colorValue: _colorValue,
      excludedDates: _excludedDates,
    );
    if (widget.course == null) {
      await DataStore.instance.addCourse(course);
    } else {
      await DataStore.instance.updateCourse(course);
    }
    ReminderEngine.instance.tick();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    // 删除确认：删除全部（整条课程）/ 删除本节（只删点进来的那一天）
    final choice = await showDeleteCourseDialog(
      context,
      course: widget.course!,
      occurrenceDate: widget.occurrenceDate,
    );
    if (choice == null) return;
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final nodes = DataStore.instance.topology.nodes;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.course == null ? '添加课程' : '编辑课程'),
        actions: [
          if (widget.course != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '删除课程',
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: '课程名称 *', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? '请填写课程名称' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _teacher,
                    decoration: const InputDecoration(labelText: '教师', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _room,
                    decoration: const InputDecoration(labelText: '教室', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _dayOfWeek,
                    decoration: const InputDecoration(labelText: '星期', border: OutlineInputBorder()),
                    items: [
                      for (var d = 1; d <= 7; d++)
                        DropdownMenuItem(value: d, child: Text(weekdayName(d))),
                    ],
                    onChanged: (v) => _dayOfWeek = v ?? 1,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _parity,
                    decoration: const InputDecoration(labelText: '重复方式', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('每周')),
                      DropdownMenuItem(value: 'odd', child: Text('单周')),
                      DropdownMenuItem(value: 'even', child: Text('双周')),
                      DropdownMenuItem(value: 'once', child: Text('不重复')),
                    ],
                    onChanged: (v) {
                      setState(() {
                        _parity = v ?? 'all';
                        if (_parity == 'once') {
                          _endDate = _startDate; // 不重复 = 只上开始日期这一天
                        } else if (_endDate == _startDate) {
                          // 从不重复切回重复：结束日期扩到所在阶段结束，避免只覆盖一天
                          _endDate = WeekService.phaseEndDate(
                              _startDate, DataStore.instance.settings);
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                if (_useCustomTime) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickCustomTime(isStart: true),
                      icon: const Icon(Icons.play_arrow_outlined, size: 16),
                      label: Text('开始 ${timeOfDayToHm(_customStart)}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickCustomTime(isStart: false),
                      icon: const Icon(Icons.stop_outlined, size: 16),
                      label: Text('结束 ${timeOfDayToHm(_customEnd)}'),
                    ),
                  ),
                ] else ...[
                  Expanded(
                    child: _numberField(_startPeriod, '开始节次 *'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _numberField(_periodCount, '持续节数 *'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickDate(isStart: true),
                    icon: const Icon(Icons.event_outlined, size: 16),
                    label: Text('开始日期 ${formatDate(_startDate)}'),
                  ),
                ),
                if (_parity != 'once') ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(isStart: false),
                      icon: const Icon(Icons.event_available_outlined, size: 16),
                      label: Text('结束日期 ${formatDate(_endDate)}'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _parity == 'once'
                  ? '仅上 ${formatDate(_startDate)}（${weekdayName(_startDate.weekday)} · ${_phaseLabel(_startDate)}）这一天'
                  : '${formatDate(_startDate)}（${_phaseLabel(_startDate)}）~ ${formatDate(_endDate)}'
                      '（${_phaseLabel(_endDate)}），范围内${_parityLabel(_parity)}',
              style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary),
            ),
            if (_excludedDates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final d in [..._excludedDates]) _excludedDateChip(d),
                ],
              ),
              Text(
                '以上日期已停课（点标签或 ✕ 立即恢复上课）',
                style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary),
              ),
            ],
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('自定义上下课时间'),
              value: _useCustomTime,
              onChanged: (v) {
                setState(() {
                  _useCustomTime = v;
                  if (v) {
                    // 打开时按当前节次字段刷新默认值
                    _customStart = _defaultCustomTime(isStart: true);
                    _customEnd = _defaultCustomTime(isStart: false);
                  }
                });
              },
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: _locationNodeId ?? '',
              decoration: InputDecoration(
                labelText: '地点节点（用于计算步行时间）',
                border: const OutlineInputBorder(),
                helperText: _pendingLocationName == null
                    ? '在「校园地图」页维护节点；不关联则按固定提前时间提醒'
                    : '「$_pendingLocationName」尚未在地图中找到，'
                        '导入地图节点数据后会自动匹配；也可在这里手动重新选择',
              ),
              items: [
                // 课程关联的节点已不在当前地图中（拓扑被替换/节点被删除）时，
                // 补一个占位项防止下拉框断言崩溃，重新选择即可
                if (_orphanNodeId != null)
                  DropdownMenuItem<String>(
                    value: _orphanNodeId,
                    child: Text('$_orphanNodeId（节点已不在地图中）'),
                  ),
                DropdownMenuItem<String>(
                  value: '',
                  child: Text(_pendingLocationName == null
                      ? '未关联'
                      : '未关联（暂存地点：$_pendingLocationName）'),
                ),
                ...nodes.map((n) => DropdownMenuItem<String>(value: n.id, child: Text(n.name))),
              ],
              onChanged: (v) => _locationNodeId = (v == null || v.isEmpty) ? null : v,
            ),
            const SizedBox(height: 16),
            Text(
              '卡片颜色：${_colorLabel()}',
              style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _colorDot(null),
                for (var i = 0; i < CourseCard.palette.length; i++)
                  _colorDot(CourseCard.palette[i].toARGB32(),
                      name: CourseCard.paletteNames[i]),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _pickCustomColor,
                  icon: const Icon(Icons.colorize_outlined, size: 16),
                  label: const Text('自定义颜色'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _colorValue == null
                      ? null
                      : () => setState(() => _colorValue = null),
                  child: const Text('恢复自动配色'),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('保存'),
          ),
        ),
      ),
    );
  }

  /// 停课日期标签：点标签或 ✕ 立即恢复当天的课（不依赖「保存」）。
  Widget _excludedDateChip(String d) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _restoreDate(d),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
              child: Text('$d 停课', style: const TextStyle(fontSize: 13)),
            ),
          ),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _restoreDate(d),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.close, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  /// 恢复某一天停课的课：本地状态 + 立即写盘。
  void _restoreDate(String d) {
    setState(() => _excludedDates.remove(d));
    DataStore.instance.restoreCourseDate(widget.course!, d);
    ReminderEngine.instance.tick();
  }

  /// 当前所选卡片颜色的名字（预设色显示预设名）。
  String _colorLabel() {
    final v = _colorValue;
    if (v == null) return '自动配色（按课程名+教师）';
    final i = CourseCard.palette.indexWhere((c) => c.toARGB32() == v);
    return i >= 0 ? CourseCard.paletteNames[i] : '自定义颜色';
  }

  /// 颜色圆点：点击选中该颜色；[value] 为 null 时表示自动配色。
  Widget _colorDot(int? value, {String? name}) {
    final selected = _colorValue == value;
    final primary = Theme.of(context).colorScheme.primary;
    return Tooltip(
      message: value == null ? '自动配色' : (name ?? '自定义颜色'),
      child: InkWell(
        onTap: () => setState(() => _colorValue = value),
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: value == null ? Colors.transparent : Color(value),
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? primary : Theme.of(context).dividerColor,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check, size: 16, color: primary)
              : (value == null
                  ? Icon(Icons.auto_awesome, size: 14, color: context.iclColors.textSecondary)
                  : null),
        ),
      ),
    );
  }

  /// 自定义颜色：弹出取色器对话框（色块调深浅 + 色相条调基础色），确定后写入 [_colorValue]。
  Future<void> _pickCustomColor() async {
    final picked = await ColorPickerDialog.show(
      context,
      initial: Color(_colorValue ?? 0xFFBFD9F5),
    );
    if (picked != null && mounted) {
      setState(() => _colorValue = picked.toARGB32());
    }
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      keyboardType: TextInputType.number,
      validator: (v) {
        final n = int.tryParse(v ?? '');
        if (n == null || n < 1) return '填数字';
        return null;
      },
    );
  }

  /// 日期在学年日历里的位置，如「秋季学期 第3周」。
  String _phaseLabel(DateTime d) {
    final ctx = WeekService.contextOf(d, DataStore.instance.settings);
    return '${ctx.phase.label} 第${ctx.week}周';
  }

  String _parityLabel(String parity) {
    switch (parity) {
      case 'odd':
        return '单周重复';
      case 'even':
        return '双周重复';
      case 'once':
        return '不重复';
      default:
        return '每周重复';
    }
  }
}
