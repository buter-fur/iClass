import 'package:flutter/material.dart';

import '../models/period.dart';
import '../models/period_break.dart';
import '../services/data_store.dart';
import '../services/reminder_engine.dart';
import '../theme.dart';
import '../utils/date_utils.dart';

/// 节次设置：全局一份节次表（所有星期共用）。
/// 支持"自动生成"（可带休息时间）、逐节手动编辑（可自定义节次名称与课后课间时长）、
/// 添加/删除休息时间（后面的节次自动顺延）。
class PeriodSettingsScreen extends StatefulWidget {
  const PeriodSettingsScreen({super.key});

  @override
  State<PeriodSettingsScreen> createState() => _PeriodSettingsScreenState();
}

class _PeriodSettingsScreenState extends State<PeriodSettingsScreen> {
  List<Period> get _periods => DataStore.instance.settings.periods;
  List<PeriodBreak> get _breaks => DataStore.instance.settings.breaks;

  void _show(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// 从 [fromMin] 起（含）的所有节次与休息整体平移 [delta] 分钟后，
  /// 是否会溢出当天 24:00（delta ≤ 0 只会更早，不可能溢出）。
  bool _wouldOverflow(List<Period> periods, List<PeriodBreak> breaks, int fromMin, int delta) {
    if (delta <= 0) return false;
    var maxEnd = fromMin;
    for (final q in periods) {
      if (hmToMinutes(q.start) >= fromMin && hmToMinutes(q.end) > maxEnd) {
        maxEnd = hmToMinutes(q.end);
      }
    }
    for (final b in breaks) {
      if (b.startMinutes >= fromMin && b.endMinutes > maxEnd) {
        maxEnd = b.endMinutes;
      }
    }
    return maxEnd + delta > 24 * 60;
  }

  Future<void> _addPeriod() async {
    final list = _periods;
    final nextIndex =
        list.isEmpty ? 1 : list.map((p) => p.index).reduce((a, b) => a > b ? a : b) + 1;
    // 默认时间：接在上一节之后（上一节有课间时长用它，否则默认课间 10 分钟）；第一节默认 08:00 开始
    var startMin = 8 * 60;
    if (list.isNotEmpty) {
      final last = list.reduce((a, b) => a.index > b.index ? a : b);
      final gap = last.breakAfterMinutes > 0 ? last.breakAfterMinutes : 10;
      startMin = hmToMinutes(last.end) + gap;
    }
    if (startMin + 50 > 24 * 60) {
      _show('新节次结束时间不能晚于 24:00，请先缩短上一节的课间时长');
      return;
    }
    list.add(Period(index: nextIndex, start: hm(startMin), end: hm(startMin + 50)));
    Period.recomputeBreakGaps(list); // 上一节的课间时长变为真实间隔
    await DataStore.instance.saveSettings();
    ReminderEngine.instance.tick();
  }

  /// 编辑一节：开始/结束时间 + 自定义名称 + 课后课间时长。
  /// 课间时长变化时，以编辑后的本节结束时间为界，后面的节次整体平移；
  /// 本节结束时间正后方的休息时间同步伸缩（缩到不合法则移除）。
  Future<void> _editPeriod(Period p) async {
    final isLast = identical(p, _lastPeriodByTime(_periods));
    final result = await showDialog<_PeriodForm>(
      context: context,
      builder: (context) => _PeriodDialog(period: p, isLast: isLast),
    );
    if (result == null) return;
    final settings = DataStore.instance.settings;
    p.start = result.start;
    p.end = result.end;
    p.name = result.name;
    // delta 以编辑前的存值为基准（存值 = 重算后的真实间隔），
    // 所以 delta >= -存值，顺延后下一节不会与本节重叠
    final delta = result.breakAfterMinutes - p.breakAfterMinutes;
    if (delta != 0) {
      final endMin = hmToMinutes(p.end);
      // 顺延后任何节次/休息都不能溢出当天 24:00
      if (_wouldOverflow(settings.periods, settings.breaks, endMin, delta)) {
        _show('课间时长过大，顺延后节次/休息时间不能晚于 24:00');
        return;
      }
      for (final q in settings.periods) {
        if (hmToMinutes(q.start) >= endMin) {
          q.start = hm(hmToMinutes(q.start) + delta);
          q.end = hm(hmToMinutes(q.end) + delta);
        }
      }
      // 本节结束时间正后方若有休息时间：同步伸缩；缩到 0 分钟以下（不合法）才移除
      final bi = settings.breaks.indexWhere((b) => b.startMinutes == endMin);
      final touched = bi >= 0 ? settings.breaks[bi] : null;
      if (bi >= 0) {
        final newEnd = touched!.endMinutes + delta;
        if (newEnd > touched.startMinutes) {
          touched.end = hm(newEnd);
        } else {
          settings.breaks.removeAt(bi);
          _show('课间时长已缩短，原休息时间已移除');
        }
      }
      // 平移范围内的其他休息时间跟着整体平移，保持与节次间隔一致
      // （正后方那条已在上面单独处理，跳过）
      for (final x in settings.breaks) {
        if (!identical(x, touched) && x.startMinutes >= endMin) {
          x.start = hm(x.startMinutes + delta);
          x.end = hm(x.endMinutes + delta);
        }
      }
    }
    Period.recomputeBreakGaps(settings.periods);
    await DataStore.instance.saveSettings();
    ReminderEngine.instance.tick();
  }

  Future<void> _deletePeriod(Period p) async {
    _periods.removeWhere((x) => x.index == p.index);
    Period.recomputeBreakGaps(_periods); // 前一个节次的课间时长跨过被删的节次重新计算
    await DataStore.instance.saveSettings();
    ReminderEngine.instance.tick();
  }

  /// 添加休息时间：检查与节次/已有休息不重叠，之后把后面的节次整体顺延。
  Future<void> _addBreak() async {
    final b = await showDialog<PeriodBreak>(
      context: context,
      builder: (context) => const _BreakDialog(),
    );
    if (b == null) return;
    final settings = DataStore.instance.settings;
    if (b.durationMinutes <= 0) {
      _show('结束时间必须晚于开始时间');
      return;
    }
    if (settings.breaks
        .any((x) => x.startMinutes < b.endMinutes && x.endMinutes > b.startMinutes)) {
      _show('与已有休息时间重叠，请调整时间');
      return;
    }
    if (settings.periods.any(
        (p) => hmToMinutes(p.start) < b.endMinutes && hmToMinutes(p.end) > b.startMinutes)) {
      _show('休息时间与上课节次重叠，请选在两节课之间');
      return;
    }
    // 顺延后的节次/休息不能溢出当天 24:00（自定义休息任意时长均可，只拦溢出）
    final dur = b.durationMinutes;
    if (_wouldOverflow(settings.periods, settings.breaks, b.startMinutes, dur)) {
      _show('添加该休息后节次/休息时间不能晚于 24:00，请缩短休息时长');
      return;
    }
    b.isCustom = true; // 手动添加的休息标注"自定义"，忠实显示不按阈值约束
    settings.breaks.add(b);
    settings.breaks.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    for (final p in settings.periods) {
      if (hmToMinutes(p.start) >= b.startMinutes) {
        p.start = hm(hmToMinutes(p.start) + dur);
        p.end = hm(hmToMinutes(p.end) + dur);
      }
    }
    // 顺延范围内的其他休息时间跟着整体顺延，保持与节次间隔一致（新添加的 b 除外）
    for (final x in settings.breaks) {
      if (!identical(x, b) && x.startMinutes >= b.startMinutes) {
        x.start = hm(x.startMinutes + dur);
        x.end = hm(x.endMinutes + dur);
      }
    }
    Period.recomputeBreakGaps(settings.periods); // 课间时长按顺延后的真实间隔重算
    await DataStore.instance.saveSettings();
    ReminderEngine.instance.tick();
  }

  /// 删除休息时间：休息之后的节次自动前移，恢复紧凑排课。
  Future<void> _deleteBreak(PeriodBreak b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除休息时间'),
        content: Text('删除 ${b.start} - ${b.end} 的休息？\n之后的节次会自动前移 ${b.durationMinutes} 分钟。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    final settings = DataStore.instance.settings;
    settings.breaks.remove(b);
    final dur = b.durationMinutes;
    for (final p in settings.periods) {
      if (hmToMinutes(p.start) >= b.endMinutes) {
        p.start = hm(hmToMinutes(p.start) - dur);
        p.end = hm(hmToMinutes(p.end) - dur);
      }
    }
    // 前移范围内的其他休息时间跟着整体前移，保持与节次间隔一致
    for (final x in settings.breaks) {
      if (x.startMinutes >= b.endMinutes) {
        x.start = hm(x.startMinutes - dur);
        x.end = hm(x.endMinutes - dur);
      }
    }
    Period.recomputeBreakGaps(settings.periods); // 课间时长按前移后的真实间隔重算
    await DataStore.instance.saveSettings();
    ReminderEngine.instance.tick();
  }

  /// 编辑"自动识别休息"的最小间隔（默认 30 分钟）。
  /// 保存后立即按新阈值对节次真实间隔重新判定休息时间。
  Future<void> _editAutoBreakMinutes() async {
    final settings = DataStore.instance.settings;
    final controller = TextEditingController(text: '${settings.autoBreakMinutes}');
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('自动识别休息的最小间隔'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分钟',
            hintText: '相邻节次间隔不小于该值时识别为休息（默认 30）',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text.trim())),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result < 1 || result > 600) {
      _show('请输入 1 - 600 之间的数字');
      return;
    }
    settings.autoBreakMinutes = result;
    final (added, removed) = _rejudgeBreaks();
    await DataStore.instance.saveSettings();
    if (added > 0 || removed > 0) {
      _show('已按新阈值重新判定休息时间：新增 $added 段，移除 $removed 段');
    }
  }

