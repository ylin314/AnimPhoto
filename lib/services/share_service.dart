/// 分享服务：上传动态照片到后端，返回 7 天有效链接。
///
/// 只上传单文件动态照片原文件，服务端按视频偏移直接流式播放内嵌视频，
/// 避免把同一段视频重复上传。
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/log.dart';
import 'server_config.dart';

class ShareService {
  ShareService._();

  /// 分享服务地址（部署后由反向代理路由到服务端口）。
  static const String baseUrl = ServerConfig.baseUrl;

  /// 同一文件正在执行的上传。用于合并连续点击产生的并发请求。
  static final Map<String, _ShareUploadTask> _inFlight = {};

  /// 已成功生成且仍在有效期内的分享链接。同一文件再次分享直接复用。
  static final Map<String, _CachedShare> _completed = {};
  static const String _cachePreferenceKey = 'share_link_cache_v1';
  static Future<void>? _cacheLoadFuture;

  /// 上传 [motionPath] 与元数据。
  ///
  static Future<String> upload({
    required String motionPath,
    required String name,
    required String format,
    required int videoOffset,
    required int videoEnd,
    void Function(double)? onProgress,
  }) async {
    final key = await _uploadKey(
      motionPath: motionPath,
      name: name,
      format: format,
      videoOffset: videoOffset,
      videoEnd: videoEnd,
    );
    await _ensureCacheLoaded();
    final now = DateTime.now();
    final beforePurge = _completed.length;
    _completed.removeWhere((_, value) => !value.expiresAt.isAfter(now));
    if (_completed.length != beforePurge) {
      await _saveCompletedCache();
    }

    // 命中本地缓存后，仍需向服务端探活：本地缓存仅知道「上传时」的过期时间，
    // 无法感知服务端文件是否已被手动删除或因过期清理（sweepExpired）消失。
    // 若不探活，会出现「服务端已无此文件、APP 却直接返回旧 URL」的过期链接 bug。
    final cached = _completed[key];
    if (cached != null && cached.expiresAt.isAfter(now)) {
      final alive = await _isShareAlive(cached.url);
      if (alive) {
        log('复用已有分享链接: name=$name expiresAt=${cached.expiresAt}');
        onProgress?.call(1);
        return cached.url;
      }
      // 服务端已无此分享：丢弃失效缓存，落到下方真实上传流程重新生成。
      log('缓存的分享在服务端已失效，重新上传: name=$name url=${cached.url}');
      _completed.remove(key);
      await _saveCompletedCache();
    }

    final running = _inFlight[key];
    if (running != null) {
      log('合并重复分享上传: name=$name');
      running.addProgressListener(onProgress);
      return (await running.future).url;
    }

    final task = _ShareUploadTask()..addProgressListener(onProgress);
    _inFlight[key] = task;
    task.future = _uploadOnce(
      motionPath: motionPath,
      name: name,
      format: format,
      videoOffset: videoOffset,
      videoEnd: videoEnd,
      onProgress: task.reportProgress,
    );

    try {
      final result = await task.future;
      _completed[key] = _CachedShare(
        url: result.url,
        expiresAt: result.expiresAt,
      );
      // 防止长时间运行后缓存无限增长；保留最近插入的 128 条即可。
      while (_completed.length > 128) {
        _completed.remove(_completed.keys.first);
      }
      await _saveCompletedCache();
      return result.url;
    } finally {
      if (identical(_inFlight[key], task)) {
        _inFlight.remove(key);
      }
    }
  }

  static Future<void> _ensureCacheLoaded() {
    return _cacheLoadFuture ??= _loadCompletedCache();
  }

