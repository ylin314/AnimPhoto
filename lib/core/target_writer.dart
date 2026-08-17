/// 目标格式组装：以“主 JPEG + 辅助图片 + 纯 MP4”为统一中间结构。
///
/// 转换时会剥离源动态 XMP和厂商边界数据，保留 Ultra HDR GainMap，
/// 再按目标格式写入新的 XMP 或 OpenHarmony 尾标。全程不重编码图片和视频。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'motion_photo.dart';
import 'openharmony_assembler.dart';
import 'vendor_metadata.dart';

class TargetWriter {
  TargetWriter._();

  static const int _chunkSize = 1 << 20;
  static const String _xapPrefix = 'http://ns.adobe.com/xap/1.0/\x00';

  /// 生成目标动态照片 XMP APP1。
  static Uint8List buildTargetXmpApp1(
    TargetFormat target,
    int videoSize, {
    int timestampUs = -1,
    List<ContainerItem> auxiliaryItems = const [],
    bool hdrGainMap = false,
  }) {
    final xml = _buildXmp(
      target: target,
      videoSize: videoSize,
      timestampUs: timestampUs,
      auxiliaryItems: auxiliaryItems,
      hdrGainMap: hdrGainMap,
    );
    return _buildApp1(xml);
  }

  /// 生成只描述主图和辅助图片的 XMP，用于 OpenHarmony 旧格式。
  static Uint8List? buildImageXmpApp1({
    List<ContainerItem> auxiliaryItems = const [],
    bool hdrGainMap = false,
  }) {
    if (auxiliaryItems.isEmpty && !hdrGainMap) return null;
    return _buildApp1(
      _buildXmp(auxiliaryItems: auxiliaryItems, hdrGainMap: hdrGainMap),
    );
  }

  static Uint8List _buildApp1(String xml) {
    final payload = Uint8List.fromList(utf8.encode('$_xapPrefix$xml'));
    if (payload.length + 2 > 0xFFFF) {
      throw StateError('目标 XMP 超过 JPEG APP1 长度限制');
    }
    final segment = Uint8List(payload.length + 4);
    segment[0] = 0xFF;
    segment[1] = 0xE1;
    segment[2] = ((payload.length + 2) >> 8) & 0xFF;
    segment[3] = (payload.length + 2) & 0xFF;
    segment.setRange(4, segment.length, payload);
    return segment;
  }

