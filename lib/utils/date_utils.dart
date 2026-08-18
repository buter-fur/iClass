import 'package:flutter/material.dart' show TimeOfDay;

/// "HH:mm" 字符串 → 当天 00:00 起的时长。
Duration parseHm(String hm) {
  final parts = hm.split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  return Duration(hours: h, minutes: m);
}

/// 从 00:00 起的分钟数 → "HH:mm"。
String hm(int totalMinutes) {
  final h = (totalMinutes ~/ 60) % 24;
  final m = totalMinutes % 60;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// "HH:mm" → 分钟数。
int hmToMinutes(String hm) {
  final d = parseHm(hm);
  return d.inMinutes;
}

/// "HH:mm-HH:mm"（分隔符支持 -、~、—、–、～，两侧可带空格）→ (开始分钟, 结束分钟)。
/// 任一侧不是合法的 HH:mm（小时 0-23、分钟 0-59 且必须两位），
/// 或结束不晚于开始时，返回 null。
(int, int)? parseHmRange(String s) {
  final text = s.trim();
  if (text.isEmpty) return null;
  final sepIndex = text.indexOf(RegExp(r'[-~—–～]')); // 第一个分隔符
  if (sepIndex < 0) return null;
  final start = _strictHmToMinutes(text.substring(0, sepIndex).trim());
  final end = _strictHmToMinutes(text.substring(sepIndex + 1).trim());
  if (start == null || end == null || end <= start) return null;
  return (start, end);
}

/// 严格的 "HH:mm" 校验（小时 0-23、分钟 0-59、分钟必须两位），非法返回 null。
int? _strictHmToMinutes(String s) {
  final m = RegExp(r'^(\d{1,2})[:：](\d{2})$').firstMatch(s);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/// "yyyy-MM-dd" → DateTime，解析失败返回 null。
DateTime? parseDate(String s) {
  final parts = s.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

/// DateTime → "yyyy-MM-dd"。
String formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "HH:mm" 显示格式（去掉秒）。
String formatTime(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// 星期几的中文名。
const List<String> weekdayNames = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

String weekdayName(int weekday) => weekdayNames[weekday - 1];

/// "HH:mm" → TimeOfDay。
TimeOfDay parseTimeOfDay(String hm) {
  final parts = hm.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 0,
    minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
  );
}

/// TimeOfDay → "HH:mm"。
String timeOfDayToHm(TimeOfDay t) => hm(t.hour * 60 + t.minute);
