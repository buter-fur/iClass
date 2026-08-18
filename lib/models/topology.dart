/// 校园拓扑地图：节点（每栋楼一个）+ 边（步行时间，单位秒）。
class TopologyNode {
  final String id;
  String name;
  double lat;
  double lng;

  TopologyNode({required this.id, required this.name, required this.lat, required this.lng});

  factory TopologyNode.fromJson(Map<String, dynamic> json) => TopologyNode(
        id: json['id'] as String,
        name: json['name'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'lat': lat, 'lng': lng};
}

class TopologyEdge {
  final String from;
  final String to;
  int timeSeconds;

  TopologyEdge({required this.from, required this.to, required this.timeSeconds});

  factory TopologyEdge.fromJson(Map<String, dynamic> json) => TopologyEdge(
        from: json['from'] as String,
        to: json['to'] as String,
        timeSeconds: json['time_seconds'] as int,
      );

  Map<String, dynamic> toJson() => {'from': from, 'to': to, 'time_seconds': timeSeconds};
}

/// 无向带权拓扑图。
class Topology {
  List<TopologyNode> nodes;
  List<TopologyEdge> edges;

  Topology({List<TopologyNode>? nodes, List<TopologyEdge>? edges})
      : nodes = nodes ?? [],
        edges = edges ?? [];

  factory Topology.fromJson(Map<String, dynamic> json) => Topology(
        nodes: (json['nodes'] as List<dynamic>? ?? [])
            .map((e) => TopologyNode.fromJson(e as Map<String, dynamic>))
            .toList(),
        edges: (json['edges'] as List<dynamic>? ?? [])
            .map((e) => TopologyEdge.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
      };

  bool get isEmpty => nodes.isEmpty;

  TopologyNode? nodeById(String id) {
    for (final n in nodes) {
      if (n.id == id) return n;
    }
    return null;
  }
}
