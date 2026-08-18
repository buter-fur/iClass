# iClass —— 校园课表与智能课前提醒

Flutter Windows 桌面应用：周课表 + 校园拓扑地图（Dijkstra 最短步行时间）+ 课前智能提醒。后续计划在**同一套代码**上扩展 Android / iOS / macOS（移动端用 GPS 自动匹配最近节点）。

## 功能特性

- **周课表**：星期 × 节次网格视图，支持周次翻页、单双周/不重复课程、自定义上下课时间（可跨节次边界）、「删除本节」停课、课程自定义配色
- **校园拓扑地图**：节点（每栋楼一个）+ 步行边，Dijkstra 计算最短步行时间；「我在哪」选择当前位置；支持 Excel / JSON 导入导出
- **智能提醒**：按"步行时间 + 提前到达量"的临界点提醒出发（系统通知 + 提示音），每节课只提醒一次、迟到补提醒；关窗最小化到托盘后台运行，可选开机自启动
- **Excel 课表导入**：标准模板（含「节次时间」表自动适配节次设置与休息时间）；地点列支持节点名称或 id，导入地图数据后自动重新匹配关联
- **深色模式**：浅色 / 深色 / 跟随系统

## 技术栈

- Flutter 3.47（Windows 桌面）
- 状态管理：单例 `ChangeNotifier`（DataStore）+ `ListenableBuilder`，无第三方状态库
- 数据存储：本地 JSON（`Documents\iClass\`，可直接查看 / 修改 / 备份；便携版在 exe 旁 `iClassData\`）

## 构建与运行

```bash
flutter pub get           # 安装依赖
flutter run -d windows    # 运行（调试）
flutter build windows     # 构建 release（输出在 build/windows/x64/runner/Release/）
python tools/gen_assets.py  # 重新生成提示音 / 图标资源（可选）
```

环境要求：Flutter SDK stable 3.47；Visual Studio 2022（勾选"使用 C++ 的桌面开发"工作负载）——**不要安装 VS2026**（与 Flutter 存在已知冲突）。

## 数据文件（Documents\iClass\）

| 文件 | 内容 |
|---|---|
| `courses.json` | 课程列表（含 `excludedDates` 停课日期） |
| `topology.json` | 校园拓扑（节点 + 步行边） |
| `settings.json` | 全部设置（节次表、休息时间、学期日历、当前位置、外观、已提醒记录等） |

三个文件都是普通 JSON，可直接用记事本查看 / 修改（建议改前先备份）。

## 目录结构

```
lib/
├── models/     数据模型（course / period / topology / settings 等）
├── services/   业务逻辑（提醒引擎、Dijkstra 路径、步行估算、JSON 存储、Excel 导入）
├── screens/    界面（课表、课程编辑、节次设置、设置、导入、校园地图）
├── widgets/    组件（课表网格、课程卡片、下一节课卡片、详情小窗）
└── theme.dart  主题（浅色/深色两套语义色）
tools/          开发辅助脚本（资源生成、图标转换、构建修复）
```

## 提醒逻辑（核心规则）

- 期望到达 = 上课时间 − 提前分钟（默认 2）
- 理想提醒时刻 = 期望到达 − 步行分钟；无步行时长时 = 上课时间 − 固定提前（默认 15）
- 检查窗口开始 = min(上课前 20 分钟, 理想提醒时刻 − 5 分钟)，每 2 分钟检查一次
- 窗口内"现在出发已来不及"→ 立即提醒；每节课只提醒一次（fired key 持久化，重启不重复）
- 只提醒**今天**的课；"下一节课"卡片可显示未来 7 天的课
