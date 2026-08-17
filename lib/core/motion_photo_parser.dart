/// 动态照片单文件解析器。
///
/// 视频定位优先级（见 AGENT.md 5.2）：
///   1. XMP 容器 `Semantic=MotionPhoto` 的 `Item:Length`（反向偏移）
///   2. `GCamera:MicroVideoOffset`（旧标准，反向偏移）
///   3. OpenHarmony 旧格式 `LIVE_` 尾标反推
///   4. JPEG EOI 之后扫描 `ftyp`（兜底）
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'byte_utils.dart';
import 'motion_photo.dart';
import 'mp4_extractor.dart';
import 'xmp_parser.dart';

class MotionPhotoParser {
  MotionPhotoParser._();

  /// 解析单文件动态照片（全量读取）。 [path] 用于记录来源路径，数据以 [data] 为准。
  static MotionPhotoInfo parse(Uint8List data, {required String path}) {
    final size = data.length;
    final xmp = XmpParser.parse(data);
    final sos = _firstSosPayload(data);
    final eoi = sos < 0 ? -1 : ByteUtils.findEoi(data, sos);
    final trailer = _parseTrailer(data);

    final candidates = <(String, int)>[];
    for (final item in xmp.items) {
      if (!item.isVideo) continue;
      final len = int.tryParse(item.length ?? '');
      if (len != null && len > 0) {
        candidates.add(('XMP Item:Length', size - len));
      }
    }
    final microOff = xmp.tags['GCamera:MicroVideoOffset'];
    if (microOff != null) {
      final v = int.tryParse(microOff);
      if (v != null && v > 0) {
        candidates.add(('XMP GCamera:MicroVideoOffset', size - v));
      }
    }
    if (trailer != null && trailer.liveSize != null) {
      candidates.add((
        'OpenHarmony LIVE_ trailer',
        size - trailer.liveSize! - 40,
      ));
    }
    String? method;
    int? videoOffset;
    for (final (m, off) in candidates) {
      if (ByteUtils.isFtypAt(data, off)) {
        method = m;
        videoOffset = off;
        break;
      }
    }
    if (videoOffset != null) {
      return _info(path, size, data, eoi, videoOffset, method, xmp, trailer);
    }

    // 兜底：EOI 之后扫 ftyp
    if (eoi > 0) {
      final ftyp = ByteUtils.findBytes(data, const [
        0x66,
        0x74,
        0x79,
        0x70,
      ], start: eoi);
      if (ftyp > 0 && ByteUtils.isFtypAt(data, ftyp - 4)) {
        return _info(
          path,
          size,
          data,
          eoi,
          ftyp - 4,
          'ftyp scan',
          xmp,
          trailer,
        );
      }
    }
    return _info(path, size, data, eoi, null, null, xmp, trailer);
  }