  static String _buildXmp({
    TargetFormat? target,
    int? videoSize,
    int timestampUs = -1,
    required List<ContainerItem> auxiliaryItems,
    required bool hdrGainMap,
  }) {
    final hasMotion = target != null && videoSize != null;
    final timestamp = timestampUs >= 0 ? timestampUs : -1;
    final animPhotoTarget = _animPhotoTargetValue(target);
    final buffer = StringBuffer()
      ..writeln('<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="AnimPhoto">')
      ..writeln(
        '  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">',
      )
      ..writeln('    <rdf:Description rdf:about=""')
      ..writeln(
        '        xmlns:Container="http://ns.google.com/photos/1.0/container/"',
      )
      ..writeln(
        '        xmlns:Item="http://ns.google.com/photos/1.0/container/item/"',
      );
    if (hdrGainMap) {
      buffer.writeln(
        '        xmlns:hdrgm="http://ns.adobe.com/hdr-gain-map/1.0/"',
      );
    }
    if (hasMotion) {
      buffer.writeln(
        '        xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"',
      );
    }
    if (target == TargetFormat.oppo) {
      buffer.writeln(
        '        xmlns:OpCamera="http://ns.oplus.com/photos/1.0/camera/"',
      );
    }
    if (target == TargetFormat.vivo) {
      // 与 vivo X300 Pro 原生样例一致，XMP 与文件尾 UUID 扩展配套写入。
      buffer.writeln(
        '        xmlns:VCamera="http://ns.vivo.com/photos/1.0/camera/"',
      );
    }
    if (animPhotoTarget != null) {
      buffer.writeln('        xmlns:AnimPhoto="http://ns.animphoto.app/1.0/"');
    }
    if (hdrGainMap) {
      buffer.writeln('        hdrgm:Version="1.0"');
    }
    if (target == TargetFormat.oppo) {
      buffer
        ..writeln('        OpCamera:MotionPhotoOwner="oplus"')
        ..writeln('        OpCamera:OLivePhotoVersion="2"')
        // 无厂商扩展时，VideoLength 与纯 MP4 长度相同。
        ..writeln('        OpCamera:VideoLength="$videoSize"')
        ..writeln(
          '        OpCamera:MotionPhotoPrimaryPresentationTimestampUs="$timestamp"',
        );
    }
    if (target == TargetFormat.vivo) {
      // 与 vivo X300 Pro 原生样例一致，XMP 与文件尾 UUID 扩展配套写入。
      buffer
        ..writeln('        VCamera:VMotionPhotoVersion="1"')
        ..writeln('        VCamera:VMotionPhotoSource="1"')
        ..writeln('        VCamera:VMediaKitVersion="1.0.0.5"');
    }
    if (animPhotoTarget != null) {
      buffer.writeln('        AnimPhoto:TargetFormat="$animPhotoTarget"');
    }
    if (hasMotion) {
      buffer;
      // OPPO/vivo 原生样例只写新版 MotionPhoto 字段。旧 MicroVideo 字段
      // 仅保留给 Google/小米目标，避免严格厂商解析器把两套描述判为冲突。
      if (target == TargetFormat.google || target == TargetFormat.xiaomi) {
        buffer
          ..writeln('        GCamera:MicroVideo="1"')
          ..writeln('        GCamera:MicroVideoVersion="1"')
          ..writeln('        GCamera:MicroVideoOffset="$videoSize"')
          ..writeln(
            '        GCamera:MicroVideoPresentationTimestampUs="$timestamp"',
          );
      }
      buffer
        ..writeln('        GCamera:MotionPhoto="1"')
        ..writeln('        GCamera:MotionPhotoVersion="1"')
        ..writeln(
          '        GCamera:MotionPhotoPresentationTimestampUs="$timestamp">',
        );
    } else {
      buffer.writeln('        >');
    }
    buffer
      ..writeln('      <Container:Directory>')
      ..writeln('        <rdf:Seq>')
      ..writeln('          <rdf:li rdf:parseType="Resource">')
      ..writeln(
        target == TargetFormat.oppo
            ? '            <Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary" Item:Length="0" Item:Padding="0"/>'
            : '            <Container:Item Item:Mime="image/jpeg" Item:Semantic="Primary"/>',
      )
      ..writeln('          </rdf:li>');
    for (final item in auxiliaryItems) {
      buffer
        ..writeln('          <rdf:li rdf:parseType="Resource">')
        ..writeln('            <Container:Item${_itemAttributes(item)}/>')
        ..writeln('          </rdf:li>');
    }
    if (hasMotion) {
      buffer
        ..writeln('          <rdf:li rdf:parseType="Resource">')
        ..writeln(
          '            <Container:Item Item:Mime="video/mp4" '
          'Item:Semantic="MotionPhoto" Item:Length="$videoSize"'
          '${target == TargetFormat.vivo || target == TargetFormat.xiaomi ? ' Item:Padding="0"' : ''}/>',
        )
        ..writeln('          </rdf:li>');
    }
    buffer
      ..writeln('        </rdf:Seq>')
      ..writeln('      </Container:Directory>')
      ..writeln('    </rdf:Description>')
      ..writeln('  </rdf:RDF>')
      ..write('</x:xmpmeta>');
    return buffer.toString();
  }

  static String? _animPhotoTargetValue(TargetFormat? target) {
    switch (target) {
      case TargetFormat.google:
        return 'google';
      case TargetFormat.oppo:
        return 'oplus';
      case TargetFormat.vivo:
        return 'vivo';
      case TargetFormat.xiaomi:
        return 'xiaomi';
      case TargetFormat.honorHuawei:
      case null:
        return null;
    }
  }

