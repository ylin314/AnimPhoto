/// 批量视频提取：对选中的多张单文件动态照片逐张提取内嵌视频，
/// 保存到系统相册 Movies/AnimPhoto。
///
/// 流程：确认弹窗（是否全部提取）→ BatchProgressPage 进度页。
library;

import 'package:flutter/material.dart';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../core/brand.dart';
import '../../platform/media_scan.dart';
import '../../utils/video_extractor.dart';
import '../../models/live_photo_entry.dart';
import 'batch_progress_page.dart';

class BatchExtract {
  BatchExtract._();

  /// 入口：先弹确认对话框，用户同意后进入进度页执行批量提取。
  static Future<void> start(
    BuildContext context, {
    required List<LivePhotoEntry> entries,
    required DeviceBrand deviceBrand,
  }) async {
    if (entries.isEmpty) return;

    // 1) 确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量提取视频'),
        content: Text(
          '将对选中的 ${entries.length} 张动态照片逐张提取视频，'
          '并保存到相册「AnimPhoto」。是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('全部提取'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    // 2) 构造任务并进入进度页
    final tasks = <BatchTask>[
      for (final e in entries)
        BatchTask(
          title: e.media.fileName,
          subtitle: e.formatLabel,
          run: () => _extractOne(e),
        ),
    ];

    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            BatchProgressPage(kind: BatchKind.extractVideo, tasks: tasks),
      ),
    );
  }

  /// 提取单张并保存到相册。
  static Future<BatchTaskResult> _extractOne(LivePhotoEntry entry) async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir =
          '${tmp.path}/batch_extract_${DateTime.now().microsecondsSinceEpoch}';
      final videoPath = await VideoExtractor.extract(
        entry: entry,
        destDir: dir,
      );
      final stem = _stem(entry);
      final ok = await MediaScanService.saveVideoToGallery(
        srcPath: videoPath,
        name: '${stem}_video.mp4',
      );
      // 清理临时文件（单文件格式会拷贝出临时 mp4）
      try {
        final f = videoPath;
        if (f.startsWith(tmp.path)) {
          await File(f).delete();
        }
      } catch (_) {}
      return BatchTaskResult(ok: ok, error: ok ? null : '保存到相册失败，请检查权限');
    } catch (e) {
      return BatchTaskResult(ok: false, error: '$e');
    }
  }

  static String _stem(LivePhotoEntry entry) {
    final fileName = entry.media.fileName;
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }
}
