/// 缩略图内存缓存：单飞（同路径去重）+ 并发上限，避免首次进相册时并发解码卡顿。
library;

import 'dart:async';
import 'dart:typed_data';

import '../../platform/media_scan.dart';

class ThumbnailCache {
  ThumbnailCache._();

  static final Map<String, Uint8List> _cache = {};
  static final Map<String, Future<Uint8List?>> _inflight = {};
  static final List<_Job> _queue = [];
  static int _active = 0;

  static const int _maxConcurrent = 5;
  static const int _cap = 400;

  static String _key(String path, int max) => '$path@$max';

  static Future<Uint8List?> get(String path, {int max = 400}) {
    final key = _key(path, max);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    final inflight = _inflight[key];
    if (inflight != null) return inflight;

    final job = _Job(path, max, key);
    _queue.add(job);
    _pump();
    final future = job.future;
    _inflight[key] = future;
    future.whenComplete(() => _inflight.remove(key));
    return future;
  }

  static void _pump() {
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _active++;
      job.run().whenComplete(() {
        _active--;
        _pump();
      });
    }
  }

  static void clear() {
    _cache.clear();
    _queue.clear();
  }
}

class _Job {
  _Job(this.path, this.max, this.key);

  final String path;
  final int max;
  final String key;
  final Completer<Uint8List?> _completer = Completer<Uint8List?>();

  Future<Uint8List?> get future => _completer.future;

  Future<void> run() async {
    Uint8List? bytes;
    try {
      bytes = await MediaScanService.getThumbnail(path, max: max);
      if (bytes != null) {
        if (ThumbnailCache._cache.length >= ThumbnailCache._cap) {
          ThumbnailCache._cache.clear();
        }
        ThumbnailCache._cache[key] = bytes;
      }
    } catch (_) {
      bytes = null;
    }
    if (!_completer.isCompleted) _completer.complete(bytes);
  }
}
