/// Android 原生通道封装：设备品牌、媒体权限、相册扫描、缩略图、写入相册。
library;

import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('cn.ylin314/media');

class MediaItem {
  const MediaItem({
    required this.path,
    required this.size,
    this.id = 0,
    this.added = 0,
    this.modified = 0,
    this.bucketId = '',
    this.bucketName = '',
  });

  final String path;
  final int size;

  /// MediaStore `_ID`；0 表示未知（测试或非 Android 数据源）。
  final int id;

  /// 添加到系统媒体库的时间（Unix 秒）。
  final int added;

  /// 修改时间（Unix 秒）。
  final int modified;

  /// 相册 ID。
  final String bucketId;

  /// 相册名（MediaStore BUCKET_DISPLAY_NAME）。
  final String bucketName;

  String get fileName => path.split(RegExp(r'[/\\]')).last;
}

class MediaScanService {
  MediaScanService._();

  /// 读取设备厂商（Build.MANUFACTURER）。
  static Future<String> getDeviceBrand() async =>
      await _channel.invokeMethod<String>('getDeviceBrand') ?? 'unknown';

  /// 是否已授予媒体读取权限。
  static Future<bool> hasMediaPermission() async =>
      await _channel.invokeMethod<bool>('hasMediaPermission') ?? false;

  /// 请求媒体读取权限（异步返回，实际授权结果需稍后复查）。
  static Future<void> requestMediaPermissions() async {
    await _channel.invokeMethod<void>('requestMediaPermissions');
  }

  /// 扫描系统相册中的图片（路径 + 大小 + 修改时间 + 相册信息，按日期倒序）。
  static Future<List<MediaItem>> scanImages() async {
    final raw =
        await _channel.invokeMethod<List<dynamic>>('scanImages') ?? const [];
    return raw
        .map((e) => (e as Map<dynamic, dynamic>))
        .map(
          (m) => MediaItem(
            path: m['path'] as String,
            size: (m['size'] as num).toInt(),
            id: (m['id'] as num?)?.toInt() ?? 0,
            added: (m['added'] as num?)?.toInt() ?? 0,
            modified: (m['modified'] as num?)?.toInt() ?? 0,
            bucketId: (m['bucketId'] as String?) ?? '',
            bucketName: (m['bucketName'] as String?) ?? '',
          ),
        )
        .toList();
  }

  /// 生成缩略图 JPEG 字节（最长边约 [max] 像素）。
  static Future<Uint8List?> getThumbnail(String path, {int max = 400}) async {
    final raw = await _channel.invokeMethod<Uint8List>('getThumbnail', {
      'path': path,
      'max': max,
    });
    return raw;
  }

  /// 删除系统媒体库中的图片（根据扫描时记录的媒体 ID）。
  ///
  /// Android 10 及以下需要 WRITE_EXTERNAL_STORAGE；Android 11 起由
  /// 批量删除系统相册中的图片，返回系统确认后成功删除的数量。
  static Future<int> deleteImages(List<int> ids) async =>
      await _channel.invokeMethod<int>('deleteImages', {'ids': ids}) ?? 0;

  /// 将 [srcPath] 的 JPEG 写入系统相册 Pictures/AnimPhoto。
  static Future<bool> saveJpegToGallery({
    required String srcPath,
    required String name,
  }) async =>
      await _channel.invokeMethod<bool>('saveJpegToGallery', {
        'path': srcPath,
        'name': name,
      }) ??
      false;

  /// 将 [srcPath] 的 MP4 写入系统相册 Movies/AnimPhoto。
  static Future<bool> saveVideoToGallery({
    required String srcPath,
    required String name,
  }) async =>
      await _channel.invokeMethod<bool>('saveVideoToGallery', {
        'path': srcPath,
        'name': name,
      }) ??
      false;
}
