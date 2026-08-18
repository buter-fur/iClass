import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/topology.dart';
import '../services/data_store.dart';
import '../services/reminder_engine.dart';
import '../services/topology_excel_service.dart';
import '../theme.dart';

/// 校园地图（拓扑）管理：节点/边的增删改、JSON 导入导出。
/// 节点建议每栋楼一个（含 GPS 坐标），边为节点间步行秒数。
class TopologyScreen extends StatefulWidget {
  const TopologyScreen({super.key});

  @override
  State<TopologyScreen> createState() => _TopologyScreenState();
}

class _TopologyScreenState extends State<TopologyScreen> {
  Future<void> _importJson() async {
    const typeGroup = XTypeGroup(label: '拓扑 JSON 文件', extensions: ['json']);
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    try {
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final t = Topology.fromJson(map);
      final ids = <String>{};
      final dupIds = t.nodes.where((n) => !ids.add(n.id)).length;
      if (dupIds > 0) {
        _show('导入失败：有 $dupIds 个节点 id 重复，请检查 JSON 文件');
        return;
      }
      // 过滤掉引用不存在节点的边
      final badEdges = t.edges.where((e) => !ids.contains(e.from) || !ids.contains(e.to)).length;
      t.edges.removeWhere((e) => !ids.contains(e.from) || !ids.contains(e.to));
      await DataStore.instance.saveTopology(t);
      final relinked = await DataStore.instance.relinkCourseLocations();
      ReminderEngine.instance.tick();
      final base = '导入成功：${t.nodes.length} 个节点、${t.edges.length} 条边'
          '${badEdges > 0 ? '（忽略 $badEdges 条引用不存在节点的边）' : ''}';
      // 有暂存地点匹配上时用弹窗提示，避免被忽略
      if (relinked.isNotEmpty) {
        await _showMatchedDialog(relinked, base);
      } else {
        _show(base);
      }
    } catch (e) {
      _show('导入失败：JSON 格式错误（$e）');
    }
  }

  Future<void> _exportJson() async {
    final location = await getSaveLocation(suggestedName: 'topology.json');
    if (location == null) return;
    final json = const JsonEncoder.withIndent('  ')
        .convert(DataStore.instance.topology.toJson());
    await File(location.path).writeAsString(json);
    _show('已导出到 ${location.path}');
  }

  /// 生成 JSON 标准模板（两个示例节点 + 一条示例边，可直接改）。
  Future<void> _downloadJsonTemplate() async {
    final location = await getSaveLocation(suggestedName: 'topology.json');
    if (location == null) return;
    final json = const JsonEncoder.withIndent('  ').convert({
      '说明': '每栋楼一个节点（id 以 n_ 开头且唯一），边的 time_seconds 是实测步行秒数',
      'nodes': [
        {'id': 'n_dorm', 'name': '宿舍楼', 'lat': 30.00000, 'lng': 120.00000},
        {'id': 'n_teach', 'name': '教学楼', 'lat': 30.00100, 'lng': 120.00200},
      ],
      'edges': [
        {'from': 'n_dorm', 'to': 'n_teach', 'time_seconds': 300},
      ],
    });
    await File(location.path).writeAsString(json);
    _show('模板已保存到 ${location.path}');
  }

