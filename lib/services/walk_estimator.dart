import 'dart:math';

import '../models/course.dart';
import '../models/topology.dart';
import '../models/walk_estimate.dart';
import 'path_finder.dart';

/// 步行时长决策表（按顺序判定，对应需求文档 4.6 的边界情况）。
///
/// 说明：直线距离估算需要两端坐标，节点缺失时算不出直线，
/// 此时按"能算直线就直线，算不出用固定提前分钟兜底"处理（见 DataStore 设置）。
class WalkEstimator {
  /// 直线估算参数：路径系数 1.3，步行速度 1.2 m/s。
  static const double pathFactor = 1.3;
  static const double walkSpeedMps = 1.2;

  static WalkEstimate estimate({
    required Course course,
    required String? currentLocationNodeId,
    required Topology topology,
    required int fallbackAdvanceMinutes,
  }) {
    // 1. 未选择当前位置
    if (currentLocationNodeId == null || currentLocationNodeId.isEmpty) {
      return WalkEstimate(
        walkMinutes: null,
        source: WalkEstimateSource.fallbackNoLocation,
        hint: '未选择当前位置，按提前 $fallbackAdvanceMinutes 分钟提醒',
      );
    }

    // 2. 课程未关联地图节点
    final courseNodeId = course.locationNodeId;
    if (courseNodeId == null || courseNodeId.isEmpty) {
      return WalkEstimate(
        walkMinutes: null,
        source: WalkEstimateSource.fallbackNoCourseNode,
        hint: '该课程未关联地图节点，按提前 $fallbackAdvanceMinutes 分钟提醒',
      );
    }

    // 3. 拓扑缺节点 / 为空
    final from = topology.nodeById(currentLocationNodeId);
    final to = topology.nodeById(courseNodeId);
    if (from == null || to == null) {
      return const WalkEstimate(
        walkMinutes: null,
        source: WalkEstimateSource.fallbackTopologyMissing,
        hint: '当前地点未录入校园地图',
      );
    }

    // 4. 同节点
    if (currentLocationNodeId == courseNodeId) {
      return const WalkEstimate(
        walkMinutes: 0,
        source: WalkEstimateSource.sameNode,
        hint: '当前位置就是上课地点',
      );
    }

    // 5. Dijkstra 有路径（分钟向上取整，宁可早提醒不迟到）
    final seconds = PathFinder.walkSecondsBetween(topology, currentLocationNodeId, courseNodeId);
    if (seconds != null) {
      final minutes = (seconds / 60).ceil();
      return WalkEstimate(
        walkMinutes: minutes,
        source: WalkEstimateSource.dijkstra,
        hint: '步行约 $minutes 分钟',
      );
    }

    // 6. 两点无连通路径 → 直线距离估算
    final meters = haversineMeters(from, to);
    final minutes = (meters * pathFactor / walkSpeedMps / 60).ceil();
    return WalkEstimate(
      walkMinutes: minutes,
      source: WalkEstimateSource.straightLine,
      hint: '两点未连通，按直线距离估算',
    );
  }

  /// 球面直线距离（米），haversine 公式。
  static double haversineMeters(TopologyNode a, TopologyNode b) {
    const earthRadius = 6371000.0;
    final dLat = (b.lat - a.lat) * pi / 180;
    final dLng = (b.lng - a.lng) * pi / 180;
    final lat1 = a.lat * pi / 180;
    final lat2 = b.lat * pi / 180;
    final h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    return 2 * earthRadius * asin(sqrt(h));
  }
}
