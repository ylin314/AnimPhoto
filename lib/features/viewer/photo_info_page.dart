/// 照片信息页：展示动态照片信息，提供格式转换、视频提取与分享入口。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/brand.dart';
import '../../core/motion_photo.dart';
import '../../platform/media_scan.dart';
import '../../services/share_service.dart';
import '../../utils/feature_guide_prefs.dart';
import '../../utils/video_extractor.dart';
import '../../widgets/feature_guide_overlay.dart';
import '../convert/convert_page.dart';
import '../../models/live_photo_entry.dart';

String buildMotionPhotoShareText(String url) =>
    '「瞬影 APP - 动态照片跨品牌播放与转换」，点击链接播放与转换动态照片：$url';

class PhotoInfoPage extends StatelessWidget {
  static final Set<String> _activeShares = {};
  const PhotoInfoPage({
    super.key,
    required this.entry,
    required this.deviceBrand,
    this.showFeatureGuide = false,
  });

  final LivePhotoEntry entry;
  final DeviceBrand deviceBrand;
  final bool showFeatureGuide;

  String get _stem {
    final fileName = entry.media.fileName;
    final dot = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  Future<void> _extractVideo(BuildContext context) async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir =
          '${tmp.path}/extract_${DateTime.now().millisecondsSinceEpoch}';
      final videoPath = await VideoExtractor.extract(
        entry: entry,
        destDir: dir,
      );
      final ok = await MediaScanService.saveVideoToGallery(
        srcPath: videoPath,
        name: '${_stem}_video.mp4',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(ok ? '视频已保存到相册「AnimPhoto」' : '保存视频失败，请检查权限')),
        );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('提取失败：$e')));
    }
  }

  Future<void> _share(BuildContext context) async {
    final shareKey = entry.media.path;
    // 防止分享弹层尚未出现时的连续点击同时启动多个上传。
    if (!_activeShares.add(shareKey)) return;
    final state = ValueNotifier<ShareSheetState>(
      const ShareSheetState.uploading(0),
    );
    // 先立即弹出分享框，避免上传期间无响应
    unawaited(_showShareSheet(context, state));
    try {
      final motionSize = await File(entry.media.path).length();
      final info = entry.info;
      final videoOffset = info?.videoOffset ?? motionSize;
      final videoEnd = info?.effectiveVideoEnd ?? motionSize;
      final url = await ShareService.upload(
        motionPath: entry.media.path,
        name: _stem,
        format: entry.formatLabel,
        videoOffset: videoOffset,
        videoEnd: videoEnd,
        onProgress: (p) => state.value = ShareSheetState.uploading(p),
      );
      await Clipboard.setData(
        ClipboardData(text: buildMotionPhotoShareText(url)),
      );
      if (!context.mounted) return;
      state.value = ShareSheetState.done(url);
    } catch (e) {
      if (!context.mounted) return;
      state.value = ShareSheetState.error('$e');
    } finally {
      _activeShares.remove(shareKey);
    }
  }

  /// 半透明底部弹层：上传中显示进度，成功后显示分享文案与复制按钮。
  Future<void> _showShareSheet(
    BuildContext context,
    ValueNotifier<ShareSheetState> state,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black.withValues(alpha: 0.55),
      barrierColor: Colors.black45,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => ValueListenableBuilder<ShareSheetState>(
        valueListenable: state,
        builder: (sheetContext, s, _) => SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.42,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(child: _shareBody(context, sheetContext, s, state)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _shareBody(
    BuildContext pageContext,
    BuildContext sheetContext,
    ShareSheetState s,
    ValueNotifier<ShareSheetState> state,
  ) {
    final url = s.url;
    if (s.error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 28),
          const SizedBox(height: 12),
          Text(
            '分享失败：${s.error}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: () => Navigator.of(sheetContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      );
    }
    if (url == null) {
      final progress = s.progress ?? 0;
      // 客户端字节进度封顶 99%：剩余等待服务器确认，避免“100% 但没成功”误导
      final shown = (progress * 100).clamp(0, 99).toStringAsFixed(0);
      final waiting = progress >= 0.999;
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            waiting ? '上传完成，等待服务器确认…' : '正在上传 $shown%',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
            backgroundColor: Colors.white24,
            color: Colors.white,
          ),
        ],
      );
    }
    final shareText = buildMotionPhotoShareText(url);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Colors.white, size: 20),
            SizedBox(width: 8),
            Text(
              '链接已复制到剪贴板',
              style: TextStyle(color: Colors.white, fontSize: 15),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '有效期 7 天',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            child: Text(
              shareText,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
        const Spacer(),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          icon: const Icon(Icons.copy),
          label: const Text('复制'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: shareText));
            if (!sheetContext.mounted) return;
            Navigator.of(sheetContext).pop();
            if (pageContext.mounted) {
              ScaffoldMessenger.of(
                pageContext,
              ).showSnackBar(const SnackBar(content: Text('链接已复制')));
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageGuideKey = GlobalKey();
    final info = entry.info;
    final rows = <(String, String)>[
      ('文件名', entry.media.fileName),
      ('动态照片格式', entry.formatLabel),
      ('相机', info == null ? '未知' : _camera(info)),
      ('时间', _dateText(info?.exifDateTimeOriginal, entry.media.modified)),
      ('文件大小', _sizeText(entry.media.size)),
      if (info?.videoOffset != null) ('视频偏移', '${info!.videoOffset}'),
      if (info?.videoBytes != null) ('视频大小', _sizeText(info!.videoBytes!)),
    ];

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(title: const Text('照片信息')),
          body: KeyedSubtree(
            key: pageGuideKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...rows.map(
                  (r) => ListTile(
                    dense: true,
                    title: Text(
                      r.$1,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    subtitle: Text(r.$2),
                  ),
                ),
                const SizedBox(height: 24),
                if (entry.isLive)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.swap_horiz),
                        label: const Text('转换格式'),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ConvertPage(
                                entry: entry,
                                deviceBrand: deviceBrand,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.movie_outlined),
                        label: const Text('提取视频'),
                        onPressed: () => _extractVideo(context),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.share_outlined),
                        label: const Text('分享'),
                        onPressed: () => _share(context),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        if (showFeatureGuide)
          FeatureGuideOverlay(
            targetKey: pageGuideKey,
            title: '更多动态照片工具',
            message: '这个页面可以进行格式转换、视频导出与分享。之后你可以随时从照片右上角的菜单按钮回到这里。',
            stepText: '点击屏幕完成提示',
            onBackgroundTap: () {
              markFeatureGuideCompleted(kPhotoMenuGuideCompletedKey);
            },
            dismissOnBackgroundTap: true,
          ),
      ],
    );
  }

  static String _camera(MotionPhotoInfo info) {
    final parts = <String>[
      // if (info.exifMake != null && info.exifMake!.isNotEmpty) info.exifMake!,
      if (info.exifModel != null && info.exifModel!.isNotEmpty) info.exifModel!,
    ];
    return parts.isEmpty ? '未知' : parts.join(' ');
  }

  /// 优先显示 EXIF 拍摄时间；无 EXIF 时回退到文件保存时间。
  /// [exif] 格式如 `2026:08:10 18:05:34`；[modifiedUnix] 为 Unix 秒。
  static String _dateText(String? exif, int modifiedUnix) {
    if (exif != null && exif.isNotEmpty) {
      final parsed = _parseExifDate(exif);
      if (parsed != null) return parsed;
    }
    // 回退到文件保存时间
    final dt = DateTime.fromMillisecondsSinceEpoch(modifiedUnix * 1000);
    final y = dt.year.toString();
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi';
  }

  /// 解析 EXIF DateTimeOriginal（`yyyy:MM:dd HH:mm:ss`）为 `yyyy-MM-dd HH:mm`。
  static String? _parseExifDate(String exif) {
    // 标准格式: 2026:08:10 18:05:34
    if (exif.length >= 19 && exif[4] == ':' && exif[7] == ':') {
      final year = exif.substring(0, 4);
      final month = exif.substring(5, 7);
      final day = exif.substring(8, 10);
      final hour = exif.substring(11, 13);
      final minute = exif.substring(14, 16);
      final y = int.tryParse(year);
      final mo = int.tryParse(month);
      final d = int.tryParse(day);
      if (y != null && mo != null && d != null && y > 1900) {
        return '$year-$month-$day $hour:$minute';
      }
    }
    return null;
  }

  static String _sizeText(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}

/// 分享弹层状态：上传中（进度）/ 成功（URL）/ 失败（错误）。
class ShareSheetState {
  const ShareSheetState.uploading(this.progress) : url = null, error = null;
  const ShareSheetState.done(this.url) : progress = 1, error = null;
  const ShareSheetState.error(this.error) : progress = null, url = null;

  final double? progress;
  final String? url;
  final String? error;
}
