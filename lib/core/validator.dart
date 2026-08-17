/// 输出校验：按 OpenHarmony 旧格式反推公式校验产物（见 AGENT.md 5.4 / 8）。
library;

import 'dart:typed_data';

import 'byte_utils.dart';
import 'openharmony_assembler.dart';

class OutputValidator {
  OutputValidator._();

  /// 校验 [data] 是否为合法的 OpenHarmony 旧格式单文件。
  /// 返回错误列表；为空表示通过。
  static List<String> validate(Uint8List data) {
    final errors = <String>[];
    final liveSize = OpenHarmonyAssembler.parseLiveSize(data);
    if (liveSize == null) {
      return ['文件末尾 20B 不以 LIVE_ 开头，非 OpenHarmony 旧格式'];
    }
    final imageSize = OpenHarmonyAssembler.reverseImageSize(data.length, liveSize);
    if (imageSize < 0 || imageSize >= data.length) {
      errors.add('imageSize 越界: $imageSize (total=${data.length}, liveSize=$liveSize)');
      return errors;
    }
    if (!ByteUtils.isFtypAt(data, imageSize)) {
      errors.add('imageSize=$imageSize 处未找到 MP4 ftyp');
    }
    final expectedVideoSize = liveSize - 20;
    final actualVideoSize = data.length - imageSize - 60;
    if (expectedVideoSize != actualVideoSize) {
      errors.add('视频大小不一致: liveSize 推导=$expectedVideoSize, 实际=$actualVideoSize');
    }
    return errors;
  }
}
