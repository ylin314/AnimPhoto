import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/update_cleanup_config.dart';
import '../features/onboarding/intro_page.dart';
import '../features/scan/unsupported_intro_page.dart';
import '../utils/feature_guide_prefs.dart';
import '../utils/log.dart';
import '../utils/scan_cache.dart';
import 'share_service.dart';

class UpdateCleanupOptions {
  const UpdateCleanupOptions({
    required this.migrationId,
    this.clearScanCache = false,
    this.resetAppIntro = false,
    this.resetUnsupportedPhotosIntro = false,
    this.resetMultiSelectEntryGuide = false,
    this.resetMultiSelectActionsGuide = false,
    this.resetPhotoMenuGuide = false,
    this.clearShareLinkCache = false,
    this.clearDiagnosticLog = false,
    this.clearTemporaryFiles = false,
  });

  const UpdateCleanupOptions.fromConfig()
    : migrationId = UpdateCleanupConfig.migrationId,
      clearScanCache = UpdateCleanupConfig.clearScanCache,
      resetAppIntro = UpdateCleanupConfig.resetAppIntro,
      resetUnsupportedPhotosIntro =
          UpdateCleanupConfig.resetUnsupportedPhotosIntro,
      resetMultiSelectEntryGuide =
          UpdateCleanupConfig.resetMultiSelectEntryGuide,
      resetMultiSelectActionsGuide =
          UpdateCleanupConfig.resetMultiSelectActionsGuide,
      resetPhotoMenuGuide = UpdateCleanupConfig.resetPhotoMenuGuide,
      clearShareLinkCache = UpdateCleanupConfig.clearShareLinkCache,
      clearDiagnosticLog = UpdateCleanupConfig.clearDiagnosticLog,
      clearTemporaryFiles = UpdateCleanupConfig.clearTemporaryFiles;

  final String migrationId;
  final bool clearScanCache;
  final bool resetAppIntro;
  final bool resetUnsupportedPhotosIntro;
  final bool resetMultiSelectEntryGuide;
  final bool resetMultiSelectActionsGuide;
  final bool resetPhotoMenuGuide;
  final bool clearShareLinkCache;
  final bool clearDiagnosticLog;
  final bool clearTemporaryFiles;
}

class UpdateCleanupService {
  UpdateCleanupService._();

  static const String appliedMigrationPreferenceKey =
      'animphoto.update_cleanup.applied_migration';

  static Future<void> run({
    UpdateCleanupOptions options = const UpdateCleanupOptions.fromConfig(),
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(appliedMigrationPreferenceKey) == options.migrationId) {
      return;
    }

    log('执行版本更新本地数据清理：${options.migrationId}');
    if (options.clearScanCache) await ScanCache.clearPersistent();
    if (options.resetAppIntro) await prefs.remove(kIntroNeverShowKey);
    if (options.resetUnsupportedPhotosIntro) {
      await prefs.remove(kUnsupportedIntroNeverShowKey);
    }
    if (options.resetMultiSelectEntryGuide) {
      await prefs.remove(kMultiSelectUsedKey);
    }
    if (options.resetMultiSelectActionsGuide) {
      await prefs.remove(kMultiSelectActionsGuideCompletedKey);
    }
    if (options.resetPhotoMenuGuide) {
      await prefs.remove(kPhotoMenuGuideCompletedKey);
    }
    if (options.clearShareLinkCache) await ShareService.clearLocalCache();
    if (options.clearDiagnosticLog) await clearLog();
    if (options.clearTemporaryFiles) await _clearTemporaryFiles();

    // 只有所有清理项执行完毕后才记录完成；中途失败会在下次启动重试。
    await prefs.setString(appliedMigrationPreferenceKey, options.migrationId);
    log('版本更新本地数据清理完成：${options.migrationId}');
  }

  static Future<void> _clearTemporaryFiles() async {
    final temp = await getTemporaryDirectory();
    if (!await temp.exists()) return;
    await for (final entity in temp.list(followLinks: false)) {
      final segments = entity.uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (segments.isEmpty || !_isOwnedTemporaryName(segments.last)) continue;
      try {
        await entity.delete(recursive: entity is Directory);
      } catch (error) {
        log('删除临时文件失败（忽略）：${entity.path} $error');
      }
    }
  }

  static bool _isOwnedTemporaryName(String name) {
    return name.startsWith('animphoto_convert_') ||
        name.startsWith('pair_source_') ||
        name.startsWith('extract_') ||
        name.endsWith('_video.mp4');
  }
}
