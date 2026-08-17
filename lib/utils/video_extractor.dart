/// 视频提取工具：从单文件动态照片中提取有效 MP4。
library;

import 'dart:io';

import '../models/live_photo_entry.dart';
import 'file_io.dart';

class VideoExtractor {
  VideoExtractor._();

  /// 提取视频到 [destDir]/video.mp4，返回路径。
  static Future<String> extract({
    required LivePhotoEntry entry,
    required String destDir,
  }) async {
    await Directory(destDir).create(recursive: true);
    final info = entry.info!;
    final videoPath = '$destDir/video.mp4';
    await FileIo.copyRange(
      entry.media.path,
      videoPath,
      info.videoOffset!,
      info.effectiveVideoEnd,
    );
    return videoPath;
  }
}
