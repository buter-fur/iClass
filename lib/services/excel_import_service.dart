import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';

import '../models/app_settings.dart';
import '../models/course.dart';
import '../models/day_periods.dart';
import '../models/period.dart';
import '../models/period_break.dart';
import '../models/topology.dart';
import '../utils/date_utils.dart';

/// Excel 导入结果：解析出的课程 + 逐行错误/提示信息。
/// [errors]：该行有问题，**不会被导入**（如缺少课程名称、日期格式错误）。
/// [warnings]：该行**已正常导入**，但需要用户留意（如地点 id 在地图中不存在）。
/// 识别到「节次时间」表时，[adaptedPeriods]/[adaptedBreaks] 携带
/// 适配后的节次与自动识别的休息时间（成对出现），导入时同步更新节次设置。
class ImportResult {
  final List<Course> courses;
  final List<String> errors; // 如 "第 3 行：缺少课程名称"
  final List<String> warnings; // 如 "第 3 行：地点 id「xxx」无对应地点"
  final List<Period>? adaptedPeriods;
  final List<PeriodBreak>? adaptedBreaks;

  ImportResult(this.courses, this.errors,
      {this.warnings = const [], this.adaptedPeriods, this.adaptedBreaks});

  bool get hasErrors => errors.isNotEmpty;
}

/// Excel 解析器接口。模板解析器已实现；教务系统导出解析器待用户提供样例。
/// [nodes] 是当前地图节点列表，用于把"地点节点"列的名称解析成节点 id；
/// [settings] 提供当前节次表（校验节次范围、解析「节次时间」表时沿用节次名称）。
abstract class ExcelParser {
  String get name;
  ImportResult parse(Uint8List bytes, List<TopologyNode> nodes, AppSettings settings);
}

/// 标准模板解析器。
///
/// 模板包含两个工作表：
/// 「课程」表头（第一行，共 10 列）：
/// 课程名称 | 教师 | 教室 | 星期(1-7) | 开始节次 | 结束节次 | 开始日期 | 结束日期 | 重复方式 | 地点节点
/// 其中"开始/结束日期"填 yyyy-mm-dd（如 2026-08-31），"重复方式"填
/// 每周 / 单周 / 双周 / 不重复（留空 = 每周）。"地点节点"填地图节点的
/// **名称或 id**（如"教学楼"）。地图里有对应节点 → 直接关联；
/// 填了但找不到时**不跳过整行**：内容像名称（含中文）→ 名称暂存进课程，
/// 按"名称 教室"正常显示，之后导入地图节点数据时会自动重新匹配关联；
/// 内容像 id → 忽略该地点导入其他部分，并在 [ImportResult.warnings] 提示留意。
/// 建议优先导入地图（地点）数据再导入课表，地点才能自动关联。
/// 留空时若"教室"以某个节点名开头（如"教学楼101"），自动关联该节点并把
/// 剩余部分（101）作为教室。
/// 「节次时间」表（可选）：单列，A1 为标题，从第 1 节到最后一节每行一个
/// "HH:mm-HH:mm"；识别到后导入时自动同步节次设置，连续节次间隔不小于
/// 设置的「自动识别休息的最小间隔」（默认 30 分钟）时自动识别为休息时间。
/// 没有该表时保持当前节次设置不变（旧模板兼容）。
class TemplateExcelParser implements ExcelParser {
  @override
  String get name => '标准模板';

  @override
  ImportResult parse(Uint8List bytes, List<TopologyNode> nodes, AppSettings settings) {
    final courses = <Course>[];
    final errors = <String>[];
    final warnings = <String>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    List<Period>? adapted;
    List<PeriodBreak>? adaptedBreaks;

    try {
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) {
        return ImportResult(courses, ['文件中没有工作表']);
      }

      // 「节次时间」表（可选）：先解析，识别到则导入时同步节次设置
      final periodTable = excel.tables['节次时间'];
      if (periodTable != null) {
        final parsed = _parsePeriodSheet(periodTable, settings, errors);
        if (parsed != null) {
          adapted = parsed.periods;
          adaptedBreaks = parsed.breaks;
        }
      }

      // 「课程」表：按表名 → A1 表头嗅探 → 第一张表（旧单表模板）的顺序查找
      final table = _findCourseTable(excel);
      if (table == null) {
        errors.add('没有找到「课程」工作表');
        return ImportResult(courses, errors, warnings: warnings,
            adaptedPeriods: adapted, adaptedBreaks: adaptedBreaks);
      }
      final rows = table.rows.toList();
      if (rows.length < 2) {
        return ImportResult(courses, ['表格为空（至少需要表头 + 一行数据）'],
            warnings: warnings,
            adaptedPeriods: adapted, adaptedBreaks: adaptedBreaks);
      }

      // 节次越界校验的边界：有「节次时间」表用适配结果，否则用当前节次设置
      final bound = adapted != null
          ? DayPeriods(adapted).maxPeriodIndex
          : (settings.periods.isEmpty ? 0 : DayPeriods(settings.periods).maxPeriodIndex);

      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];

