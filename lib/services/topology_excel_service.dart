import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';

import '../models/topology.dart';

/// 拓扑 Excel 导入结果：解析出的拓扑 + 逐行错误信息。
class TopologyExcelResult {
  final Topology topology;
  final List<String> errors; // 如 "节点表第 3 行：缺少节点ID"

  TopologyExcelResult(this.topology, this.errors);

  bool get hasErrors => errors.isNotEmpty;
}

/// 校园地图的 Excel 导入 / 导出。两个工作表：
/// 「节点」：节点ID | 名称 | 纬度lat | 经度lng
/// 「边」：起点节点ID | 终点节点ID | 步行秒数
class TopologyExcel {
  static const List<String> nodeHeader = ['节点ID', '名称', '纬度lat', '经度lng'];
  static const List<String> edgeHeader = ['起点节点ID', '终点节点ID', '步行秒数'];

  /// 生成标准模板（表头 + 三行节点示例 + 两行边示例）。
  static List<int> buildTemplate() {
    final excel = Excel.createExcel();
    final nodes = excel['节点'];
    nodes.appendRow(nodeHeader.map((e) => TextCellValue(e)).toList());
    nodes.appendRow([
      TextCellValue('n_dorm'),
      TextCellValue('宿舍楼'),
      TextCellValue('30.00000'),
      TextCellValue('120.00000'),
    ]);
    nodes.appendRow([
      TextCellValue('n_teach'),
      TextCellValue('教学楼'),
      TextCellValue('30.00100'),
      TextCellValue('120.00200'),
    ]);
    nodes.appendRow([
      TextCellValue('n_canteen'),
      TextCellValue('食堂'),
      TextCellValue('30.00200'),
      TextCellValue('120.00100'),
    ]);
    final edges = excel['边'];
    edges.appendRow(edgeHeader.map((e) => TextCellValue(e)).toList());
    edges.appendRow([
      TextCellValue('n_dorm'),
      TextCellValue('n_teach'),
      TextCellValue('300'),
    ]);
    edges.appendRow([
      TextCellValue('n_teach'),
      TextCellValue('n_canteen'),
      TextCellValue('180'),
    ]);
    // 去掉自带的空表 Sheet1：它排在第一个标签页，打开文件先看到空白页会以为文件是空的。
    // 先读一次 tables 触发全部解析，否则 encode 时会把已删的空表重新加回来
    excel.tables;
    excel.delete('Sheet1');
    final bytes = excel.encode();
    if (bytes == null) throw Exception('编码失败');
    return bytes;
  }

  /// 把当前拓扑导出为 Excel（节点 / 边两个工作表）。
  static List<int> buildExport(Topology topology) {
    final excel = Excel.createExcel();
    final nodes = excel['节点'];
    nodes.appendRow(nodeHeader.map((e) => TextCellValue(e)).toList());
    for (final n in topology.nodes) {
      nodes.appendRow([
        TextCellValue(n.id),
        TextCellValue(n.name),
        TextCellValue(n.lat.toString()),
        TextCellValue(n.lng.toString()),
      ]);
    }
    final edges = excel['边'];
    edges.appendRow(edgeHeader.map((e) => TextCellValue(e)).toList());
    for (final e in topology.edges) {
      edges.appendRow([
        TextCellValue(e.from),
        TextCellValue(e.to),
        TextCellValue(e.timeSeconds.toString()),
      ]);
    }
    // 去掉自带的空表 Sheet1：否则打开文件先看到空白页，像"文件是空的"。
    // 先读一次 tables 触发全部解析，否则 encode 时会把已删的空表重新加回来
    excel.tables;
    excel.delete('Sheet1');
    final bytes = excel.encode();
    if (bytes == null) throw Exception('编码失败');
    return bytes;
  }

  /// 解析拓扑 Excel：有效行进结果，坏行进 [TopologyExcelResult.errors]（带行号）。
  /// 优先按表名找「节点」「边」；找不到时按顺序（第一张 = 节点，第二张 = 边）。
  static TopologyExcelResult parse(Uint8List bytes) {
    final nodes = <TopologyNode>[];
    final edges = <TopologyEdge>[];
    final errors = <String>[];

    try {
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) {
        return TopologyExcelResult(Topology(), ['文件中没有工作表']);
      }
      var nodeTable = excel.tables['节点'];
      var edgeTable = excel.tables['边'];
      if (nodeTable == null || edgeTable == null) {
        final tables = excel.tables.values.toList();
        nodeTable ??= tables.isNotEmpty ? tables[0] : null;
        edgeTable ??= tables.length > 1 ? tables[1] : null;
      }
      if (nodeTable == null) {
        return TopologyExcelResult(Topology(), ['没有找到「节点」工作表']);
      }

      final ids = <String>{};
      final nodeRows = nodeTable.rows.toList();
      for (var i = 1; i < nodeRows.length; i++) {
        final row = nodeRows[i];
        if (_rowEmpty(row)) continue;
        final id = _cell(row, 0);
        final name = _cell(row, 1);
        final lat = double.tryParse(_cell(row, 2));
        final lng = double.tryParse(_cell(row, 3));
        if (id.isEmpty) {
          errors.add('节点表第 ${i + 1} 行：缺少节点ID');
          continue;
        }
        if (!ids.add(id)) {
          errors.add('节点表第 ${i + 1} 行：节点ID「$id」重复');
          continue;
        }
        if (name.isEmpty || lat == null || lng == null) {
          errors.add('节点表第 ${i + 1} 行：名称或坐标格式错误');
          continue;
        }
        nodes.add(TopologyNode(id: id, name: name, lat: lat, lng: lng));
      }
      if (nodes.isEmpty) {
        errors.add('节点表没有可导入的节点');
      }

      if (edgeTable != null) {
        final edgeRows = edgeTable.rows.toList();
        for (var i = 1; i < edgeRows.length; i++) {
          final row = edgeRows[i];
          if (_rowEmpty(row)) continue;
          final from = _cell(row, 0);
          final to = _cell(row, 1);
          final seconds = num.tryParse(_cell(row, 2))?.toInt();
          if (from.isEmpty || to.isEmpty) {
            errors.add('边表第 ${i + 1} 行：缺少起点/终点节点ID');
            continue;
          }
          if (!ids.contains(from) || !ids.contains(to)) {
            errors.add('边表第 ${i + 1} 行：起点或终点节点不存在（先填好节点表）');
            continue;
          }
          if (seconds == null || seconds <= 0) {
            errors.add('边表第 ${i + 1} 行：步行秒数格式错误');
            continue;
          }
          edges.add(TopologyEdge(from: from, to: to, timeSeconds: seconds));
        }
      }
    } catch (e) {
      errors.add('文件解析失败：$e');
    }
    return TopologyExcelResult(Topology(nodes: nodes, edges: edges), errors);
  }

  static bool _rowEmpty(dynamic row) =>
      row.every((c) => c?.value == null || c!.value.toString().trim().isEmpty);

  static String _cell(dynamic row, int col) {
    final v = row.length > col ? row[col]?.value : null;
    return v == null ? '' : v.toString().trim();
  }
}