  static String _itemAttributes(ContainerItem item) {
    final values = <String, String>{
      if (item.mime != null) 'Mime': item.mime!,
      if (item.semantic != null) 'Semantic': item.semantic!,
      if (item.parsedLength != null) 'Length': '${item.parsedLength}',
      if (item.padding != null) 'Padding': item.padding!,
    };
    return values.entries
        .map((entry) => ' Item:${entry.key}="${_xmlEscape(entry.value)}"')
        .join();
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  /// 生成单文件目标格式。
  static Future<void> convertToFile({
    required String srcPath,
    required String outPath,
    required MotionPhotoInfo info,
    required TargetFormat target,
    int? coverMs,
    int? frameIndex,
  }) async {
    final layout = _layout(info);
    final timestampUs = info.presentationTimestampUs;
    final src = await File(srcPath).open();
    final outFile = File(outPath);
    await outFile.parent.create(recursive: true);
    final dst = await outFile.open(mode: FileMode.write);
    try {
      final header = await _readJpegHeader(src, layout.primaryEnd);
      final canonicalVideoEnd = await _canonicalVideoEnd(src, layout);
      final canonicalVideoSize = canonicalVideoEnd - layout.videoStart;
      final vivoExtensions = target == TargetFormat.vivo
          ? VendorMetadata.buildVivoVideoExtensions(
              width: header.width ?? 4096,
              height: header.height ?? 3072,
              model: 'vivo',
            )
          : Uint8List(0);
      final outputVideoSize = canonicalVideoSize + vivoExtensions.length;

      Uint8List? oppoExif;
      if (target == TargetFormat.oppo) {
        Uint8List? original;
        final exif = header.exifSpan;
        if (exif != null) {
          original = await _readRange(src, exif.start, exif.end);
        }
        oppoExif = VendorMetadata.buildOppoExifApp1(original);
      }

      if (target == TargetFormat.honorHuawei) {
        await _writeCanonicalImage(
          src: src,
          dst: dst,
          info: info,
          layout: layout,
          header: header,
          app1: buildImageXmpApp1(
            auxiliaryItems: layout.auxiliaryItems,
            hdrGainMap: layout.hdrGainMap,
          ),
        );
      } else {
        await _writeCanonicalImage(
          src: src,
          dst: dst,
          info: info,
          layout: layout,
          header: header,
          app1: buildTargetXmpApp1(
            target,
            outputVideoSize,
            timestampUs: timestampUs,
            auxiliaryItems: layout.auxiliaryItems,
            hdrGainMap: layout.hdrGainMap,
          ),
          exifReplacement: oppoExif,
        );
      }
      if (target == TargetFormat.vivo) {
        // vivo 原生文件在 MP4 前还有一个不计入 Item:Length 的边界标记。
        await dst.writeFrom(VendorMetadata.vivoBoundary);
      }
      await _copyRange(src, dst, layout.videoStart, canonicalVideoEnd);
      if (vivoExtensions.isNotEmpty) await dst.writeFrom(vivoExtensions);
      if (target == TargetFormat.honorHuawei) {
        final resolvedCoverMs =
            coverMs ?? (timestampUs >= 0 ? (timestampUs / 1000).round() : 0);
        final trailer = OpenHarmonyAssembler.buildTrailer(
          videoSize: canonicalVideoSize,
          coverMs: resolvedCoverMs,
          frameIndex: frameIndex ?? info.trailer?.frameIndex ?? 0,
        );
        await dst.writeFrom(trailer);
      }
    } finally {
      await dst.close();
      await src.close();
    }
  }

  static _CanonicalLayout _layout(MotionPhotoInfo info) {
    final videoStart = info.videoOffset;
    if (videoStart == null) {
      throw StateError('源文件不是可识别的动态照片（缺少视频偏移）');
    }
    if (info.eoi <= 1 || info.eoi > videoStart) {
      throw StateError('源文件主图不是可无损转换的 JPEG');
    }
    final videoEnd = info.effectiveVideoEnd;
    if (videoEnd <= videoStart || videoEnd > info.size) {
      throw StateError('源文件视频结束位置无效');
    }
    final auxiliaryItems = info.auxiliaryItems;
    final auxiliaryLength = auxiliaryItems.fold<int>(
      0,
      (sum, item) => sum + (item.parsedLength ?? 0),
    );
    final auxiliaryEnd = info.eoi + auxiliaryLength;
    if (auxiliaryEnd > videoStart) {
      throw StateError('辅助图片长度超过视频起点，容器元数据无效');
    }
    final hdrGainMap =
        info.xmpTags.containsKey('hdrgm:Version') ||
        auxiliaryItems.any((item) => item.semantic == 'GainMap');
    return _CanonicalLayout(
      primaryEnd: info.eoi,
      auxiliaryEnd: auxiliaryEnd,
      videoStart: videoStart,
      videoEnd: videoEnd,
      auxiliaryItems: auxiliaryItems,
      hdrGainMap: hdrGainMap,
    );
  }

  static Future<void> _writeCanonicalImage({
    required RandomAccessFile src,
    required RandomAccessFile dst,
    required MotionPhotoInfo info,
    required _CanonicalLayout layout,
    required _JpegHeaderInfo header,
    required Uint8List? app1,
    Uint8List? exifReplacement,
  }) async {
    final uniqueSpans = <String, ByteSpan>{};
    for (final span in [...info.motionXmpSpans, ...info.containerXmpSpans]) {
      if (span.start >= 2 && span.end <= layout.primaryEnd) {
        uniqueSpans['${span.start}:${span.end}'] = span;
      }
    }
    final xmpSpans = uniqueSpans.values.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final replacements = <_ByteReplacement>[];
    if (xmpSpans.isNotEmpty) {
      for (var index = 0; index < xmpSpans.length; index++) {
        final span = xmpSpans[index];
        replacements.add(
          _ByteReplacement(
            start: span.start,
            end: span.end,
            bytes: index == 0 && app1 != null ? app1 : Uint8List(0),
            priority: 1,
          ),
        );
      }
    } else if (app1 != null) {
      replacements.add(
        _ByteReplacement(
          start: header.exifSpan?.end ?? 2,
          end: header.exifSpan?.end ?? 2,
          bytes: app1,
          priority: 1,
        ),
      );
    }

    if (exifReplacement != null) {
      final exif = header.exifSpan;
      replacements.add(
        _ByteReplacement(
          start: exif?.start ?? 2,
          end: exif?.end ?? 2,
          bytes: exifReplacement,
          priority: 0,
        ),
      );
    }
    replacements.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.priority.compareTo(b.priority);
    });