  /// Excel 直接导入：全部有效直接替换；有坏行先弹窗确认再导入有效部分。
  Future<void> _importExcel() async {
    const typeGroup = XTypeGroup(label: 'Excel 文件', extensions: ['xlsx', 'xls']);
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    final result = TopologyExcel.parse(await file.readAsBytes());
    if (!mounted) return;
    if (result.hasErrors) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('有 ${result.errors.length} 行有问题'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('以下行有问题，不会被导入：',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in result.errors)
                        Text('· $e', style: const TextStyle(fontSize: 12.5)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text('仍然导入有效部分吗？（会替换当前地图）'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('仍然导入')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await DataStore.instance.saveTopology(result.topology);
    final relinked = await DataStore.instance.relinkCourseLocations();
    ReminderEngine.instance.tick();
    final base = '导入成功：${result.topology.nodes.length} 个节点、'
        '${result.topology.edges.length} 条边'
        '${result.hasErrors ? '（已跳过问题行）' : ''}';
    // 有暂存地点匹配上时用弹窗提示，避免被忽略
    if (relinked.isNotEmpty) {
      await _showMatchedDialog(relinked, base);
    } else {
      _show(base);
    }
  }

  /// 生成 Excel 标准模板（节点 / 边两个工作表）。
  Future<void> _downloadExcelTemplate() async {
    final location = await getSaveLocation(suggestedName: '拓扑导入模板.xlsx');
    if (location == null) return;
    try {
      await File(location.path).writeAsBytes(TopologyExcel.buildTemplate());
      _show('模板已保存到 ${location.path}');
    } catch (e) {
      _show('保存模板失败：$e');
    }
  }

  Future<void> _exportExcel() async {
    final location = await getSaveLocation(suggestedName: 'topology.xlsx');
    if (location == null) return;
    try {
      await File(location.path)
          .writeAsBytes(TopologyExcel.buildExport(DataStore.instance.topology));
      _show('已导出到 ${location.path}');
    } catch (e) {
      _show('导出失败：$e');
    }
  }

  void _show(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  /// 导入成功后弹窗：提示有几门课的暂存地点（导入课表时地图里还没有对应节点）
  /// 已按名称自动匹配上节点，课程地点显示随之恢复。[names] 列出本次匹配的课程名。
  Future<void> _showMatchedDialog(List<String> names, String importSummary) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, color: Colors.green),
        title: Text('${names.length} 门课的暂存地点已自动匹配上节点'),
        content: Text(
          '${names.map((n) => '「$n」').join('、')}导入时填的地点名称在地图里还没有对应节点，'
          '现在已按名称自动关联，课表里的地点显示已恢复。\n\n'
          '$importSummary',
          style: const TextStyle(fontSize: 13, height: 1.6),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('好的')),
        ],
      ),
    );
  }

  /// 导入按钮下拉菜单的公共选项：直接导入 / 生成标准模板。
  static const _importMenuItems = [
    PopupMenuItem(value: 'import', child: Text('直接导入')),
    PopupMenuItem(value: 'template', child: Text('生成标准模板')),
  ];

  /// 带下拉菜单的按钮（外观与其他按钮一致）。
  Widget _menuButton({
    required IconData icon,
    required String label,
    required List<PopupMenuEntry<String>> items,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (context) => items,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13)),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  /// 复制节点 id 到剪贴板（可粘贴到课表导入模板的"地点节点"列）。
  Future<void> _copyNodeId(TopologyNode n) async {
    await Clipboard.setData(ClipboardData(text: n.id));
    _show('已复制节点 id：${n.id}');
  }

  Future<void> _addNode() async {
    final result = await showDialog<_NodeForm>(
      context: context,
      builder: (context) => const _NodeDialog(),
    );
    if (result == null) return;
    await DataStore.instance.addNode(TopologyNode(
      id: result.id,
      name: result.name,
      lat: result.lat,
      lng: result.lng,
    ));
    ReminderEngine.instance.tick();
  }

  Future<void> _editNode(TopologyNode node) async {
    final result = await showDialog<_NodeForm>(
      context: context,
      builder: (context) => _NodeDialog(node: node),
    );
    if (result == null) return;
    node.name = result.name;
    node.lat = result.lat;
    node.lng = result.lng;
    await DataStore.instance.updateNode(node);
    ReminderEngine.instance.tick();
  }

  Future<void> _deleteNode(TopologyNode node) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除节点'),
        content: Text('确定删除「${node.name}」吗？\n与该节点相连的边会一起删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await DataStore.instance.deleteNode(node.id);
    ReminderEngine.instance.tick();
  }

  Future<void> _addEdge() async {
    final result = await showDialog<_EdgeForm>(
      context: context,
      builder: (context) => const _EdgeDialog(),
    );
    if (result == null) return;
    await DataStore.instance.addEdge(TopologyEdge(
      from: result.from,
      to: result.to,
      timeSeconds: result.timeSeconds,
    ));
    ReminderEngine.instance.tick();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DataStore.instance,
      builder: (context, _) {
        final topology = DataStore.instance.topology;
        return Scaffold(
          appBar: AppBar(title: const Text('校园地图（拓扑）')),
          body: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Card(
                color: context.iclColors.infoCardBg,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '节点 ${topology.nodes.length} 个 · 边 ${topology.edges.length} 条',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '建议每栋楼/大门口一个节点（含 GPS 坐标），节点之间用"边"连接，'
                        '边的时长是实际走一遍测出的秒数。\n'
                        '节点 id 以 n_ 开头（软件自动生成形如 n_1751234567890；'
                        '自己起名也要 n_ 开头，如 n_dorm、n_teach），同一张图内不能重复。\n'
                        '支持 Excel / JSON 导入导出，可先点导入按钮里的「生成标准模板」拿到示例文件。',
                        style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _menuButton(
                    icon: Icons.grid_on_outlined,
                    label: 'Excel 导入',
                    items: _importMenuItems,
                    onSelected: (v) =>
                        v == 'import' ? _importExcel() : _downloadExcelTemplate(),
                  ),
                  _menuButton(
                    icon: Icons.data_object_outlined,
                    label: 'JSON 导入',
                    items: _importMenuItems,
                    onSelected: (v) =>
                        v == 'import' ? _importJson() : _downloadJsonTemplate(),
                  ),
                  _menuButton(
                    icon: Icons.save_alt_outlined,
                    label: '导出',
                    items: const [
                      PopupMenuItem(value: 'excel', child: Text('导出为 Excel')),
                      PopupMenuItem(value: 'json', child: Text('导出为 JSON')),
                    ],
                    onSelected: (v) => v == 'excel' ? _exportExcel() : _exportJson(),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _addNode,
                    icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                    label: const Text('添加节点'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: topology.nodes.length >= 2 ? _addEdge : null,
                    icon: const Icon(Icons.add_road_outlined, size: 18),
                    label: const Text('添加边'),
                  ),
                ],
              ),
              if (topology.nodes.length < 2)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('至少需要 2 个节点才能添加边',
                      style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                child: Text('节点',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary)),
              ),
              if (topology.nodes.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('还没有节点。可以点"导入 JSON"加载采集好的数据，或手动添加。'),
                ),
              for (final n in topology.nodes)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(n.name),
                  subtitle: Text('${n.id} · (${n.lat.toStringAsFixed(5)}, ${n.lng.toStringAsFixed(5)})'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.copy_outlined, size: 20),
                        tooltip: '复制节点 id',
                        onPressed: () => _copyNodeId(n),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20),
                        onPressed: () => _editNode(n),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _deleteNode(n),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                child: Text('边（步行时间）',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary)),
              ),
              if (topology.edges.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('还没有边。边连接两个节点，时长 = 步行秒数。'),
                ),
              for (var i = 0; i < topology.edges.length; i++)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.directions_walk_outlined),
                  title: Text(
                    '${_nodeName(topology, topology.edges[i].from)} → ${_nodeName(topology, topology.edges[i].to)}',
                  ),
                  subtitle: Text(
                    '${topology.edges[i].timeSeconds} 秒（约 ${(topology.edges[i].timeSeconds / 60).ceil()} 分钟）',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    onPressed: () async {
                      await DataStore.instance.deleteEdge(i);
                      ReminderEngine.instance.tick();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _nodeName(Topology topology, String id) {
    return topology.nodeById(id)?.name ?? id;
  }
}

class _NodeForm {
  final String id;
  final String name;
  final double lat;
  final double lng;
  _NodeForm(this.id, this.name, this.lat, this.lng);
}

/// 节点编辑对话框。
class _NodeDialog extends StatefulWidget {
  final TopologyNode? node;
  const _NodeDialog({this.node});

  @override
  State<_NodeDialog> createState() => _NodeDialogState();
}

class _NodeDialogState extends State<_NodeDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.node?.name ?? '');
  late final TextEditingController _lat =
      TextEditingController(text: widget.node?.lat.toString() ?? '');
  late final TextEditingController _lng =
      TextEditingController(text: widget.node?.lng.toString() ?? '');

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.node == null;
    return AlertDialog(
      title: Text(isNew ? '添加节点' : '编辑节点'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '名称（如：A宿舍门口）'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _lat,
                  decoration: const InputDecoration(labelText: '纬度 lat'),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _lng,
                  decoration: const InputDecoration(labelText: '经度 lng'),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          if (isNew) ...[
            const SizedBox(height: 8),
            Text(
              '节点 id 将自动生成',
              style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Text(
                    'id：${widget.node!.id}（不可修改）',
                    style: TextStyle(fontSize: 12, color: context.iclColors.textSecondary),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: widget.node!.id));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('已复制节点 id：${widget.node!.id}')),
                        );
                      }
                    },
                    child: Icon(Icons.copy_outlined,
                        size: 15, color: context.iclColors.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final lat = double.tryParse(_lat.text);
            final lng = double.tryParse(_lng.text);
            if (name.isEmpty || lat == null || lng == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请填写名称和坐标')),
              );
              return;
            }
            Navigator.pop(
              context,
              _NodeForm(
                widget.node?.id ?? 'n_${DateTime.now().millisecondsSinceEpoch}',
                name,
                lat,
                lng,
              ),
            );
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _EdgeForm {
  final String from;
  final String to;
  final int timeSeconds;
  _EdgeForm(this.from, this.to, this.timeSeconds);
}

