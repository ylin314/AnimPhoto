/// OpenHarmony 旧格式单文件组装（见 AGENT.md 5.4）。
///
/// 参考：OpenHarmony `multimedia_media_library`
/// → `moving_photo_file_utils.cpp`（`GetVersionPositionTag` / `GetDurationTag` / `GetVideoInfoTag`），
/// 遵循其固定 20B 字段与 `AUTO_PLAY_DURATION_MS = 600` 逻辑。
library;

import 'dart:convert';
import 'dart:typed_data';

class OpenHarmonyAssembler {
  OpenHarmonyAssembler._();

  static const int tagLen = 20;
  static const int playInfoLen = 20;
  static const int versionTagLen = 20;
  static const int minStandardSize = 60; // 20+20+20
  static const int autoPlayDurationMs = 600;

  static String _pad(String s, int length) {
    if (s.length > length) {
      throw ArgumentError('OpenHarmony trailer field too long: "$s"');
    }
    return s.padRight(length, ' ');
  }

  /// 生成 60B 尾部标记：versionTag(20) + playInfo(20) + LIVE_+liveSize(20)。
  ///
  /// - [videoSize]：视频区域字节数（不含尾标）。
  /// - [coverMs]：封面位置（毫秒）。默认 0。
  /// - [frameIndex]：封面帧号。默认 0。第三方（非相机拍摄）用 `v3_f` 前缀。
  static Uint8List buildTrailer({
    required int videoSize,
    int coverMs = 0,
    int frameIndex = 0,
  }) {
    final versionTag = _pad('v3_f$frameIndex', versionTagLen);
    final playInfo = _pad(
      coverMs < autoPlayDurationMs
          ? '0:$coverMs'
          : '${coverMs - autoPlayDurationMs}:$coverMs',
      playInfoLen,
    );
    final liveSize = videoSize + versionTagLen;
    final liveTag = _pad('LIVE_$liveSize', tagLen);
    return Uint8List.fromList(ascii.encode(versionTag + playInfo + liveTag));
  }

  /// 解析末 20B 中的 liveSize（以 `LIVE_` 开头）；非旧格式返回 null。
  static int? parseLiveSize(Uint8List data) {
    if (data.length < tagLen) return null;
    final s = latin1.decode(data.sublist(data.length - tagLen)).trim();
    if (!s.startsWith('LIVE_')) return null;
    return int.tryParse(s.substring(5).trim());
  }

  /// 标准尾部（无 cinemagraph）时，由文件总大小与 liveSize 反推 imageSize。
  /// 即 `imageSize = totalSize - liveSize - 40`（playInfo 20 + LIVE_ 20）。
  static int reverseImageSize(int totalSize, int liveSize) =>
      totalSize - liveSize - 40;
}