    var cursor = 0;
    for (final replacement in replacements) {
      if (replacement.start < cursor && replacement.end > cursor) continue;
      if (replacement.start > cursor) {
        await _copyRange(src, dst, cursor, replacement.start);
      }
      if (replacement.bytes.isNotEmpty) {
        await dst.writeFrom(replacement.bytes);
      }
      cursor = max(cursor, replacement.end);
    }
    if (cursor < layout.primaryEnd) {
      await _copyRange(src, dst, cursor, layout.primaryEnd);
    }
    if (layout.auxiliaryEnd > layout.primaryEnd) {
      await _copyRange(src, dst, layout.primaryEnd, layout.auxiliaryEnd);
    }
  }

  static Future<int> _canonicalVideoEnd(
    RandomAccessFile src,
    _CanonicalLayout layout,
  ) async {
    var position = layout.videoStart;
    final boxes = <_Mp4TopLevelBox>[];
    while (position + 8 <= layout.videoEnd) {
      await src.setPosition(position);
      final header = await src.read(min(24, layout.videoEnd - position));
      if (header.length < 8 || !_printableBoxType(header, 4)) break;
      var size =
          (header[0] << 24) | (header[1] << 16) | (header[2] << 8) | header[3];
      var headerSize = 8;
      if (size == 1) {
        if (header.length < 16) break;
        size = 0;
        for (var index = 8; index < 16; index++) {
          size = (size << 8) | header[index];
        }
        headerSize = 16;
      } else if (size == 0) {
        size = layout.videoEnd - position;
      }
      if (size < headerSize || position + size > layout.videoEnd) break;
      final type = ascii.decode(header.sublist(4, 8), allowInvalid: true);
      String? userType;
      if (type == 'uuid' && header.length >= headerSize + 16) {
        userType = ascii.decode(
          header.sublist(headerSize, headerSize + 16),
          allowInvalid: true,
        );
      }
      boxes.add(
        _Mp4TopLevelBox(
          start: position,
          end: position + size,
          type: type,
          userType: userType,
        ),
      );
      position += size;
    }
    var end = layout.videoEnd;
    for (final box in boxes.reversed) {
      if (box.end != end ||
          box.type != 'uuid' ||
          (box.userType != 'vivoMediaEStream' &&
              box.userType != 'vivoMediaExtInfo')) {
        break;
      }
      end = box.start;
    }
    return end;
  }

  static bool _printableBoxType(Uint8List data, int offset) {
    if (offset + 4 > data.length) return false;
    for (var index = 0; index < 4; index++) {
      final value = data[offset + index];
      if (value < 0x20 || value > 0x7E) return false;
    }
    return true;
  }

  static Future<_JpegHeaderInfo> _readJpegHeader(
    RandomAccessFile src,
    int primaryEnd,
  ) async {
    var position = 2;
    ByteSpan? exifSpan;
    int? width;
    int? height;
    while (position + 4 <= primaryEnd) {
      await src.setPosition(position);
      final header = await src.read(4);
      if (header.length < 4 || header[0] != 0xFF) break;
      final marker = header[1];
      if (marker == 0xDA || marker == 0xD9) break;
      final length = (header[2] << 8) | header[3];
      if (length < 2 || position + 2 + length > primaryEnd) break;
      final end = position + 2 + length;
      final payloadLength = length - 2;
      await src.setPosition(position + 4);
      final prefix = await src.read(min(payloadLength, 16));
      if (marker == 0xE1 &&
          prefix.length >= 6 &&
          prefix[0] == 0x45 &&
          prefix[1] == 0x78 &&
          prefix[2] == 0x69 &&
          prefix[3] == 0x66 &&
          prefix[4] == 0x00 &&
          prefix[5] == 0x00) {
        exifSpan ??= ByteSpan(position, end);
      }
      if (_isSofMarker(marker) && prefix.length >= 5) {
        height ??= (prefix[1] << 8) | prefix[2];
        width ??= (prefix[3] << 8) | prefix[4];
      }
      position = end;
    }
    return _JpegHeaderInfo(exifSpan: exifSpan, width: width, height: height);
  }

  static bool _isSofMarker(int marker) => const {
    0xC0,
    0xC1,
    0xC2,
    0xC3,
    0xC5,
    0xC6,
    0xC7,
    0xC9,
    0xCA,
    0xCB,
    0xCD,
    0xCE,
    0xCF,
  }.contains(marker);

  static Future<void> _copyRange(
    RandomAccessFile src,
    RandomAccessFile dst,
    int start,
    int end,
  ) async {
    await src.setPosition(start);
    var position = start;
    while (position < end) {
      final length = min(_chunkSize, end - position);
      final buffer = await src.read(length);
      if (buffer.isEmpty) break;
      await dst.writeFrom(buffer);
      position += buffer.length;
    }
  }

  static Future<Uint8List> _readRange(
    RandomAccessFile src,
    int start,
    int end,
  ) async {
    await src.setPosition(start);
    return Uint8List.fromList(await src.read(end - start));
  }
}

class _Mp4TopLevelBox {
  const _Mp4TopLevelBox({
    required this.start,
    required this.end,
    required this.type,
    this.userType,
  });

  final int start;
  final int end;
  final String type;
  final String? userType;
}

class _ByteReplacement {
  const _ByteReplacement({
    required this.start,
    required this.end,
    required this.bytes,
    required this.priority,
  });

  final int start;
  final int end;
  final Uint8List bytes;
  final int priority;
}

class _JpegHeaderInfo {
  const _JpegHeaderInfo({this.exifSpan, this.width, this.height});

  final ByteSpan? exifSpan;
  final int? width;
  final int? height;
}

class _CanonicalLayout {
  const _CanonicalLayout({
    required this.primaryEnd,
    required this.auxiliaryEnd,
    required this.videoStart,
    required this.videoEnd,
    required this.auxiliaryItems,
    required this.hdrGainMap,
  });

  final int primaryEnd;
  final int auxiliaryEnd;
  final int videoStart;
  final int videoEnd;
  final List<ContainerItem> auxiliaryItems;
  final bool hdrGainMap;

  int get videoSize => videoEnd - videoStart;
}