  /// 按最新阈值重新判定休息时间（阈值更改后调用）：
  /// - 节次真实间隔 ≥ 阈值且尚无休息覆盖 → 自动添加（非自定义）
  /// - 自动识别的休息（非自定义）时长 < 阈值 → 移除
  /// - 自定义休息（用户手动添加）不受阈值约束，始终保留
  /// 返回 (新增段数, 移除段数)。
  (int, int) _rejudgeBreaks() {
    final settings = DataStore.instance.settings;
    final threshold = settings.autoBreakMinutes;
    final periods = [...settings.periods]
      ..sort((a, b) => hmToMinutes(a.start).compareTo(hmToMinutes(b.start)));

    final before = settings.breaks.length;
    // 1) 低于新阈值的自动识别休息移除（自定义保留）
    settings.breaks.removeWhere((b) => !b.isCustom && b.durationMinutes < threshold);
    final removed = before - settings.breaks.length;

    // 2) 真实间隔 ≥ 阈值且无休息覆盖 → 自动添加
    var added = 0;
    for (var i = 0; i < periods.length - 1; i++) {
      final gapStart = hmToMinutes(periods[i].end);
      final gapEnd = hmToMinutes(periods[i + 1].start);
      if (gapEnd - gapStart < threshold) continue;
      final covered = settings.breaks
          .any((r) => r.startMinutes <= gapStart && r.endMinutes >= gapEnd);
      if (!covered) {
        settings.breaks.add(PeriodBreak(start: hm(gapStart), end: hm(gapEnd)));
        added++;
      }
    }
    settings.breaks.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return (added, removed);
  }