  /// 快速检测（随机访问，不全量读文件）：用于相册扫描。
  ///
  /// 只读取：JPEG 段头与必要 APP1 元数据 + 文件尾 60B（LIVE_ 尾标）
  /// + 候选偏移处小段校验。
  /// 快速扫描只负责发现动态照片，不扫描 JPEG 压缩数据寻找 EOI；需要无损转换时
  /// 由 [analyzeForConversion] 按需补齐 JPEG 与 MP4 边界。
  static Future<MotionPhotoInfo> detectFile(String path) async {
    final file = File(path);
    final size = await file.length();
    final raf = await file.open();
    try {
      final metadata = await _readJpegMetadata(raf, size);
      final head = metadata.exifHead;
      final xmp = metadata.xmp;
      // 文件真正的尾部 60B（LIVE_ 尾标位于文件末尾）
      Uint8List tailBytes = Uint8List(0);
      if (size >= 60) {
        await raf.setPosition(size - 60);
        tailBytes = await raf.read(60);
      }
      final trailer = _parseTrailer(tailBytes);

      // 1) XMP Item:Length（按 Semantic=MotionPhoto，禁止硬编码下标）
      for (final item in xmp.items) {
        if (!item.isVideo) continue;
        final len = int.tryParse(item.length ?? '');
        if (len != null && len > 0 && len < size) {
          if (await _hasFtyp(raf, size - len)) {
            final offset = size - len;
            final videoEnd = await _scanMp4End(raf, offset, size);
            return _info(
              path,
              size,
              head,
              -1,
              offset,
              'XMP Item:Length',
              xmp,
              trailer,
              videoEnd: videoEnd,
            );
          }
        }
      }
      // 2) MicroVideoOffset
      final microOff = xmp.tags['GCamera:MicroVideoOffset'];
      if (microOff != null) {
        final v = int.tryParse(microOff);
        if (v != null && v > 0 && v < size) {
          if (await _hasFtyp(raf, size - v)) {
            final offset = size - v;
            final videoEnd = await _scanMp4End(raf, offset, size);
            return _info(
              path,
              size,
              head,
              -1,
              offset,
              'XMP GCamera:MicroVideoOffset',
              xmp,
              trailer,
              videoEnd: videoEnd,
            );
          }
        }
      }
      // 3) OpenHarmony LIVE_ 尾标
      if (trailer != null &&
          trailer.liveSize != null &&
          trailer.liveSize! < size) {
        final off = size - trailer.liveSize! - 40;
        if (off >= 0 && await _hasFtyp(raf, off)) {
          final videoEnd = await _scanMp4End(raf, off, size - 60);
          return _info(
            path,
            size,
            head,
            -1,
            off,
            'OpenHarmony LIVE_ trailer',
            xmp,
            trailer,
            videoEnd: videoEnd,
          );
        }
      }
      final exifMake = _readExifString(head, 0x010F);
      return MotionPhotoInfo(
        path: path,
        size: size,
        eoi: -1,
        format: _classify(xmp, trailer, exifMake),
        xmpTags: xmp.tags,
        containerItems: xmp.items,
        trailer: trailer,
        exifMake: exifMake,
        exifModel: _readExifString(head, 0x0110),
        exifDateTimeOriginal: _readExifString(head, 0x9003),
        exifSoftware: _readExifString(head, 0x0131),
        motionXmpSpans: xmp.segments
            .where((s) => s.isMotion)
            .map((s) => ByteSpan(s.start, s.end))
            .toList(),
        containerXmpSpans: xmp.segments
            .where((segment) => segment.isContainer)
            .map((segment) => ByteSpan(segment.start, segment.end))
            .toList(),
      );
    } finally {
      await raf.close();
    }
  }

  /// 沿 JPEG 段表随机跳转，只读取 APP1（EXIF/XMP）段。
  ///
  /// 大型 APP2/HDR 段只读取 4B 段头后直接跳过；最多检查到文件前 16 MiB，
  /// 实际 APP1 累计读取上限为 2 MiB。
  static Future<({Uint8List exifHead, XmpResult xmp})> _readJpegMetadata(
    RandomAccessFile raf,
    int fileSize,
  ) async {
    const maxStructurePosition = 16 * 1024 * 1024;
    const maxApp1Bytes = 2 * 1024 * 1024;
    final maxEnd = min(fileSize, maxStructurePosition);
    await raf.setPosition(0);
    final soi = await raf.read(2);
    if (soi.length != 2 || soi[0] != 0xFF || soi[1] != 0xD8) {
      return (exifHead: Uint8List.fromList(soi), xmp: XmpResult());
    }

    final app1Segments = <({int start, Uint8List bytes})>[];
    final exifBytes = BytesBuilder(copy: false)..add(soi);
    var app1Bytes = 0;
    var position = 2;
    while (position + 4 <= maxEnd) {
      await raf.setPosition(position);
      final header = await raf.read(4);
      if (header.length != 4 || header[0] != 0xFF) break;
      final marker = header[1];
      if (marker == 0xDA || marker == 0xD9) break;
      final length = (header[2] << 8) | header[3];
      final segmentSize = length + 2;
      if (length < 2 || position + segmentSize > fileSize) break;
      if (marker == 0xE1 && app1Bytes + segmentSize <= maxApp1Bytes) {
        await raf.setPosition(position);
        final bytes = await raf.read(segmentSize);
        if (bytes.length != segmentSize) break;
        final segment = Uint8List.fromList(bytes);
        app1Segments.add((start: position, bytes: segment));
        exifBytes.add(segment);
        app1Bytes += segmentSize;
      }
      position += segmentSize;
    }
    return (
      exifHead: exifBytes.takeBytes(),
      xmp: XmpParser.parseApp1Segments(app1Segments),
    );
  }

