import 'dart:io';

import 'package:excel_plus/excel_plus.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/data_store.dart';
import '../services/excel_import_service.dart';
import '../services/reminder_engine.dart';
import '../theme.dart';
import '../utils/date_utils.dart';

/// 课表导入：选择标准模板 Excel 文件 → 解析 → 预览 → 导入。
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final ExcelParser _parser = TemplateExcelParser();
  ImportResult? _result;

  Future<void> _pickFile() async {
    const typeGroup = XTypeGroup(label: 'Excel 文件', extensions: ['xlsx', 'xls']);
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    final result =
        _parser.parse(bytes, DataStore.instance.topology.nodes, DataStore.instance.settings);
    setState(() => _result = result);
  }

  Future<void> _import() async {
    final result = _result;
    if (result == null || result.courses.isEmpty) return;
    // 识别到「节次时间」表：先同步节次设置，课程展示/提醒时间自动按新表重算
    var synced = false;
    if (result.adaptedPeriods != null) {
      final s = DataStore.instance.settings;
      s.periods
        ..clear()
        ..addAll(result.adaptedPeriods!);
      s.breaks
        ..clear()
        ..addAll(result.adaptedBreaks!);
      await DataStore.instance.saveSettings();
      synced = true;
    }
    await DataStore.instance.addCourses(result.courses);
    ReminderEngine.instance.tick();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(synced
            ? '成功导入 ${result.courses.length} 门课，节次设置已同步更新'
            : '成功导入 ${result.courses.length} 门课')),
      );
      setState(() => _result = null);
    }
  }

  /// 生成并保存标准模板 xlsx：两张表「课程」（10 列表头 + 两行示例）与
  /// 「节次时间」（单列，与当前节次设置一致，一行一节 "HH:mm-HH:mm"）。
  Future<void> _downloadTemplate() async {
    final location = await getSaveLocation(suggestedName: 'iClass课程导入模板.xlsx');
    if (location == null) return;
    try {
      final excel = Excel.createExcel();
      // 表一：课程
      final courses = excel['课程'];
      const header = ['课程名称', '教师', '教室', '星期(1-7)', '开始节次', '结束节次', '开始日期', '结束日期', '重复方式', '地点节点'];
      const example1 = ['高等数学', '张老师', 'A201', '1', '3', '4', '2026-08-31', '2027-01-17', '每周', '教学楼'];
      const example2 = ['大学物理实验', '李老师', 'B实验楼', '3', '7', '8', '2026-09-16', '2026-12-30', '双周', ''];
      courses.appendRow(header.map((e) => TextCellValue(e)).toList());
      courses.appendRow(example1.map((e) => TextCellValue(e)).toList());
      courses.appendRow(example2.map((e) => TextCellValue(e)).toList());
      // 表二：节次时间（A1 标题 + 每节一行，从第 1 节到最后一节依次写出）
      final periodsSheet = excel['节次时间'];
      periodsSheet.appendRow([TextCellValue('节次时间')]);
      for (final p in DataStore.instance.settings.periods) {
        periodsSheet.appendRow([TextCellValue('${p.start}-${p.end}')]);
      }
      // 先读 tables 触发全部懒解析，再删自带的空表 Sheet1；否则 encode 会把已删的空表加回来
      excel.tables;
      excel.delete('Sheet1');
      final bytes = excel.encode();
      if (bytes == null) throw Exception('编码失败');
      await File(location.path).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('模板已保存到 ${location.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存模板失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导入课表')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                FilledButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('选择 Excel 文件'),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _downloadTemplate,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('下载标准模板'),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final result = _result;
    if (result == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '选择 .xlsx 或 .xls 文件开始解析。\n\n标准模板包含两个工作表：\n'
                '「课程」：课程名称 | 教师 | 教室 | 星期(1-7) | 开始节次 | 结束节次 | '
                '开始日期 | 结束日期 | 重复方式 | 地点节点\n'
                '「节次时间」：从第一节到最后一节每节的上课时间（HH:mm-HH:mm），一行一节；\n'
                '导入时若识别到「节次时间」表，会自动同步节次设置，并把连续节次间不小于'
                '「自动识别休息的最小间隔」（默认 30 分钟，可在节次设置里修改）的间隔识别为休息时间。\n\n'
                '（"开始/结束日期"填 yyyy-mm-dd；"重复方式"填 每周/单周/双周/不重复；'
                '"地点节点"填地图里的节点名称或 id，可留空；\n'
                '建议优先导入地图（地点）数据再导入课表。填了名称但地图里暂时没有对应节点时，'
                '课程按"名称 教室"正常显示，之后导入地图数据会自动匹配关联；\n'
                '填了 id 却找不到对应地点时会忽略该地点并提示你留意；'
                '留空时若"教室"以楼名开头，如"教学楼101"，会自动关联"教学楼"节点）',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.iclColors.textSecondary, height: 1.6),
          ),
        ),
      );
    }
    return Column(
      children: [
        if (result.hasErrors)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              color: context.iclColors.errorCardBg,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('以下行有问题，不会被导入：',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ...result.errors.map((e) => Text('· $e', style: const TextStyle(fontSize: 12.5))),
                  ],
                ),
              ),
            ),
          ),
        if (result.warnings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              color: context.iclColors.infoCardBg,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('以下行已正常导入，但请留意：',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    ...result.warnings
                        .map((e) => Text('· $e', style: const TextStyle(fontSize: 12.5))),
                  ],
                ),
              ),
            ),
          ),
        if (result.adaptedPeriods != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              color: context.iclColors.infoCardBg,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.schedule, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '识别到「节次时间」表：${result.adaptedPeriods!.length} 节'
                      '（${result.adaptedPeriods!.first.start}-${result.adaptedPeriods!.last.end}），'
                      '自动识别休息 ${result.adaptedBreaks!.length} 段；导入时将同步更新节次设置',
                      style: const TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                  ),
                ]),
              ),
            ),
          )
        else if (!result.hasErrors)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('未识别到「节次时间」表，节次设置保持不变',
                style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary)),
          ),
        Expanded(
          child: result.courses.isEmpty
              ? const Center(child: Text('没有解析出可导入的课程'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: result.courses.length,
                  itemBuilder: (context, i) {
                    final c = result.courses[i];
                    // 已关联节点显示节点名；暂存的地点名称（地图暂无对应节点）也显示
                    final nodeName =
                        DataStore.instance.topology.nodeById(c.locationNodeId ?? '')?.name;
                    final placeName = nodeName ?? c.locationName;
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text(c.name),
                      subtitle: Text(
                        '${weekdayName(c.dayOfWeek)} '
                        '${c.periodCount == 1 ? '第${c.startPeriod}节' : '第${c.startPeriod}-${c.startPeriod + c.periodCount - 1}节'} · '
                        '${formatDate(c.startDate)}~${formatDate(c.endDate)} · ${_parityLabel(c.parity)}'
                        '${c.room.isEmpty ? '' : ' · ${c.room}'}'
                        '${placeName == null ? '' : ' · 地点：$placeName'}',
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: result.courses.isEmpty ? null : _import,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: Text(result.courses.isEmpty ? '没有可导入的课程' : '导入 ${result.courses.length} 门课'),
            ),
          ),
        ),
      ],
    );
  }

  String _parityLabel(String parity) {
    switch (parity) {
      case 'odd':
        return '单周';
      case 'even':
        return '双周';
      case 'once':
        return '不重复';
      default:
        return '每周';
    }
  }
}
