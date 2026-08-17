/// MP4 有效区域提取：按盒子遍历，遇到非法盒子/非 ASCII 类型即停止，
/// 用于提取动态照片内嵌视频时跳过厂商私有尾随数据（如 OPPO mdat 后的私有块）。
library;

import 'dart:typed_data';

class Mp4Extractor {
  Mp4Extractor._();

  /// 从 [start]（应为 ftyp 盒子的 size 字段位置）起遍历盒子，
  /// 返回最后一个**有效**盒子之后的偏移。
  static int validMp4End(Uint8List data, int start) {
    var pos = start;
    while (pos + 8 <= data.length) {
      var size = (data[pos] << 24) |
          (data[pos + 1] << 16) |
          (data[pos + 2] << 8) |
          data[pos + 3];
      var header = 8;
      if (size == 1) {
        if (pos + 16 > data.length) break;
        size = _readUint64(data, pos + 8);
        header = 16;
      } else if (size == 0) {
        size = data.length - pos;
      }
      // 类型必须为可打印 ASCII，否则视为厂商私有尾随数据
      if (!_isPrintableType(data, pos + 4)) break;
      if (size < header || pos + size > data.length) break;
      pos += size;
    }
    return pos;
  }

  static int _readUint64(Uint8List d, int o) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = (v << 8) | d[o + i];
    }
    return v;
  }

  static bool _isPrintableType(Uint8List d, int o) {
    if (o + 4 > d.length) return false;
    for (var i = 0; i < 4; i++) {
      final b = d[o + i];
      if (b < 0x20 || b > 0x7E) return false;
    }
    return true;
  }
}
