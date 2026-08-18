import '../utils/date_utils.dart';

/// 课程模型。
///
/// [dayOfWeek]：1=周一 … 7=周日
/// [startDate]/[endDate]：课程生效的日期范围（含首尾两天）。课程只在这段日期内出现，
/// 不会自动复制到其他学期；日期超出学期范围时，假期周次延续编号、单双周判断连续。
/// [parity]："all"（每周）| "odd"（单周）| "even"（双周）| "once"（不重复，
/// 只在 startDate 当天上一次）
/// [locationNodeId]：关联的拓扑节点 id，可为空（表示未关联地图）。
/// [locationName]：导入课表时填的地点名称，但当时地图里还没有对应节点——
/// 名称暂存在这里正常显示（"名称 教室"），之后导入地图节点数据时会按名称
/// 自动重新匹配关联（匹配成功即转成 [locationNodeId] 并清空暂存）。
/// [customStart]/[customEnd]：自定义上下课时间 "HH:mm"（两个同时设置才生效），
/// 可不落在节次边界上，课表卡片按实际占时显示、可跨节次分界线。
class Course {
  final String id;
  String name;
  String teacher;
  String room;
  int dayOfWeek;
  int startPeriod; // 开始节次，从 1 开始
  int periodCount; // 持续节数
  DateTime startDate; // 生效开始日期（含当天）
  DateTime endDate; // 生效结束日期（含当天）；不重复时 = startDate
  String parity;
  String? locationNodeId;
  String? locationName; // 导入时暂存的地点名称（地图里还没有对应节点时）
  String? customStart; // 自定义上课时间 "HH:mm"
  String? customEnd; // 自定义下课时间 "HH:mm"
  int? colorValue; // 自定义卡片颜色（ARGB 值）；null = 按课程名+教师自动配色
  List<String> excludedDates; // 停课日期（"yyyy-MM-dd"）：「删除本节」只把这一天排除

  Course({
    required this.id,
    required this.name,
    this.teacher = '',
    this.room = '',
    required this.dayOfWeek,
    required this.startPeriod,
    this.periodCount = 1,
    required this.startDate,
    required this.endDate,
    this.parity = 'all',
    this.locationNodeId,
    this.locationName,
    this.customStart,
    this.customEnd,
    this.colorValue,
    List<String>? excludedDates,
  }) : excludedDates = excludedDates ?? [];

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as String,
        name: json['name'] as String,
        teacher: (json['teacher'] as String?) ?? '',
        room: (json['room'] as String?) ?? '',
        dayOfWeek: json['dayOfWeek'] as int,
        startPeriod: json['startPeriod'] as int,
        periodCount: (json['periodCount'] as int?) ?? 1,
        // 旧数据只有周次（startWeek/endWeek）：由 DataStore 加载时先换算成日期
        startDate: parseDate(json['startDate'] as String? ?? '') ?? DateTime(2020, 1, 1),
        endDate: parseDate(json['endDate'] as String? ?? '') ?? DateTime(2020, 1, 1),
        parity: (json['parity'] as String?) ?? 'all',
        locationNodeId: json['locationNodeId'] as String?,
        locationName: json['locationName'] as String?,
        customStart: json['customStart'] as String?,
        customEnd: json['customEnd'] as String?,
        colorValue: (json['colorValue'] as num?)?.toInt(),
        excludedDates: ((json['excludedDates'] as List<dynamic>?) ?? [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'teacher': teacher,
        'room': room,
        'dayOfWeek': dayOfWeek,
        'startPeriod': startPeriod,
        'periodCount': periodCount,
        'startDate': formatDate(startDate),
        'endDate': formatDate(endDate),
        'parity': parity,
        'locationNodeId': locationNodeId,
        'locationName': locationName,
        'customStart': customStart,
        'customEnd': customEnd,
        'colorValue': colorValue,
        'excludedDates': excludedDates,
      };

  Course copy() => Course.fromJson(toJson());
}