/// 边编辑对话框。
class _EdgeDialog extends StatefulWidget {
  const _EdgeDialog();

  @override
  State<_EdgeDialog> createState() => _EdgeDialogState();
}

class _EdgeDialogState extends State<_EdgeDialog> {
  final _seconds = TextEditingController(text: '60');
  String? _from;
  String? _to;

  @override
  void dispose() {
    _seconds.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nodes = DataStore.instance.topology.nodes;
    return AlertDialog(
      title: const Text('添加边'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _from,
            decoration: const InputDecoration(labelText: '起点'),
            items: [
              for (final n in nodes) DropdownMenuItem(value: n.id, child: Text(n.name)),
            ],
            onChanged: (v) => setState(() => _from = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _to,
            decoration: const InputDecoration(labelText: '终点'),
            items: [
              for (final n in nodes) DropdownMenuItem(value: n.id, child: Text(n.name)),
            ],
            onChanged: (v) => setState(() => _to = v),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _seconds,
            decoration: const InputDecoration(labelText: '步行秒数', helperText: '实际走一遍测出的时间'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(
          onPressed: () {
            final seconds = int.tryParse(_seconds.text);
            if (_from == null || _to == null || seconds == null || seconds <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('请选择两个不同的节点并填写秒数')),
              );
              return;
            }
            if (_from == _to) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('起点和终点不能相同')),
              );
              return;
            }
            Navigator.pop(context, _EdgeForm(_from!, _to!, seconds));
          },
          child: const Text('添加'),
        ),
      ],
    );
  }
}
