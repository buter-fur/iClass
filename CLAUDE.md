# iClass — 校园课表与智能课前提醒

Flutter Windows 桌面应用（后续同一套代码上 Android/iOS/macOS）。
核心功能：周课表 + 校园拓扑地图（Dijkstra 最短步行时间）+ 课前智能提醒。

## 常用命令

```bash
# 运行（调试）
flutter run -d windows

# 构建 release exe（输出在 build/windows/x64/runner/Release/）
flutter build windows

# 重新生成静态资源（提示音/图标，纯 Python 无需第三方库）
python tools/gen_assets.py

# 依赖更新
flutter pub get
```

## 数据文件

- 位置：`Documents\iClass\`（用户文档目录下的 iClass 子文件夹）
- `courses.json` — 课程列表（含 `excludedDates` 停课日期，由「删除本节」写入）
- `topology.json` — 校园拓扑（节点 + 步行边）
- `settings.json` — 全部设置（节次表、学期开始日期、当前位置、外观 `themeMode`、已提醒记录等）
- 三个文件都是 JSON，可直接用记事本查看/修改/备份

## 架构

- 状态管理：单例 `DataStore`（ChangeNotifier）+ `ListenableBuilder`，不用第三方状态库
- `lib/models/` — 数据模型（course/period/topology/settings 等）
- `lib/services/` — 业务逻辑：
  - `reminder_engine.dart` — 提醒引擎（每 2 分钟 tick，核心状态机）
  - `walk_estimator.dart` — 步行时长决策表（Dijkstra / 直线估算 / 固定提前兜底）
  - `path_finder.dart` — Dijkstra 最短路径
  - `data_store.dart` / `storage_service.dart` — JSON 存储（原子写）
  - `time_service.dart` — 时间来源（支持模拟时间调试）
  - `week_service.dart` — 学期周次/单双周计算
- `lib/screens/` — 界面：home（课表+下一节课卡片）、course_edit、period_settings、
  settings、import、topology
- `lib/widgets/` — timetable_grid、course_card、next_class_card、location_dropdown

## 提醒逻辑（核心规则）

- 期望到达 = 上课时间 − 提前分钟（默认 2）
- 理想提醒时刻 = 期望到达 − 步行分钟；无步行时长时 = 上课时间 − 固定提前（默认 15）
- 检查窗口开始 = min(上课前 20 分钟, 理想提醒时刻 − 5 分钟)，每 2 分钟检查
- 窗口内：现在出发的预计到达 > 期望到达 → 立即提醒（每节课只提醒一次，
  fired key 格式 `日期|课程id|开始节次` 持久化在 settings.json）
- 已上课但没提醒过 → 补提醒一次；课已结束 → 不再提醒
- 只提醒**今天**的课；"下一节课"卡片可显示未来 7 天的课

## 注意事项

- 编译器：VS2022 + "使用 C++ 的桌面开发"工作负载；**不要装 VS2026**（与 Flutter 冲突）
- 点击窗口关闭按钮 = 最小化到托盘（`windows/runner/main.cpp` 里有 `SetQuitOnClose(false)`）；
  彻底退出用托盘菜单"退出"
- 构建报 C1083（找不到 cpp_client_wrapper 里的 .cc 文件）时先跑
  `python tools/fix_ephemeral.py`——Flutter 3.47 偶发不完整生成 ephemeral 目录
- 重启应用前若报 LNK1168（exe 被占用），先 `taskkill //F //IM iclass.exe`
- 调包建议：tray_manager 锁 0.5.3；audioplayers 若与 VS2022 构建冲突回退 6.7.x
- 模拟时间（设置 → 开发者）用于调试提醒时机，改完记得清除
- 测试提醒按钮不写 fired key，不影响去重
- 删除课程分两种：删除全部（整条课程）/ 删除本节（当天写入 excludedDates，编辑页可见可恢复）
- 深色模式：语义色在 lib/theme.dart 的 IClassColors 里维护两套（浅/深），界面用 `context.iclColors` 取色
