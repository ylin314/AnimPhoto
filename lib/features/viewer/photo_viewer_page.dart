/// 照片查看页：左右滑动切换相册内前后照片。
/// 每张照片：先展示静态图，长按/点按钮在当前页播放动态照片，松手/播完自动切回静态图。
/// 滑动切换时会自动停止当前播放；未放大时可左右滑动翻页，放大后可平移查看细节。
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/brand.dart';
import '../../utils/feature_guide_prefs.dart';
import '../../utils/file_io.dart';
import '../../utils/log.dart';
import '../../widgets/feature_guide_overlay.dart';
import '../../models/live_photo_entry.dart';
import '../scan/thumbnail_cache.dart';
import 'photo_info_page.dart';

class PhotoViewerPage extends StatefulWidget {
  const PhotoViewerPage({
    super.key,
    required this.entries,
    required this.initialIndex,
    required this.deviceBrand,
  });

  /// 当前相册的全部动态照片。
  final List<LivePhotoEntry> entries;

  /// 初始展示的照片下标。
  final int initialIndex;

  final DeviceBrand deviceBrand;

  @override
  State<PhotoViewerPage> createState() => _PhotoViewerPageState();
}

class _PhotoViewerPageState extends State<PhotoViewerPage> {
  /// 已提取的视频路径缓存（按源图片路径），避免每次播放重复提取。
  static final Map<String, String> _videoPathCache = {};

  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _current = widget.initialIndex;
  final GlobalKey _playGuideKey = GlobalKey();
  final GlobalKey _menuGuideKey = GlobalKey();

  VideoPlayerController? _controller;
  bool _playing = false;
  bool _loadingVideo = false;
  String? _error;
  bool _showMenuGuide = false;

  LivePhotoEntry get _entry => widget.entries[_current];

  @override
  void initState() {
    super.initState();
    _loadMenuGuide();
  }

  Future<void> _loadMenuGuide() async {
    final completed = await isFeatureGuideCompleted(
      kPhotoMenuGuideCompletedKey,
    );
    if (!mounted || completed) return;
    setState(() => _showMenuGuide = true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<String> _videoPath(LivePhotoEntry e) async {
    final cached = _videoPathCache[e.media.path];
    if (cached != null) return cached;
    final info = e.info!;
    final tmpDir = await getTemporaryDirectory();
    final videoPath =
        '${tmpDir.path}/${e.media.path.split(RegExp(r'[/\\]')).last}_video.mp4';
    await FileIo.copyRange(
      info.path,
      videoPath,
      info.videoOffset!,
      info.effectiveVideoEnd,
    );
    _videoPathCache[e.media.path] = videoPath;
    return videoPath;
  }

  Future<void> _play() async {
    final e = _entry;
    if (_playing || _loadingVideo || !e.isLive) return;
    log('播放: ${e.media.fileName}');
    setState(() {
      _loadingVideo = true;
      _error = null;
    });
    try {
      final c = VideoPlayerController.file(File(await _videoPath(e)));
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(() {
        // 播放结束自动切回静态照片
        if (_playing &&
            c.value.isInitialized &&
            c.value.duration > Duration.zero &&
            c.value.position >= c.value.duration) {
          _stop();
        }
      });
      setState(() {
        _controller = c;
        _playing = true;
        _loadingVideo = false;
      });
      await c.play();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingVideo = false;
          _error = '播放失败：$e';
        });
      }
    }
  }

  Future<void> _stop() async {
    final c = _controller;
    if (mounted) {
      setState(() {
        _controller = null;
        _playing = false;
        _loadingVideo = false;
      });
    }
    await c?.dispose();
  }

  void _togglePlay() {
    if (_playing) {
      _stop();
    } else {
      _play();
    }
  }

  void _onPageChanged(int index) {
    _stop();
    if (mounted) setState(() => _current = index);
  }

  Future<void> _openInfo({bool continueGuide = false}) async {
    log('打开照片信息: ${_entry.media.fileName}');
    if (continueGuide) {
      setState(() => _showMenuGuide = false);
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoInfoPage(
          entry: _entry,
          deviceBrand: widget.deviceBrand,
          showFeatureGuide: continueGuide,
        ),
      ),
    );
    if (!continueGuide || !mounted) return;
    final completed = await isFeatureGuideCompleted(
      kPhotoMenuGuideCompletedKey,
    );
    if (mounted && !completed) {
      setState(() => _showMenuGuide = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
              '${_current + 1} / ${widget.entries.length}',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            centerTitle: true,
            actions: [
              if (_entry.isLive)
                IconButton(
                  key: _playGuideKey,
                  tooltip: _playing ? '停止' : '播放动态照片',
                  icon: Icon(_playing ? Icons.stop : Icons.play_circle_outline),
                  onPressed: _togglePlay,
                ),
              IconButton(
                key: _menuGuideKey,
                tooltip: '信息',
                icon: const Icon(Icons.more_vert),
                onPressed: () => _openInfo(),
              ),
            ],
          ),
          body: Stack(
            children: [
              PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: widget.entries.length,
                itemBuilder: (context, i) => _PhotoPage(
                  entry: widget.entries[i],
                  isCurrent: i == _current,
                  playing: _playing && i == _current,
                  controller: i == _current ? _controller : null,
                  error: i == _current ? _error : null,
                  onPlay: _play,
                  onStop: _stop,
                ),
              ),
              if (_loadingVideo)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black45,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
        if (_showMenuGuide)
          FeatureGuideOverlay(
            targetKey: _menuGuideKey,
            title: '播放与更多功能',
            message:
                '左边的按钮可以播放动态照片，右边的“三个点”是功能菜单。'
                '点击菜单按钮，可以进行格式转换、视频导出与分享。',
            stepText: '请点击右上角菜单按钮继续',
            onTargetAction: () => _openInfo(continueGuide: true),
            accentColor: Colors.white,
          ),
      ],
    );
  }
}

