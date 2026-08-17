/// 系统相册动态照片扫描服务。
///
/// 负责权限、MediaStore 枚举、扫描缓存和单文件识别；
/// 页面只维护展示状态与扫描任务串行化。
library;

import '../core/brand.dart';
import '../core/motion_photo_parser.dart';
import '../models/live_photo_entry.dart';
import '../platform/media_scan.dart';
import '../utils/log.dart';
import '../utils/scan_cache.dart';

class GalleryScanProgress {
  const GalleryScanProgress({
    required this.scanned,
    required this.total,
    required this.found,
  });

  final int scanned;
  final int total;
  final int found;
}

class GalleryScanResult {
  const GalleryScanResult({
    required this.deviceBrand,
    required this.entries,
    required this.cacheHits,
  });

  final DeviceBrand deviceBrand;
  final List<LivePhotoEntry> entries;
  final int cacheHits;
}

class GalleryScanner {
  GalleryScanner._();

  static Future<GalleryScanResult> scan({
    required bool force,
    void Function(GalleryScanProgress progress)? onProgress,
  }) async {
    log('开始扫描（force=$force）');
    final rawBrand = await MediaScanService.getDeviceBrand();
    final deviceBrand = BrandDetector.fromManufacturer(rawBrand);

    if (!await MediaScanService.hasMediaPermission()) {
      log('未授权，请求媒体权限');
      await MediaScanService.requestMediaPermissions();
      if (!await MediaScanService.hasMediaPermission()) {
        log('媒体权限被拒绝');
        throw StateError('未授予相册读取权限，请在系统设置中授权后重试');
      }
    }

    final items = await MediaScanService.scanImages();
    log('相册图片总数: ${items.length}');

    final cache = force ? <String, ScanCacheEntry>{} : await ScanCache.load();
    log('缓存条目: ${cache.length}');

    final entries = <LivePhotoEntry>[];
    final newCache = <String, ScanCacheEntry>{};
    var hits = 0;
    var scanned = 0;
    onProgress?.call(
      GalleryScanProgress(scanned: 0, total: items.length, found: 0),
    );

    for (final media in items) {
      final cached = cache[media.path];
      var hit =
          cached != null &&
          cached.size == media.size &&
          cached.modified == media.modified;

      final validCached = hit ? cached : null;
      if (validCached != null) {
        hits++;
        if (validCached.info != null) {
          entries.add(LivePhotoEntry(media: media, info: validCached.info));
        }
        newCache[media.path] = validCached;
      } else {
        await _scanOne(media: media, entries: entries, newCache: newCache);
      }

      scanned++;
      onProgress?.call(
        GalleryScanProgress(
          scanned: scanned,
          total: items.length,
          found: entries.length,
        ),
      );
    }

    await ScanCache.save(newCache);
    log('扫描完成：命中缓存 $hits，共发现 ${entries.length} 条动态照片');
    return GalleryScanResult(
      deviceBrand: deviceBrand,
      entries: entries,
      cacheHits: hits,
    );
  }

  static Future<void> _scanOne({
    required MediaItem media,
    required List<LivePhotoEntry> entries,
    required Map<String, ScanCacheEntry> newCache,
  }) async {
    try {
      final info = await MotionPhotoParser.detectFile(media.path);
      if (info.isLivePhoto) {
        entries.add(LivePhotoEntry(media: media, info: info));
        newCache[media.path] = ScanCacheEntry(
          size: media.size,
          modified: media.modified,
          info: info,
        );
        log(
          '动态照片: ${media.fileName} 偏移=${info.videoOffset} '
          '方法=${info.videoOffsetMethod} 格式=${info.format}',
        );
        return;
      }

      newCache[media.path] = ScanCacheEntry(
        size: media.size,
        modified: media.modified,
      );
    } catch (error) {
      log('跳过 ${media.fileName}: $error');
      newCache[media.path] = ScanCacheEntry(
        size: media.size,
        modified: media.modified,
      );
    }
  }
}
