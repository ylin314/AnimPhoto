/// 播放页：提取单文件动态照片的内嵌视频后播放。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../utils/file_io.dart';
import '../../models/live_photo_entry.dart';

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.entry});

  final LivePhotoEntry entry;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _controller;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    try {
      final info = widget.entry.info!;
      final tmpDir = await getTemporaryDirectory();
      final videoPath =
          '${tmpDir.path}/${info.path.split(RegExp(r'[/\\]')).last}_video.mp4';
      // 提取视频区域（分块复制，保留厂商私有尾随数据）
      await FileIo.copyRange(
        info.path,
        videoPath,
        info.videoOffset!,
        info.effectiveVideoEnd,
      );
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller.play();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('播放')),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
            : _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48),
                    const SizedBox(height: 12),
                    Text('播放失败：$_error', textAlign: TextAlign.center),
                  ],
                ),
              )
            : _controller == null
            ? const Text('无内容')
            : AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
      ),
      bottomNavigationBar: _controller != null && _error == null
          ? VideoProgressIndicator(
              _controller!,
              allowScrubbing: true,
              padding: const EdgeInsets.all(16),
            )
          : null,
    );
  }
}
