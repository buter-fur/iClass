import 'package:flutter/material.dart';

import '../services/data_store.dart';
import '../services/reminder_engine.dart';

/// "我现在在哪"下拉框（Windows 版手动选择拓扑节点，主界面和设置页共用）。
class LocationDropdown extends StatelessWidget {
  const LocationDropdown({super.key});

  @override
  Widget build(BuildContext context) {
    final store = DataStore.instance;
    final nodes = store.topology.nodes;
    final current = store.settings.currentLocationNodeId;
    // 选的节点被删除后自动当作未选择
    final validCurrent = nodes.any((n) => n.id == current) ? current : null;

    return Row(
      children: [
        Icon(Icons.place_outlined, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        const Text('我在哪：'),
        const SizedBox(width: 8),
        Flexible(
          child: DropdownButton<String>(
            value: validCurrent ?? '',
            isExpanded: true,
            items: [
              const DropdownMenuItem<String>(value: '', child: Text('未选择（按固定提前时间提醒）')),
              ...nodes.map(
                (n) => DropdownMenuItem<String>(value: n.id, child: Text(n.name, overflow: TextOverflow.ellipsis)),
              ),
            ],
            onChanged: (v) async {
              // 注意：值不能用 null 代表"未选择"（设置了 hint 的 DropdownButton 会忽略 null 选项）
              await store.setCurrentLocation(v == null || v.isEmpty ? null : v);
              ReminderEngine.instance.tick(); // 位置变了立即重新计算提醒
            },
          ),
        ),
      ],
    );
  }
}
