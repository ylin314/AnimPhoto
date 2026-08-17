/// 扫描缓存：按 路径+大小+修改时间 命中即跳过重复检测，加速启动扫描。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/motion_photo.dart';
import 'log.dart';

/// 单条缓存（以图片路径为键）。
class ScanCacheEntry {
  const ScanCacheEntry({required this.size, required this.modified, this.info});

  final int size;
  final int modified;

  /// 单文件动态照片解析结果（null 表示未识别为单文件动态照片）。
  final MotionPhotoInfo? info;

  Map<String, dynamic> toJson() => {
    'size': size,
    'modified': modified,
    'info': info?.toCacheJson(),
  };

  static ScanCacheEntry fromJson(Map<String, dynamic> j) => ScanCacheEntry(
    size: j['size'] as int,
    modified: j['modified'] as int,
    info: j['info'] == null
        ? null
        : MotionPhotoInfo.fromCacheJson(
            (j['info'] as Map).cast<String, dynamic>(),
          ),
  );
}

class ScanCache {
  ScanCache._();

  static const int _version = 6;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/scan_cache_v$_version.json');
  }

  /// 删除所有版本的持久化扫描缓存，使下次进入主页执行全盘快速扫描。
  static Future<void> clearPersistent() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) return;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .last;
      if (!RegExp(r'^scan_cache_v\d+\.json$').hasMatch(name)) continue;
      try {
        await entity.delete();
      } catch (error) {
        log('删除扫描缓存失败（忽略）: ${entity.path} $error');
      }
    }
  }

  /// 读取缓存；不存在或损坏返回空表。
  static Future<Map<String, ScanCacheEntry>> load() async {
    try {
      return await loadFrom(await _file());
    } catch (e) {
      log('读取扫描缓存失败（忽略）: $e');
      return {};
    }
  }

  /// 从指定文件读取（供测试注入临时文件）。
  static Future<Map<String, ScanCacheEntry>> loadFrom(File f) async {
    if (!await f.exists()) return {};
    // 用字节读取 + 容错解码：缓存键是文件路径，可能含非 UTF-8 字节，
    // readAsString() 会因严格 UTF-8 解码失败而丢弃整个缓存，导致全量重扫。
    final bytes = await f.readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: true);
    final map = (jsonDecode(text) as Map).cast<String, dynamic>();
    return map.map(
      (k, v) => MapEntry(
        k,
        ScanCacheEntry.fromJson((v as Map).cast<String, dynamic>()),
      ),
    );
  }

  /// 覆盖保存缓存。
  static Future<void> save(Map<String, ScanCacheEntry> cache) async {
    try {
      await saveTo(cache, await _file());
    } catch (e) {
      log('写入扫描缓存失败（忽略）: $e');
    }
  }

  /// 保存到指定文件（供测试注入临时文件）。
  static Future<void> saveTo(Map<String, ScanCacheEntry> cache, File f) async {
    await f.parent.create(recursive: true);
    final text = jsonEncode(cache.map((k, v) => MapEntry(k, v.toJson())));
    await f.writeAsString(text);
  }
}