  Future<void> _openGenerator() async {
    final result = await showDialog<_GenParams>(
      context: context,
      builder: (context) => _GeneratorDialog(initialBreaks: [..._breaks]),
    );
    if (result == null) return;
    final periods = Period.generate(
      startMinutes: result.startMinutes,
      durationMinutes: result.durationMinutes,
      breakMinutes: result.breakMinutes,
      count: result.count,
      breaks: result.breaks,
    );
    // 生成结果整体替换全局节次表与休息时间
    final settings = DataStore.instance.settings;
    settings.periods
      ..clear()
      ..addAll(periods);
    settings.breaks
      ..clear()
      ..addAll(result.breaks);
    await DataStore.instance.saveSettings();
    ReminderEngine.instance.tick();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DataStore.instance,
      builder: (context, _) {
        final periods = _periods;
        final breaks = _breaks;
        final settings = DataStore.instance.settings;
        final lastPeriod = _lastPeriodByTime(periods);
        return Scaffold(
          appBar: AppBar(title: const Text('节次设置')),
          // 整页单一滚动列表：所有区块都是列表项，滚轮在任何位置都能滚动整页
          body: ListView(
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  '节次表全局通用：所有星期共用同一份节次与时间。',
                  style: TextStyle(fontSize: 12.5, color: context.iclColors.textSecondary),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _openGenerator,
                      icon: const Icon(Icons.auto_fix_high_outlined),
                      label: const Text('自动生成'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _addPeriod,
                      icon: const Icon(Icons.add),
                      label: const Text('添加一节'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _addBreak,
                      icon: const Icon(Icons.self_improvement_outlined),
                      label: const Text('添加休息'),
                    ),
                  ],
                ),
              ),
              // ---- 休息时间 ----
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('休息时间',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary)),
                ),
              ),
              if (breaks.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('还没有休息时间。点"添加休息"设置午休/晚休。',
                        style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary)),
                  ),
                ),
              for (final b in breaks)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.self_improvement_outlined),
                  title: Text('${b.start} - ${b.end}'),
                  subtitle: Text('休息 ${b.durationMinutes} 分钟${b.isCustom ? ' · 自定义' : ''}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteBreak(b),
                  ),
                ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.rule_outlined),
                title: const Text('自动识别休息的最小间隔'),
                subtitle: Text('相邻节次间隔 ≥ ${settings.autoBreakMinutes} 分钟时识别为休息'
                    '（Excel 导入节次时间表时生效）'),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: _editAutoBreakMinutes,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('节次',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary)),
                ),
              ),
              if (periods.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      '还没有节次\n点"自动生成"一键生成，或"添加一节"手动添加',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.iclColors.textSecondary),
                    ),
                  ),
                )
              else
                ...periods.asMap().entries.map((e) {
                  final p = e.value;
                  return Padding(
                    padding: EdgeInsets.fromLTRB(16, e.key == 0 ? 4 : 6, 16, 0),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFBFD9F5),
                        child: Text('${p.index}', style: const TextStyle(fontSize: 14)),
                      ),
                      title: Text(p.name.isEmpty ? '第${p.index}节' : '第${p.index}节 · ${p.name}'),
                      subtitle: Text(_periodSubtitle(p, lastPeriod)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _editPeriod(p),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deletePeriod(p),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  /// 节次列表副标题：时间 + 课后课间信息；当日最后一节单独标注。
  String _periodSubtitle(Period p, Period? lastPeriod) {
    final base = '${p.start} - ${p.end}';
    if (identical(p, lastPeriod)) return '$base · 当日最后一节';
    if (p.breakAfterMinutes > 0) return '$base · 课后课间 ${p.breakAfterMinutes} 分钟';
    return base;
  }

  /// 按上课开始时间排序后的最后一节（最后一节没有课间时长选项）。
  Period? _lastPeriodByTime(List<Period> list) {
    if (list.isEmpty) return null;
    return ([...list]..sort((a, b) => hmToMinutes(a.start).compareTo(hmToMinutes(b.start))))
        .last;
  }
}

class _GenParams {
  final int startMinutes;
  final int durationMinutes;
  final int breakMinutes;
  final int count;
  final List<PeriodBreak> breaks;

  _GenParams(this.startMinutes, this.durationMinutes, this.breakMinutes, this.count, this.breaks);
}

/// 自动生成对话框：首节开始时间、每节时长、课间休息、节数 + 休息时间列表。
/// 生成时节次会自动跳过休息时间（下一节起点落在休息内则顺延到休息结束）。
class _GeneratorDialog extends StatefulWidget {
  final List<PeriodBreak> initialBreaks;

  const _GeneratorDialog({required this.initialBreaks});

  @override
  State<_GeneratorDialog> createState() => _GeneratorDialogState();
}

class _GeneratorDialogState extends State<_GeneratorDialog> {
  TimeOfDay _start = const TimeOfDay(hour: 8, minute: 0);
  final _duration = TextEditingController(text: '50');
  final _break = TextEditingController(text: '10');
  final _count = TextEditingController(text: '12');
  late final List<PeriodBreak> _breaks = [...widget.initialBreaks];

  @override
  void dispose() {
    _duration.dispose();
    _break.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _addBreak() async {
    final b = await showDialog<PeriodBreak>(
      context: context,
      builder: (context) => const _BreakDialog(),
    );
    if (b == null) return;
    setState(() {
      _breaks.add(b);
      _breaks.sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自动生成节次'),
      scrollable: true, // 休息时间多时弹窗内容可滚动，避免溢出
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将覆盖现有的全局节次表与休息时间',
                style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary)),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('首节开始时间'),
              trailing: TextButton(
                onPressed: () async {
                  final t = await showTimePicker(context: context, initialTime: _start);
                  if (t != null) setState(() => _start = t);
                },
                child: Text(
                    '${_start.hour.toString().padLeft(2, '0')}:${_start.minute.toString().padLeft(2, '0')}'),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _duration,
                    decoration: const InputDecoration(labelText: '每节时长(分钟)'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _break,
                    decoration: const InputDecoration(labelText: '课间休息(分钟)'),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _count,
                    decoration: const InputDecoration(labelText: '节数'),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('休息时间（生成时自动跳过）',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _addBreak,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加休息'),
                ),
              ],
            ),
            for (final b in _breaks)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${b.start} - ${b.end}'),
                subtitle: Text('休息 ${b.durationMinutes} 分钟'),
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _breaks.remove(b)),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final duration = int.tryParse(_duration.text) ?? 50;
            final breakMin = int.tryParse(_break.text) ?? 10;
            final count = int.tryParse(_count.text) ?? 12;
            if (duration < 1 || breakMin < 0 || count < 1) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请填写正确的时长和节数')),
              );
              return;
            }
            Navigator.pop(
              context,
              _GenParams(
                _start.hour * 60 + _start.minute,
                duration,
                breakMin,
                count,
                [..._breaks],
              ),
            );
          },
          child: const Text('生成'),
        ),
      ],
    );
  }
}