class _PhotoPage extends StatefulWidget {
  const _PhotoPage({
    required this.entry,
    required this.isCurrent,
    required this.playing,
    required this.controller,
    required this.error,
    required this.onPlay,
    required this.onStop,
  });

  final LivePhotoEntry entry;
  final bool isCurrent;
  final bool playing;
  final VideoPlayerController? controller;
  final String? error;
  final Future<void> Function() onPlay;
  final Future<void> Function() onStop;

  @override
  State<_PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<_PhotoPage> {
  /// 是否已放大：放大后可平移查看细节；未放大时手势交给 PageView 用于翻页。
  bool _zoomed = false;

  @override
  Widget build(BuildContext context) {
    if (widget.playing && widget.controller != null) {
      return GestureDetector(
        onTap: widget.onStop,
        child: Center(
          child: AspectRatio(
            aspectRatio: widget.controller!.value.aspectRatio,
            child: VideoPlayer(widget.controller!),
          ),
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: FutureBuilder<Uint8List?>(
            future: ThumbnailCache.get(widget.entry.media.path, max: 1600),
            builder: (context, snap) {
              final bytes = snap.data;
              if (bytes == null) {
                return Center(
                  child: widget.error != null
                      ? Text(
                          widget.error!,
                          style: const TextStyle(color: Colors.white70),
                          textAlign: TextAlign.center,
                        )
                      : const CircularProgressIndicator(),
                );
              }
              return GestureDetector(
                onLongPressStart: widget.entry.isLive
                    ? (_) => widget.onPlay()
                    : null,
                onLongPressEnd: widget.entry.isLive
                    ? (_) => widget.onStop()
                    : null,
                onLongPressCancel: widget.entry.isLive ? widget.onStop : null,
                child: InteractiveViewer(
                  maxScale: 4,
                  // 未放大时禁用平移，保证 PageView 左右滑动切换照片
                  panEnabled: _zoomed,
                  onInteractionUpdate: (details) {
                    final zoomed = details.scale > 1.02;
                    if (zoomed != _zoomed) {
                      setState(() => _zoomed = zoomed);
                    }
                  },
                  // 子级铺满全屏：缩放时画布占满屏幕，不再出现黑边
                  child: SizedBox.expand(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (widget.isCurrent &&
            !widget.playing &&
            widget.entry.isLive &&
            widget.error == null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '长按播放 · 左右滑动切换',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
