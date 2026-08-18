import 'package:flutter/material.dart';

/// iClass 自定义语义色：浅色/深色两套，挂在 ThemeData.extensions 上，
/// 界面统一用 `context.iclColors` 取色，切换主题时自动生效。
/// 注意：课程卡片固定使用浅色 pastel 底 + 深色文字，两套主题一致。
class IClassColors extends ThemeExtension<IClassColors> {
  final Color headerBg; // 课表表头 / 节次标签背景
  final Color headerTodayBg; // 今天高亮的表头背景
  final Color todayColumnBg; // 今天所在整列的背景色（表头下方）
  final Color infoCardBg; // 信息卡背景（下一节课卡片、地图说明卡）
  final Color pillBg; // 顶部"我在哪"胶囊背景
  final Color errorCardBg; // 导入错误卡背景
  final Color gridLine; // 课表网格线
  final Color textSecondary; // 辅助文字（替代 Colors.black54）
  final Color cardTextSecondary; // 课程卡片上的次级文字

  const IClassColors({
    required this.headerBg,
    required this.headerTodayBg,
    required this.todayColumnBg,
    required this.infoCardBg,
    required this.pillBg,
    required this.errorCardBg,
    required this.gridLine,
    required this.textSecondary,
    required this.cardTextSecondary,
  });

  /// 浅色（与原设计完全一致）。
  static const light = IClassColors(
    headerBg: Color(0xFFE8F1FA),
    headerTodayBg: Color(0xFFD6E8F7),
    todayColumnBg: Color(0x1F5B9BD5), // 淡蓝 12%，当天整列淡淡的蓝底
    infoCardBg: Color(0xFFDCEBF9),
    pillBg: Color(0xFFE8F1FA),
    errorCardBg: Color(0xFFFDF0F0),
    gridLine: Color(0x1F000000), // black12
    textSecondary: Colors.black54,
    cardTextSecondary: Colors.black54,
  );

  /// 深色（结构不变只换颜色）。
  static const dark = IClassColors(
    headerBg: Color(0xFF202B3A),
    headerTodayBg: Color(0xFF31445C),
    todayColumnBg: Color(0x2E5B9BD5), // 深色下加大透明度才看得清
    infoCardBg: Color(0xFF1E2833),
    pillBg: Color(0xFF202B3A),
    errorCardBg: Color(0xFF3A2626),
    gridLine: Color(0x1FFFFFFF), // white12
    textSecondary: Color(0xFFA9BACB),
    cardTextSecondary: Colors.black54,
  );

  @override
  IClassColors copyWith({
    Color? headerBg,
    Color? headerTodayBg,
    Color? todayColumnBg,
    Color? infoCardBg,
    Color? pillBg,
    Color? errorCardBg,
    Color? gridLine,
    Color? textSecondary,
    Color? cardTextSecondary,
  }) {
    return IClassColors(
      headerBg: headerBg ?? this.headerBg,
      headerTodayBg: headerTodayBg ?? this.headerTodayBg,
      todayColumnBg: todayColumnBg ?? this.todayColumnBg,
      infoCardBg: infoCardBg ?? this.infoCardBg,
      pillBg: pillBg ?? this.pillBg,
      errorCardBg: errorCardBg ?? this.errorCardBg,
      gridLine: gridLine ?? this.gridLine,
      textSecondary: textSecondary ?? this.textSecondary,
      cardTextSecondary: cardTextSecondary ?? this.cardTextSecondary,
    );
  }

  @override
  IClassColors lerp(ThemeExtension<IClassColors>? other, double t) {
    if (other is! IClassColors) return this;
    return IClassColors(
      headerBg: Color.lerp(headerBg, other.headerBg, t)!,
      headerTodayBg: Color.lerp(headerTodayBg, other.headerTodayBg, t)!,
      todayColumnBg: Color.lerp(todayColumnBg, other.todayColumnBg, t)!,
      infoCardBg: Color.lerp(infoCardBg, other.infoCardBg, t)!,
      pillBg: Color.lerp(pillBg, other.pillBg, t)!,
      errorCardBg: Color.lerp(errorCardBg, other.errorCardBg, t)!,
      gridLine: Color.lerp(gridLine, other.gridLine, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      cardTextSecondary: Color.lerp(cardTextSecondary, other.cardTextSecondary, t)!,
    );
  }
}

extension IClassThemeX on BuildContext {
  IClassColors get iclColors =>
      Theme.of(this).extension<IClassColors>() ?? IClassColors.light;
}
