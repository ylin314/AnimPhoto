/// 动态照片转换应用服务。
///
/// 统一单张与批量转换流程：准备规范化输入、调用目标格式写入器、
/// 保存到系统相册，并负责清理所有临时文件。
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/motion_photo.dart';
import '../core/motion_photo_parser.dart';
import '../core/target_writer.dart';
import '../models/live_photo_entry.dart';
import '../platform/media_scan.dart';

class ConversionSaveResult {
  const ConversionSaveResult({required this.saved, required this.fileName});

  final bool saved;
  final String fileName;
}

class ConversionService {
  ConversionService._();

  /// APP 只提供已在安卓相册验证过的五种目标格式。
  /// Apple Live Photo 仅由网页端提供，不属于 Android APP 的目标枚举。
  static const Set<TargetFormat> stableTargets = {
    TargetFormat.google,
    TargetFormat.oppo,
    TargetFormat.vivo,
    TargetFormat.xiaomi,
    TargetFormat.honorHuawei,
  };

  static bool isStable(TargetFormat target) => stableTargets.contains(target);

  static String defaultStem(LivePhotoEntry entry) {
    final fileName = entry.media.fileName;
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  static Future<ConversionSaveResult> convertAndSave({
    required LivePhotoEntry entry,
    required TargetFormat target,
    required String outputStem,
  }) async {
    final temporaryDirectory = await getTemporaryDirectory();
    PreparedConversionSource? source;
    String? outputPath;
    try {
      source = await prepareSource(entry: entry);
      outputPath =
          '${temporaryDirectory.path}/animphoto_convert_${DateTime.now().microsecondsSinceEpoch}.jpg';
      await TargetWriter.convertToFile(
        srcPath: source.path,
        outPath: outputPath,
        info: source.info,
        target: target,
      );
      final fileName = '${_normalizeStem(outputStem)}.jpg';
      final saved = await MediaScanService.saveJpegToGallery(
        srcPath: outputPath,
        name: fileName,
      );
      return ConversionSaveResult(saved: saved, fileName: fileName);
    } finally {
      if (outputPath != null) await _deleteIfExists(outputPath);
      if (source?.temporary == true) await _deleteIfExists(source!.path);
    }
  }

  static Future<PreparedConversionSource> prepareSource({
    required LivePhotoEntry entry,
  }) async {
    final info = await MotionPhotoParser.analyzeForConversion(entry.info!);
    return PreparedConversionSource(path: info.path, info: info);
  }

  static String _normalizeStem(String value) {
    var stem = value.trim();
    final lower = stem.toLowerCase();
    if (lower.endsWith('.jpeg')) {
      stem = stem.substring(0, stem.length - 5);
    } else if (lower.endsWith('.jpg')) {
      stem = stem.substring(0, stem.length - 4);
    }
    return stem.isEmpty
        ? 'animphoto_${DateTime.now().millisecondsSinceEpoch}'
        : stem;
  }

  static Future<void> _deleteIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 临时文件清理失败不覆盖真实转换结果。
    }
  }
}

class PreparedConversionSource {
  const PreparedConversionSource({
    required this.path,
    required this.info,
    this.temporary = false,
  });

  final String path;
  final MotionPhotoInfo info;
  final bool temporary;
}