  /// 为无损格式转换按需补齐完整容器边界。
  ///
  /// 不把整个动态照片读入内存：先按 JPEG 段长度随机跳转到 SOS，再从 SOS
  /// 分块扫描到视频起点寻找 EOI；MP4 结束位置同样只读取顶层盒子头。
  static Future<MotionPhotoInfo> analyzeForConversion(
    MotionPhotoInfo quickInfo,
  ) async {
    final videoOffset = quickInfo.videoOffset;
    if (videoOffset == null) {
      throw StateError('源文件不是可识别的动态照片（缺少视频偏移）');
    }
    final file = File(quickInfo.path);
    final size = await file.length();
    if (videoOffset <= 0 || videoOffset > size) {
      throw StateError('动态照片的视频起点无效');
    }

    final raf = await file.open();
    try {
      final sos = await _findJpegSosPayload(raf, videoOffset);
      if (sos < 0) {
        throw StateError('未能定位 JPEG 图像数据，源文件可能已损坏');
      }
      final eoi = await _scanJpegEoi(raf, videoOffset, start: sos);
      if (eoi <= 1 || eoi > videoOffset) {
        throw StateError('未能定位 JPEG 主图结束位置，源文件可能已损坏');
      }
      final videoEnd =
          await _scanMp4End(raf, videoOffset, size) ??
          quickInfo.effectiveVideoEnd;
      if (videoEnd <= videoOffset || videoEnd > size) {
        throw StateError('动态照片的视频结束位置无效');
      }
      return quickInfo.copyWith(size: size, eoi: eoi, videoEnd: videoEnd);
    } finally {
      await raf.close();
    }
  }

  /// 按 JPEG 段长度随机跳转到 SOS，仅读取每段的 4B 头部。
  static Future<int> _findJpegSosPayload(
    RandomAccessFile raf,
    int maxEnd,
  ) async {
    if (maxEnd < 4) return -1;
    await raf.setPosition(0);
    final soi = await raf.read(2);
    if (soi.length != 2 || soi[0] != 0xFF || soi[1] != 0xD8) return -1;

    var position = 2;
    while (position + 4 <= maxEnd) {
      await raf.setPosition(position);
      final header = await raf.read(4);
      if (header.length != 4 || header[0] != 0xFF) return -1;
      final marker = header[1];
      if (marker == 0xD9) return -1;
      final length = (header[2] << 8) | header[3];
      if (length < 2 || position + 2 + length > maxEnd) return -1;
      if (marker == 0xDA) return position + 2 + length;
      position += 2 + length;
    }
    return -1;
  }

  static Future<int> _scanJpegEoi(
    RandomAccessFile raf,
    int maxEnd, {
    required int start,
  }) async {
    if (start < 0 || start >= maxEnd) return -1;
    const chunkSize = 1 << 20;
    var position = start;
    var previousWasFf = false;
    while (position < maxEnd) {
      await raf.setPosition(position);
      final bytes = await raf.read(min(chunkSize, maxEnd - position));
      if (bytes.isEmpty) break;
      for (var index = 0; index < bytes.length; index++) {
        final value = bytes[index];
        if (previousWasFf) {
          if (value == 0x00) {
            previousWasFf = false;
            continue;
          }
          if (value == 0xD9) return position + index + 1;
          previousWasFf = value == 0xFF;
        } else {
          previousWasFf = value == 0xFF;
        }
      }
      position += bytes.length;
    }
    return -1;
  }

  static int? _validMp4EndInBytes(Uint8List data, int offset) {
    if (offset < 0 || offset >= data.length) return null;
    final region = Uint8List.sublistView(data, offset);
    final relativeEnd = Mp4Extractor.validMp4End(region, 0);
    return relativeEnd > 0 ? offset + relativeEnd : null;
  }

  /// 仅读取 MP4 顶层盒子头，避免为了确定结束位置把整段视频读入内存。
  static Future<int?> _scanMp4End(
    RandomAccessFile raf,
    int start,
    int maxEnd,
  ) async {
    var position = start;
    while (position + 8 <= maxEnd) {
      await raf.setPosition(position);
      final header = await raf.read(position + 16 <= maxEnd ? 16 : 8);
      if (header.length < 8 || !_printableBoxType(header, 4)) break;
      var boxSize =
          (header[0] << 24) | (header[1] << 16) | (header[2] << 8) | header[3];
      var headerSize = 8;
      if (boxSize == 1) {
        if (header.length < 16) break;
        boxSize = 0;
        for (var i = 8; i < 16; i++) {
          boxSize = (boxSize << 8) | header[i];
        }
        headerSize = 16;
      } else if (boxSize == 0) {
        boxSize = maxEnd - position;
      }
      if (boxSize < headerSize || position + boxSize > maxEnd) break;
      position += boxSize;
    }
    return position > start ? position : null;
  }

  static bool _printableBoxType(Uint8List data, int offset) {
    if (offset + 4 > data.length) return false;
    for (var i = 0; i < 4; i++) {
      final value = data[offset + i];
      if (value < 0x20 || value > 0x7E) return false;
    }
    return true;
  }

