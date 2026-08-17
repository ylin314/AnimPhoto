/// 动态照片列表中的领域模型与本机支持能力判断。
library;

import '../core/brand.dart';
import '../core/motion_photo.dart';
import '../platform/media_scan.dart';

class LivePhotoEntry {
  const LivePhotoEntry({required this.media, this.info});

  final MediaItem media;

  /// 单文件动态照片解析结果；null 表示非单文件格式。
  final MotionPhotoInfo? info;

  bool get isSingleFile => info?.isLivePhoto ?? false;
  bool get isLive => isSingleFile;

  String get formatLabel {
    if (isSingleFile) {
      switch (info!.format) {
        case LivePhotoFormat.honorHuaweiOld:
          return '华为/荣耀';
        case LivePhotoFormat.oppo:
          return 'OPPO';
        case LivePhotoFormat.vivo:
          return 'vivo';
        case LivePhotoFormat.xiaomi:
          return '小米';
        case LivePhotoFormat.googleMotionPhoto:
          return 'Google';
        case LivePhotoFormat.unknown:
          return '未知';
      }
    }
    return '普通照片';
  }
}

/// 判断动态照片格式是否可被本机系统相册原生播放。
bool isEntrySupportedOnDevice(LivePhotoEntry entry, DeviceBrand brand) {
  if (entry.isSingleFile) {
    switch (entry.info!.format) {
      case LivePhotoFormat.oppo:
        return brand == DeviceBrand.oppo;
      case LivePhotoFormat.vivo:
        return brand == DeviceBrand.vivo;
      case LivePhotoFormat.xiaomi:
        return brand == DeviceBrand.xiaomi;
      case LivePhotoFormat.honorHuaweiOld:
        return brand == DeviceBrand.honor || brand == DeviceBrand.huawei;
      case LivePhotoFormat.googleMotionPhoto:
        return brand == DeviceBrand.other || brand == DeviceBrand.xiaomi;
      case LivePhotoFormat.unknown:
        return false;
    }
  }
  return false;
}
