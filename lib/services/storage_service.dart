import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// iClass 数据文件夹下 JSON 文件的读写。
///
/// 默认位置是 Documents\iClass\；可以在设置里自定义位置——此时默认目录下会
/// 留一个 dir.txt 指针文件（内容是自定义文件夹的完整路径），启动时据此定位。
/// 便携模式：exe 同目录存在 portable.txt 标记文件时，数据保存在 exe 旁的
/// iClassData 文件夹（发布/分发版用，与开发测试用的 Documents\iClass 互不影响）。
/// 写入采用原子写（先写 .tmp 再改名），防止写入中断损坏文件；
/// 读取遇到损坏文件时自动备份为 .bak 并返回 null（调用方重建默认值）。
class StorageService {
  StorageService._();
  static final StorageService instance = StorageService._();

  static const _pointerFile = 'dir.txt';
  static const _portableMarker = 'portable.txt';
  static const _dataFiles = ['courses.json', 'topology.json', 'settings.json'];

  Directory? _dir;

  /// 是否便携模式（发布版：数据固定在 exe 旁的 iClassData 文件夹，不可换位置）。
  bool get isPortable => File(
          '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}$_portableMarker')
      .existsSync();

  /// 默认数据文件夹（Documents\iClass）。
  Future<Directory> _defaultDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}${Platform.pathSeparator}iClass');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  Future<Directory> get _dataDir async {
    if (_dir != null) return _dir!;
    // 便携模式优先：exe 同目录有 portable.txt → 数据在 exe 旁的 iClassData 文件夹
    if (isPortable) {
      final portable = Directory(
          '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}iClassData');
      if (!portable.existsSync()) portable.createSync(recursive: true);
      _dir = portable;
      return portable;
    }
    final def = await _defaultDir();
    var d = def;
    // 自定义数据文件夹：读默认目录里的指针文件 dir.txt（内容 = 目标文件夹路径）
    final pf = File('${def.path}${Platform.pathSeparator}$_pointerFile');
    if (pf.existsSync()) {
      try {
        final p = (await pf.readAsString()).trim();
        if (p.isNotEmpty) {
          final custom = Directory(p);
          if (!custom.existsSync()) custom.createSync(recursive: true);
          d = custom;
        }
      } catch (_) {} // 指针损坏时退回默认目录
    }
    _dir = d;
    return d;
  }

  /// 数据目录路径（如 Documents\iClass），供 UI 展示。
  Future<String> get dirPath async => (await _dataDir).path;

  /// 自定义数据文件夹位置：[newPath] 为 null 表示恢复默认位置。
  /// 会把现有数据文件整体搬过去（跨盘时复制后删除），并更新指针文件。
  /// 目标文件夹里已有 iClass 数据文件时抛异常拒绝，避免覆盖。
  Future<String> changeDataDir(String? newPath) async {
    // 便携版数据固定在 exe 旁的 iClassData，不支持换位置（dir.txt 指针只在标准版生效）
    if (isPortable) {
      throw Exception('便携版数据保存在程序文件夹内的 iClassData，不支持更改位置');
    }
    final oldDir = await _dataDir;
    final def = await _defaultDir();
    final custom = (newPath == null || newPath.trim().isEmpty);
    final target = custom ? def : Directory(newPath.trim());
    if (!target.existsSync()) target.createSync(recursive: true);
    if (target.path == oldDir.path) return target.path;

    // 目标目录里已有 iClass 数据文件 → 拒绝（防止两份数据混淆）
    for (final name in _dataFiles) {
      if (File('${target.path}${Platform.pathSeparator}$name').existsSync()) {
        throw Exception('目标文件夹里已有 iClass 数据文件，请选择一个空文件夹');
      }
    }

    // 搬数据文件（跨盘 rename 会失败，退回复制+删除）
    for (final name in _dataFiles) {
      final src = File('${oldDir.path}${Platform.pathSeparator}$name');
      if (!src.existsSync()) continue;
      try {
        src.renameSync('${target.path}${Platform.pathSeparator}$name');
      } catch (_) {
        src.copySync('${target.path}${Platform.pathSeparator}$name');
        try {
          src.deleteSync();
        } catch (_) {}
      }
    }

    // 更新指针文件：自定义 → 写入路径；恢复默认 → 删除指针
    final pf = File('${def.path}${Platform.pathSeparator}$_pointerFile');
    if (custom) {
      if (pf.existsSync()) pf.deleteSync();
    } else {
      await pf.writeAsString(target.path);
    }
    _dir = target;
    return target.path;
  }

  /// 在 Windows 资源管理器中打开数据文件夹（其他平台暂不支持，静默跳过）。
  Future<void> openDataDir() async {
    if (!Platform.isWindows) return;
    final d = await _dataDir;
    await Process.start('explorer', [d.path], mode: ProcessStartMode.detached);
  }

  /// 读取 JSON 文件；文件不存在或损坏返回 null（损坏时自动备份为 .bak）。
  Future<Map<String, dynamic>?> load(String name) async {
    final f = File('${(await _dataDir).path}${Platform.pathSeparator}$name');
    if (!f.existsSync()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      try {
        final bak = File('${f.path}.bak');
        if (bak.existsSync()) bak.deleteSync();
        f.renameSync(bak.path);
      } catch (_) {}
      return null;
    }
  }

  /// 写入队列：所有写盘串行执行，避免并发写共用 .tmp 的竞态。
  Future<void> _queue = Future.value();

  /// 写入 JSON 文件（原子写；并发调用自动排队）。
  Future<void> save(String name, Map<String, dynamic> json) {
    final task = _queue.then((_) => _doSave(name, json));
    // 单次失败不阻塞队列
    _queue = task.catchError((_) {});
    return task;
  }

  Future<void> _doSave(String name, Map<String, dynamic> json) async {
    final f = File('${(await _dataDir).path}${Platform.pathSeparator}$name');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(json));
    try {
      tmp.renameSync(f.path);
    } catch (_) {
      // 目标被占用（如 OneDrive 正在同步）：先删再改，仍失败就直接覆盖写
      try {
        if (f.existsSync()) f.deleteSync();
        tmp.renameSync(f.path);
      } catch (_) {
        await f.writeAsString(jsonEncode(json));
      }
    }
  }
}