        // 完全空行跳过
        if (_rowEmpty(row)) continue;

        final name = _cell(row, 0);
        if (name.isEmpty) {
          errors.add('第 ${i + 1} 行：缺少课程名称');
          continue;
        }

        final startDate = _parseDateCell(_cell(row, 6));
        final endDate = _parseDateCell(_cell(row, 7));
        if (startDate == null || endDate == null) {
          errors.add('第 ${i + 1} 行：开始/结束日期格式错误（应为 yyyy-mm-dd）');
          continue;
        }
        if (endDate.isBefore(startDate)) {
          errors.add('第 ${i + 1} 行：结束日期早于开始日期');
          continue;
        }

        // 地点节点：填节点 id 或名称。地图里能找到 → 关联节点；
        // 找不到时不跳过整行：名称（含中文）→ 暂存进课程正常显示，
        // 之后导入地图节点数据自动匹配；id → 忽略该地点导入其他部分并提示留意
        String? locationNodeId;
        String? locationName;
        final nodeRaw = _cell(row, 9);
        if (nodeRaw.isNotEmpty) {
          locationNodeId = _resolveNode(nodeRaw, nodes);
          if (locationNodeId == null) {
            if (_looksLikeName(nodeRaw)) {
              locationName = nodeRaw;
            } else {
              warnings.add('第 ${i + 1} 行：地点 id「$nodeRaw」无对应地点，'
                  '无法获取上课地点，请自行留意');
            }
          }
        }
        // 地点节点留空且没有暂存名称时，尝试从"教室"列自动识别楼名
        //（"教学楼101"→节点"教学楼"、教室"101"）
        var room = _cell(row, 2);
        if (locationNodeId == null && locationName == null) {
          final byNameLength = [...nodes]..sort((a, b) => b.name.length.compareTo(a.name.length));
          for (final n in byNameLength) {
            if (n.name.isEmpty) continue;
            if (room == n.name) {
              locationNodeId = n.id;
              room = '';
              break;
            }
            if (room.startsWith(n.name) && room.substring(n.name.length).trim().isNotEmpty) {
              locationNodeId = n.id;
              room = room.substring(n.name.length).trim();
              break;
            }
          }
        }