class _PeriodForm {
  final String name;
  final String start;
  final String end;
  final int breakAfterMinutes;

  _PeriodForm(this.name, this.start, this.end, this.breakAfterMinutes);
}

/// 编辑一节：开始/结束时间 + 自定义名称（留空 = 显示"第 N 节"）+ 课后课间时长。
/// [isLast] 为 true（当日最后一节）时不显示课间时长输入框。
class _PeriodDialog extends StatefulWidget {
  final Period period;
  final bool isLast;

  const _PeriodDialog({required this.period, required this.isLast});

  @override
  State<_PeriodDialog> createState() => _PeriodDialogState();
}

class _PeriodDialogState extends State<_PeriodDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.period.name);
  late final TextEditingController _breakAfter =
      TextEditingController(text: widget.period.breakAfterMinutes.toString());
  late TimeOfDay _start = parseTimeOfDay(widget.period.start);
  late TimeOfDay _end = parseTimeOfDay(widget.period.end);

  @override
  void dispose() {
    _name.dispose();
    _breakAfter.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool isStart}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
      helpText: isStart ? '第${widget.period.index}节 开始时间' : '第${widget.period.index}节 结束时间',
    );
    if (t == null) return;
    setState(() {
      if (isStart) {
        _start = t;
      } else {
        _end = t;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final startMin = _start.hour * 60 + _start.minute;
    final endMin = _end.hour * 60 + _end.minute;
    return AlertDialog(
      title: Text('编辑第${widget.period.index}节'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: '节次名称（可选）',
              hintText: '留空则显示"第 ${widget.period.index} 节"',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isStart: true),
                  child: Text('开始 ${timeOfDayToHm(_start)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isStart: false),
                  child: Text('结束 ${timeOfDayToHm(_end)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            endMin > startMin
                ? '时长 ${endMin - startMin} 分钟'
                : '结束时间必须晚于开始时间',
            style: TextStyle(
                fontSize: 12,
                color: endMin > startMin
                    ? context.iclColors.textSecondary
                    : Colors.redAccent),
          ),
          if (widget.isLast)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('这是当日最后一节，课后无课间时长',
                  style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary)),
            )
          else ...[
            const SizedBox(height: 12),
            TextField(
              controller: _breakAfter,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '课间时长(分钟)',
                hintText: '本节结束到下一节开始；修改后后面的节次自动顺延',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            if (endMin <= startMin) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('结束时间必须晚于开始时间')),
              );
              return;
            }
            if (!widget.isLast) {
              final v = int.tryParse(_breakAfter.text.trim());
              if (v == null || v < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('课间时长应为不小于 0 的整数')),
                );
                return;
              }
            }
            Navigator.pop(
              context,
              _PeriodForm(
                _name.text.trim(),
                timeOfDayToHm(_start),
                timeOfDayToHm(_end),
                widget.isLast ? 0 : int.parse(_breakAfter.text.trim()),
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 添加休息时间：自由设置开始、结束时间（时长自动算出）。
class _BreakDialog extends StatefulWidget {
  const _BreakDialog();

  @override
  State<_BreakDialog> createState() => _BreakDialogState();
}

class _BreakDialogState extends State<_BreakDialog> {
  TimeOfDay _start = const TimeOfDay(hour: 12, minute: 0);
  TimeOfDay _end = const TimeOfDay(hour: 13, minute: 0);

  Future<void> _pick({required bool isStart}) async {
    final t = await showTimePicker(
      context: context,
      initialTime: isStart ? _start : _end,
      helpText: isStart ? '休息开始时间' : '休息结束时间',
    );
    if (t == null) return;
    setState(() {
      if (isStart) {
        _start = t;
        if (_end.hour * 60 + _end.minute <= _start.hour * 60 + _start.minute) {
          // 结束时间自动跟到开始时间之后（默认 1 小时）
          _end = TimeOfDay(
              hour: (_start.hour + 1) % 24, minute: _start.minute);
        }
      } else {
        _end = t;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final startMin = _start.hour * 60 + _start.minute;
    final endMin = _end.hour * 60 + _end.minute;
    return AlertDialog(
      title: const Text('添加休息时间'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('休息时间落在两节课之间',
              style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isStart: true),
                  child: Text('开始 ${timeOfDayToHm(_start)}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pick(isStart: false),
                  child: Text('结束 ${timeOfDayToHm(_end)}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            endMin > startMin ? '时长 ${endMin - startMin} 分钟' : '结束时间必须晚于开始时间',
            style: TextStyle(
                fontSize: 12,
                color: endMin > startMin
                    ? context.iclColors.textSecondary
                    : Colors.redAccent),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            if (endMin <= startMin) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('结束时间必须晚于开始时间')),
              );
              return;
            }
            Navigator.pop(
              context,
              PeriodBreak(start: timeOfDayToHm(_start), end: timeOfDayToHm(_end)),
            );
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}