  static Future<bool> _hasFtyp(RandomAccessFile raf, int offset) async {
    if (offset < 0 || offset + 8 > await raf.length()) return false;
    await raf.setPosition(offset + 4);
    final b = await raf.read(4);
    return b.length == 4 &&
        b[0] == 0x66 &&
        b[1] == 0x74 &&
        b[2] == 0x79 &&
        b[3] == 0x70;
  }

  static MotionPhotoInfo _info(
    String path,
    int size,
    Uint8List head,
    int eoi,
    int? videoOffset,
    String? method,
    XmpResult xmp,
    TrailerInfo? trailer, {
    int? videoEnd,
  }) {
    final exifMake = _readExifString(head, 0x010F);
    final parsedVideoEnd =
        videoEnd ??
        (videoOffset != null && head.length == size
            ? _validMp4EndInBytes(head, videoOffset)
            : null);
    return MotionPhotoInfo(
      path: path,
      size: size,
      eoi: eoi,
      videoOffset: videoOffset,
      videoOffsetMethod: method,
      format: _classify(xmp, trailer, exifMake),
      xmpTags: xmp.tags,
      containerItems: xmp.items,
      trailer: trailer,
      exifMake: exifMake,
      exifModel: _readExifString(head, 0x0110),
      exifDateTimeOriginal: _readExifString(head, 0x9003),
      exifSoftware: _readExifString(head, 0x0131),
      motionXmpSpans: xmp.segments
          .where((s) => s.isMotion)
          .map((s) => ByteSpan(s.start, s.end))
          .toList(),
      containerXmpSpans: xmp.segments
          .where((segment) => segment.isContainer)
          .map((segment) => ByteSpan(segment.start, segment.end))
          .toList(),
      videoEnd: parsedVideoEnd,
    );
  }

  /// 读取 JPEG 首个 SOS 段的载荷起点（熵编码起点），用于 EOI 扫描。
  static int _firstSosPayload(Uint8List data) {
    var pos = 2;
    while (pos + 4 <= data.length) {
      if (data[pos] != 0xFF) break;
      final marker = data[pos + 1];
      if (marker == 0xDA) {
        final len = (data[pos + 2] << 8) | data[pos + 3];
        return pos + 2 + len;
      }
      if (marker == 0xD9) return -1;
      final len = (data[pos + 2] << 8) | data[pos + 3];
      if (len < 2 || pos + 2 + len > data.length) break;
      pos += 2 + len;
    }
    return -1;
  }

  /// 解析 OpenHarmony 旧格式尾标：末 20B 以 `LIVE_` 开头，前 40B 为 versionTag/playInfo。
  static TrailerInfo? _parseTrailer(Uint8List data) {
    if (data.length < 60) return null;
    final tail = data.sublist(data.length - 60);
    final liveTagBytes = tail.sublist(40, 60);
    final liveStr = latin1.decode(liveTagBytes).trim();
    if (!liveStr.startsWith('LIVE_')) return null;
    final liveSize = int.tryParse(liveStr.substring(5).trim());
    final versionTag = latin1.decode(tail.sublist(0, 20)).trim();
    final playInfo = latin1.decode(tail.sublist(20, 40)).trim();
    final v = RegExp(r'^v([0-9]+)_f([0-9]+)').firstMatch(versionTag);
    return TrailerInfo(
      liveTag: liveStr,
      liveSize: liveSize,
      versionTag: versionTag.isEmpty ? null : versionTag,
      version: v == null ? null : int.tryParse(v.group(1)!),
      frameIndex: v == null ? null : int.tryParse(v.group(2)!),
      playInfo: playInfo.isEmpty ? null : playInfo,
    );
  }

  static LivePhotoFormat _classify(
    XmpResult xmp,
    TrailerInfo? trailer,
    String? exifMake,
  ) {
    final animPhotoTarget = xmp.tags['AnimPhoto:TargetFormat'];
    if (animPhotoTarget != null) {
      switch (animPhotoTarget) {
        case 'google':
          return LivePhotoFormat.googleMotionPhoto;
        case 'oplus':
          return LivePhotoFormat.oppo;
        case 'vivo':
          return LivePhotoFormat.vivo;
        case 'xiaomi':
          return LivePhotoFormat.xiaomi;
      }
    }
    if (trailer != null && trailer.liveTag != null) {
      return LivePhotoFormat.honorHuaweiOld;
    }
    if (xmp.tags.keys.any((key) => key.startsWith('OpCamera:'))) {
      return LivePhotoFormat.oppo;
    }
    if (xmp.tags.keys.any((key) => key.startsWith('VCamera:'))) {
      return LivePhotoFormat.vivo;
    }
    final hasGoogleMotion =
        xmp.tags.containsKey('GCamera:MotionPhoto') ||
        xmp.tags.containsKey('GCamera:MicroVideo');
    if (hasGoogleMotion) {
      final make = (exifMake ?? '').toLowerCase();
      final xiaomi =
          make.contains('xiaomi') ||
          make.contains('redmi') ||
          make.contains('poco') ||
          make.contains('blackshark') ||
          xmp.tags.keys.any((key) => key.startsWith('MiCamera:'));
      return xiaomi
          ? LivePhotoFormat.xiaomi
          : LivePhotoFormat.googleMotionPhoto;
    }
    return LivePhotoFormat.unknown;
  }

