/// 步行时长来源，对应 walk_estimator 的决策表。
enum WalkEstimateSource {
  fallbackNoLocation, // 未选择当前位置
  fallbackNoCourseNode, // 课程未关联地图节点
  fallbackTopologyMissing, // 拓扑缺节点/为空（"当前地点未录入校园地图"）
  sameNode, // 当前位置就是上课地点
  dijkstra, // 拓扑最短路径
  straightLine, // 直线距离估算（两点未连通）
}

/// 步行估算结果。
///
/// [walkMinutes] 为 null 表示无法计算步行时长，此时提醒引擎用
/// 固定的 fallbackAdvanceMinutes 提前提醒。
class WalkEstimate {
  final int? walkMinutes;
  final WalkEstimateSource source;
  final String hint; // 显示给用户的中文说明

  const WalkEstimate({
    required this.walkMinutes,
    required this.source,
    required this.hint,
  });
}
