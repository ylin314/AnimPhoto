/// 字节级工具：模式查找、JPEG EOI 定位、MP4 头校验。
library;

import 'dart:typed_data';

class ByteUtils {
  ByteUtils._();

  /// 在 [data] 的 [start, end) 范围内查找 [pattern]，返回首个命中下标；未找到返回 -1。
  static int findBytes(Uint8List data, List<int> pattern, {int start = 0, int? end}) {
    final e = end ?? data.length;
    if (pattern.isEmpty || start < 0 || e > data.length || e - start < pattern.length) {
      return -1;
    }
    outer:
    for (var i = start; i <= e - pattern.length; i++) {
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          continue outer;
        }
      }
      return i;
    }
    return -1;
  }

  static const _ff = 0xFF;
  static const _d9 = 0xD9;
  static const _d8 = 0xD8;
  static const _fillByte = 0x00;

  /// 从 [start] 起扫描 JPEG 熵编码段，返回 EOI（`FF D9`）之后的绝对偏移；
  /// 跳过 `FF 00` 字节填充与 `FF D8`。未找到返回 -1。
  static int findEoi(Uint8List data, int start) {
    if (start < 0 || start >= data.length - 1) return -1;
    var i = start;
    while (i < data.length - 1) {
      if (data[i] == _ff) {
        if (data[i + 1] == _fillByte) {
          i += 2;
          continue;
        }
        if (data[i + 1] == _d9) {
          return i + 2;
        }
        if (data[i + 1] == _d8) {
          i += 2;
          continue;
        }
        i += 2;
        continue;
      }
      i++;
    }
    return -1;
  }

  /// 校验 [offset] 处是否为 MP4 盒子且类型为 `ftyp`（`....ftyp` 结构）。
  static bool isFtypAt(Uint8List data, int offset) {
    if (offset < 0 || offset + 8 > data.length) {
      return false;
    }
    return data[offset + 4] == 0x66 && // f
        data[offset + 5] == 0x74 && // t
        data[offset + 6] == 0x79 && // y
        data[offset + 7] == 0x70; // p
  }
}