  /// 从 EXIF IFD0/ExifIFD 读取 ASCII 标签。
  static String? _readExifString(Uint8List data, int tag) {
    var pos = 2;
    while (pos + 4 <= data.length) {
      if (data[pos] != 0xFF) break;
      final marker = data[pos + 1];
      if (marker == 0xDA || marker == 0xD9) break;
      final len = (data[pos + 2] << 8) | data[pos + 3];
      if (len < 2 || pos + 2 + len > data.length) break;
      if (marker == 0xE1) {
        final seg = data.sublist(pos + 4, pos + 2 + len);
        if (seg.length > 6 &&
            seg[0] == 0x45 &&
            seg[1] == 0x78 &&
            seg[2] == 0x69 &&
            seg[3] == 0x66 &&
            seg[4] == 0x00 &&
            seg[5] == 0x00) {
          final tiff = seg.sublist(6);
          final little = tiff.length > 2 && tiff[0] == 0x49 && tiff[1] == 0x49;
          if (tiff.length < 8) return null;
          final ifdOff = little
              ? tiff[4] | (tiff[5] << 8) | (tiff[6] << 16) | (tiff[7] << 24)
              : (tiff[4] << 24) | (tiff[5] << 16) | (tiff[6] << 8) | tiff[7];
          if (ifdOff + 2 > tiff.length) return null;
          final count = little
              ? tiff[ifdOff] | (tiff[ifdOff + 1] << 8)
              : (tiff[ifdOff] << 8) | tiff[ifdOff + 1];

          String? readAscii(int offset) {
            if (offset < 0 || offset + 2 > tiff.length) return null;
            final n = little
                ? tiff[offset] | (tiff[offset + 1] << 8)
                : (tiff[offset] << 8) | tiff[offset + 1];
            for (var index = 0; index < n; index++) {
              final entry = offset + 2 + index * 12;
              if (entry + 12 > tiff.length) break;
              final currentTag = little
                  ? tiff[entry] | (tiff[entry + 1] << 8)
                  : (tiff[entry] << 8) | tiff[entry + 1];
              if (currentTag != tag) continue;
              final valueOffset = little
                  ? tiff[entry + 8] |
                        (tiff[entry + 9] << 8) |
                        (tiff[entry + 10] << 16) |
                        (tiff[entry + 11] << 24)
                  : (tiff[entry + 8] << 24) |
                        (tiff[entry + 9] << 16) |
                        (tiff[entry + 10] << 8) |
                        tiff[entry + 11];
              final end = valueOffset + 64 > tiff.length
                  ? tiff.length
                  : valueOffset + 64;
              final value = latin1.decode(tiff.sublist(valueOffset, end));
              final cut = value.indexOf('\x00');
              return cut >= 0 ? value.substring(0, cut) : value;
            }
            return null;
          }

          final direct = readAscii(ifdOff);
          if (direct != null || tag != 0x9003) return direct;

          // DateTimeOriginal 位于 ExifIFD，不在 IFD0。
          for (var i = 0; i < count; i++) {
            final e = ifdOff + 2 + i * 12;
            if (e + 12 > tiff.length) break;
            final t = little
                ? tiff[e] | (tiff[e + 1] << 8)
                : (tiff[e] << 8) | tiff[e + 1];
            if (t != 0x8769) continue;
            final exifIfdOffset = little
                ? tiff[e + 8] |
                      (tiff[e + 9] << 8) |
                      (tiff[e + 10] << 16) |
                      (tiff[e + 11] << 24)
                : (tiff[e + 8] << 24) |
                      (tiff[e + 9] << 16) |
                      (tiff[e + 10] << 8) |
                      tiff[e + 11];
            return readAscii(exifIfdOffset);
          }
          return null;
        }
      }
      pos += 2 + len;
    }
    return null;
  }
}