        try {
          final startPeriod = int.parse(_cell(row, 4));
          final endPeriod = int.parse(_cell(row, 5));
          if (startPeriod < 1 || endPeriod < startPeriod || (bound > 0 && endPeriod > bound)) {
            errors.add(bound > 0
                ? '第 ${i + 1} 行：节次超出节次时间表（共 $bound 节）'
                : '第 ${i + 1} 行：节次无效（开始节次应不小于 1，结束节次不能早于开始节次）');
            continue;
          }
          final dayOfWeek = int.parse(_cell(row, 3));
          if (dayOfWeek < 1 || dayOfWeek > 7) {
            errors.add('第 ${i + 1} 行：星期应为 1-7');
            continue;
          }
          courses.add(Course(
            id: 'imp_${stamp}_$i',
            name: name,
            teacher: _cell(row, 1),
            room: room,
            dayOfWeek: dayOfWeek,
            startPeriod: startPeriod,
            periodCount: endPeriod - startPeriod + 1,
            startDate: startDate,
            endDate: endDate,
            parity: _parseParity(_cell(row, 8)),
            locationNodeId: locationNodeId,
            locationName: locationName,
          ));
        } catch (e) {
          errors.add('第 ${i + 1} 行：格式错误（星期/节次应为数字）');
        }
      }
    } catch (e) {
      errors.add('文件解析失败：$e');
    }
    return ImportResult(courses, errors, warnings: warnings,
        adaptedPeriods: adapted, adaptedBreaks: adaptedBreaks);
  }

  /// 「课程」表查找：按表名 → A1 表头嗅探（防改名/重排）→ 第一张表（旧单表模板，
  /// 但要排除「节次时间」表，防止误当课程表解析）。
  dynamic _findCourseTable(Excel excel) {
    final byName = excel.tables['课程'];
    if (byName != null) return byName;
    final tables = excel.tables.values.toList();
    for (final t in tables) {
      final rows = t.rows.toList();
      if (rows.isEmpty) continue;
      final a1 = rows[0].isNotEmpty ? rows[0][0]?.value : null;
      if (a1 != null && a1.toString().trim() == '课程名称') return t;
    }
    final first = tables.isNotEmpty ? tables.first : null;
    if (first == null) return null;
    final rows = first.rows.toList();
    final a1 = rows.isNotEmpty && rows[0].isNotEmpty ? rows[0][0]?.value : null;
    if (a1 != null && a1.toString().trim() == '节次时间') return null;
    return first;
  }

  /// 解析「节次时间」表：第一行是标题，之后每行一个 "HH:mm-HH:mm"（单列）。
  /// 有效行的 index = 有效行序号（1 开始）；名称沿用现有同 index 节次的名称。
  /// 相邻节次间隔不小于 settings.autoBreakMinutes 时自动识别为休息时间。
  /// 没有有效行时返回 null。
  ({List<Period> periods, List<PeriodBreak> breaks})? _parsePeriodSheet(
      dynamic table, AppSettings settings, List<String> errors) {
    final periods = <Period>[];
    final breaks = <PeriodBreak>[];
    final names = {for (final p in settings.periods) p.index: p.name};
    final rows = table.rows.toList();
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (_rowEmpty(row)) continue;
      final range = parseHmRange(_cell(row, 0));
      if (range == null) {
        errors.add('节次时间表第 ${i + 1} 行：时间格式错误（应为 HH:mm-HH:mm）');
        continue;
      }
      if (periods.isNotEmpty && range.$1 < hmToMinutes(periods.last.end)) {
        errors.add('节次时间表第 ${i + 1} 行：开始时间必须晚于上一节结束时间');
        continue;
      }
      final index = periods.length + 1;
      periods.add(Period(
          index: index, start: hm(range.$1), end: hm(range.$2), name: names[index] ?? ''));
    }
    if (periods.isEmpty) {
      errors.add('「节次时间」表没有可用的节次行');
      return null;
    }
    for (var i = 0; i < periods.length - 1; i++) {
      final gap = hmToMinutes(periods[i + 1].start) - hmToMinutes(periods[i].end);
      if (gap >= settings.autoBreakMinutes) {
        breaks.add(PeriodBreak(start: periods[i].end, end: periods[i + 1].start));
      }
    }
    Period.recomputeBreakGaps(periods); // 课后课间时长按真实间隔填充
    return (periods: periods, breaks: breaks);
  }

  static bool _rowEmpty(dynamic row) =>
      row.every((c) => c?.value == null || c!.value.toString().trim().isEmpty);

  static String _cell(dynamic row, int col) {
    final v = row.length > col ? row[col]?.value : null;
    return v == null ? '' : v.toString().trim();
  }

  /// 地点节点列：优先按节点 id 精确匹配，再按节点名称精确匹配；找不到返回 null。
  String? _resolveNode(String raw, List<TopologyNode> nodes) {
    final v = raw.trim();
    for (final n in nodes) {
      if (n.id == v) return n.id;
    }
    for (final n in nodes) {
      if (n.name == v) return n.id;
    }
    return null;
  }

  /// 判断地点列填的是节点名称还是 id：含中文字符 → 名称；否则 → id。
  /// 节点 id 由软件自动生成（形如 n_175...），也可以自己起（d1、teach_build 等
  /// 字母数字），都不含中文；节点名称一般是中文叫法（宿舍、教学楼等）。
  bool _looksLikeName(String s) => s.contains(RegExp(r'[一-鿿]'));

  /// 日期单元格：支持 "yyyy-mm-dd"、"yyyy/m/d" 等文本，也兼容 Excel 数字序列日期。
  DateTime? _parseDateCell(String s) {
    if (s.isEmpty) return null;
    final t = s.trim();
    final d = DateTime.tryParse(t);
    if (d != null) return DateTime(d.year, d.month, d.day);
    final n = num.tryParse(t);
    if (n != null && n > 20000 && n < 80000) {
      // Excel 序列日期（1900 日期系统）
      return DateTime(1899, 12, 30).add(Duration(days: n.toInt()));
    }
    return null;
  }

  String _parseParity(String s) {
    switch (s) {
      case '单周':
      case '单':
        return 'odd';
      case '双周':
      case '双':
        return 'even';
      case '不重复':
        return 'once';
      default:
        return 'all';
    }
  }
}

/// 教务系统导出解析器：待用户提供教务系统的 Excel 样例文件后实现。
class SchoolExportParser implements ExcelParser {
  @override
  String get name => '教务系统导出';

  @override
  ImportResult parse(Uint8List bytes, List<TopologyNode> nodes, AppSettings settings) {
    return ImportResult([], [
      '教务系统导出解析尚未完成：需要你提供学校教务系统导出的 Excel 样例文件，'
          '我根据样例定制解析规则。请先用标准模板导入。'
    ]);
  }
}