  static Future<void> _loadCompletedCache() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_cachePreferenceKey);
      if (raw == null || raw.isEmpty) return;
      final records = jsonDecode(raw) as List<dynamic>;
      final now = DateTime.now();
      for (final value in records) {
        final record = value as Map<String, dynamic>;
        final expiresAt = DateTime.fromMillisecondsSinceEpoch(
          (record['expiresAt'] as num).toInt(),
        );
        if (expiresAt.isAfter(now)) {
          _completed[record['key'] as String] = _CachedShare(
            url: record['url'] as String,
            expiresAt: expiresAt,
          );
        }
      }
    } catch (e) {
      log('读取分享链接缓存失败: $e');
    }
  }

  static Future<void> _saveCompletedCache() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final records = _completed.entries
          .map(
            (entry) => <String, dynamic>{
              'key': entry.key,
              'url': entry.value.url,
              'expiresAt': entry.value.expiresAt.millisecondsSinceEpoch,
            },
          )
          .toList();
      await preferences.setString(_cachePreferenceKey, jsonEncode(records));
    } catch (e) {
      // 缓存失败只会导致下次重新上传，不能影响本次分享成功。
      log('保存分享链接缓存失败: $e');
    }
  }

  /// 清除内存与持久化的分享链接复用缓存。
  static Future<void> clearLocalCache() async {
    _completed.clear();
    _inFlight.clear();
    _cacheLoadFuture = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_cachePreferenceKey);
  }

  static Future<_ShareUploadResult> _uploadOnce({
    required String motionPath,
    required String name,
    required String format,
    required int videoOffset,
    required int videoEnd,
    required void Function(double) onProgress,
  }) async {
    log(
      '分享上传开始: name=$name format=$format '
      'videoOffset=$videoOffset videoEnd=$videoEnd',
    );
    final motionSize = await File(motionPath).length();
    log('待上传文件: motion=${motionSize}B 目标=$baseUrl');

    final uri = Uri.parse('$baseUrl/api/shares');
    final multipart = http.MultipartRequest('POST', uri)
      ..fields['name'] = name
      ..fields['format'] = format
      ..fields['videoOffset'] = '$videoOffset'
      ..fields['videoEnd'] = '$videoEnd'
      ..files.add(await http.MultipartFile.fromPath('motion', motionPath));

    final bodyStream = multipart.finalize();
    final total = multipart.contentLength;
    log('请求 Content-Length: $total');

    final client = HttpClient()..idleTimeout = const Duration(minutes: 2);
    try {
      final request = await client.postUrl(uri);
      multipart.headers.forEach((headerName, value) {
        if (headerName.toLowerCase() != HttpHeaders.contentLengthHeader) {
          request.headers.set(headerName, value);
        }
      });
      request.headers.removeAll(HttpHeaders.expectHeader);
      request.contentLength = total;

      var sent = 0;
      var lastLoggedPct = -1;
      final progressStream = bodyStream.map((chunk) {
        sent += chunk.length;
        if (total > 0) {
          onProgress((sent / total).clamp(0.0, 1.0));
        }
        final pct = total > 0 ? (sent * 100 / total).floor() : 0;
        if (pct >= lastLoggedPct + 10 || sent == total) {
          log('上传进度: $sent/$total ($pct%)');
          lastLoggedPct = pct;
        }
        return chunk;
      });

      // 一次性把流交给 HttpClient，由其合并写入；禁止逐块 await flush，
      // 否则每个 multipart 小块都会形成串行等待，移动网络下会极慢。
      await request.addStream(progressStream);
      log('请求体发送完毕，等待服务器响应…');

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      log('服务器响应: ${response.statusCode} body=$body');
      if (response.statusCode != HttpStatus.ok) {
        throw Exception('上传失败(${response.statusCode})：$body');
      }
      final json = jsonDecode(body) as Map<String, dynamic>;
      final id = json['id'] as String;
      final expiresAtMs = (json['expiresAt'] as num?)?.toInt();
      return _ShareUploadResult(
        url: '$baseUrl/s/$id',
        expiresAt: expiresAtMs == null
            ? DateTime.now().add(const Duration(days: 7))
            : DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
      );
    } catch (e) {
      log('上传异常: $e');
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// 从分享 URL 中解析出分享 id（路径最后一段）。
  static String? _shareIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      // 形如 https://host/s/<id>
      if (segments.length >= 2 && segments[segments.length - 2] == 's') {
        return segments.last;
      }
      // 兼容仅含路径段的情况：/s/<id>
      if (segments.length >= 2 && segments.first == 's') {
        return segments[1];
      }
    } catch (_) {
      // 解析失败按「不可识别」处理。
    }
    return null;
  }

  /// 探活：本地缓存的分享在服务端是否仍然存在且未过期。
  ///
  /// 服务端 GET /api/shares/:id 在分享存在且未过期时返回 200，
  /// 否则返回 410（expired / 已被清理）或 404。任一非 200 响应都视为
  /// 该缓存已失效，应丢弃并重新上传。
  static Future<bool> _isShareAlive(String url) {
    final id = _shareIdFromUrl(url);
    if (id == null || id.isEmpty) return Future.value(true);
    return _probeShare(id);
  }

  static Future<bool> _probeShare(String id) async {
    final uri = Uri.parse('$baseUrl/api/shares/$id');
    try {
      final client = HttpClient()..idleTimeout = const Duration(seconds: 10);
      try {
        final request = await client.headUrl(uri);
        // HEAD 更轻量；若服务端/反代不支持 HEAD，回退到 GET。
        final response = await request.close();
        await response.drain<void>();
        if (response.statusCode == HttpStatus.ok) return true;
        // 405 通常意味着 HEAD 被禁用，改用 GET 再探一次。
        if (response.statusCode == HttpStatus.methodNotAllowed) {
          return _probeShareGet(id);
        }
        // 410（过期/已清理）、404、5xx 等都视为已失效。
        return false;
      } finally {
        client.close(force: true);
      }
    } catch (e) {
      // 网络异常时不应阻塞分享：保守地认为缓存仍有效，
      // 让用户看到旧链接（随后真正打开时由页面侧提示过期），
      // 而不是在断网时强制重传大文件。
      log('探活分享失败，按缓存有效处理: id=$id $e');
      return true;
    }
  }

  static Future<bool> _probeShareGet(String id) async {
    final uri = Uri.parse('$baseUrl/api/shares/$id');
    final client = HttpClient()..idleTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      await response.drain<void>();
      return response.statusCode == HttpStatus.ok;
    } catch (e) {
      log('GET 探活分享失败: id=$id $e');
      return true;
    } finally {
      client.close(force: true);
    }
  }

  /// 文件路径不足以判断是否仍为同一内容，因此同时纳入大小与修改时间。
  static Future<String> _uploadKey({
    required String motionPath,
    required String name,
    required String format,
    required int videoOffset,
    required int videoEnd,
  }) async {
    final motion = await File(motionPath).stat();
    return jsonEncode([
      File(motionPath).absolute.path,
      motion.size,
      motion.modified.microsecondsSinceEpoch,
      name,
      format,
      videoOffset,
      videoEnd,
    ]);
  }
}

class _ShareUploadTask {
  late Future<_ShareUploadResult> future;
  final List<void Function(double)> _progressListeners = [];
  double _progress = 0;

  void addProgressListener(void Function(double)? listener) {
    if (listener == null) return;
    _progressListeners.add(listener);
    listener(_progress);
  }

  void reportProgress(double progress) {
    _progress = progress;
    for (final listener in List.of(_progressListeners)) {
      try {
        listener(progress);
      } catch (_) {
        // 单个界面监听器失效不应中断真实上传。
      }
    }
  }
}

class _ShareUploadResult {
  const _ShareUploadResult({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;
}

class _CachedShare {
  const _CachedShare({required this.url, required this.expiresAt});

  final String url;
  final DateTime expiresAt;
}
