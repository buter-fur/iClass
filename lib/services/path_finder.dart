import '../models/topology.dart';

/// 拓扑图最短路径（Dijkstra，无向带权图，边权 = 步行秒数）。
class PathFinder {
  /// 从 [startId] 到各可达节点的最短耗时（秒）；不可达的节点不在结果中。
  static Map<String, int> shortestTimes(Topology topology, String startId) {
    // 邻接表
    final graph = <String, Map<String, int>>{};
    for (final e in topology.edges) {
      graph.putIfAbsent(e.from, () => {})[e.to] = e.timeSeconds;
      graph.putIfAbsent(e.to, () => {})[e.from] = e.timeSeconds;
    }
    if (!graph.containsKey(startId)) return {};

    final dist = <String, int>{startId: 0};
    final visited = <String>{};
    while (true) {
      // 找未访问节点中距离最小的
      String? cur;
      var best = -1;
      dist.forEach((id, d) {
        if (!visited.contains(id) && (best < 0 || d < best)) {
          best = d;
          cur = id;
        }
      });
      final current = cur;
      if (current == null || best < 0) break;
      visited.add(current);
      (graph[current] ?? {}).forEach((next, w) {
        if (visited.contains(next)) return;
        final nd = best + w;
        if (!dist.containsKey(next) || nd < dist[next]!) {
          dist[next] = nd;
        }
      });
    }
    return dist;
  }

  /// 两点间最短步行秒数；同点返回 0；不可达返回 null。
  static int? walkSecondsBetween(Topology topology, String fromId, String toId) {
    if (fromId == toId) return 0;
    return shortestTimes(topology, fromId)[toId];
  }
}
