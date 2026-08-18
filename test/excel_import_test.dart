// 导入解析测试：地点节点列填了内容但地图里没有对应节点时，
// 不跳过整行 —— 名称暂存进课程正常显示，id 忽略该地点并提示留意。
import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:iclass/models/app_settings.dart';
import 'package:iclass/models/topology.dart';
import 'package:iclass/services/excel_import_service.dart';

Uint8List _makeCourseSheetBytes() {
  final excel = Excel.createExcel();
  final sheet = excel['课程'];
  const header = [
    '课程名称', '教师', '教室', '星期(1-7)', '开始节次', '结束节次',
    '开始日期', '结束日期', '重复方式', '地点节点',
  ];
  sheet.appendRow(header.map((e) => TextCellValue(e)).toList());
  // 行 1：地点名称「实验楼」，地图里没有 → 名称暂存，正常导入
  sheet.appendRow([
    '高等数学', '张老师', 'A201', '1', '3', '4', '2026-08-31', '2027-01-17', '每周', '实验楼',
  ].map((e) => TextCellValue(e)).toList());
  // 行 2：地点 id「n_999999」，地图里没有 → 忽略地点，正常导入
  sheet.appendRow([
    '大学英语', '李老师', 'B101', '2', '1', '2', '2026-08-31', '2027-01-17', '每周', 'n_999999',
  ].map((e) => TextCellValue(e)).toList());
  // 行 3：地点名称「教学楼」，地图里有 → 直接关联节点
  sheet.appendRow([
    '大学物理', '王老师', 'C301', '3', '5', '6', '2026-08-31', '2027-01-17', '每周', '教学楼',
  ].map((e) => TextCellValue(e)).toList());
  excel.tables; // 触发懒解析，防止已删的 Sheet1 在 encode 时复活
  excel.delete('Sheet1');
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  final nodes = [TopologyNode(id: 'n_teach', name: '教学楼', lat: 0, lng: 0)];

  test('地点无对应节点时不跳过整行：名称暂存 / id 忽略提示 / 有节点直接关联', () {
    final result =
        TemplateExcelParser().parse(_makeCourseSheetBytes(), nodes, AppSettings());

    expect(result.errors, isEmpty);
    expect(result.courses.length, 3, reason: '三行都应被导入，不跳过');

    final c1 = result.courses[0];
    expect(c1.locationName, '实验楼');
    expect(c1.locationNodeId, isNull);
    expect(c1.room, 'A201');

    final c2 = result.courses[1];
    expect(c2.locationName, isNull);
    expect(c2.locationNodeId, isNull);
    expect(c2.room, 'B101');

    final c3 = result.courses[2];
    expect(c3.locationNodeId, 'n_teach');
    expect(c3.locationName, isNull);

    expect(result.warnings.length, 1);
    expect(result.warnings.single, contains('n_999999'));
    expect(result.warnings.single, contains('无对应地点'));
  });
}
