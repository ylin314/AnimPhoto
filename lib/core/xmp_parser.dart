/// 极简 XMP 解析：从 JPEG 的 APP1 段提取 XMP 文本、关注命名空间标签与容器条目。
/// 不引入重量级 XML 库，按本项目需求做字符串解析（见 AGENT.md 5.2）。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'byte_utils.dart';
import 'motion_photo.dart';

/// 单个 XMP 段的元信息。
class XmpSegment {
  const XmpSegment({
    required this.start,
    required this.end,
    required this.isMotion,
    required this.isContainer,
  });

  final int start;
  final int end;

  /// 是否包含动态照片标记（GCamera/OpCamera/VCamera/MiCamera/MotionPhoto/MicroVideo）。
  final bool isMotion;

  /// 是否包含 Container:Directory（GainMap/MotionPhoto 容器转换时需整体重建）。
  final bool isContainer;
}

class XmpResult {
  XmpResult({
    this.offsets = const [],
    this.texts = const [],
    this.tags = const {},
    this.items = const [],
    this.segments = const [],
  });

  /// APP1 段偏移列表。
  final List<int> offsets;

  /// XMP 文本列表。
  final List<String> texts;

  /// 关注的命名空间标签（如 `GCamera:MotionPhoto`）。
  final Map<String, String> tags;

  /// 容器条目列表（保持文件中的顺序）。
  final List<ContainerItem> items;

  /// 各 XMP 段的区间与运动标记判定。
  final List<XmpSegment> segments;
}

/// 关注的前缀命名空间。
const Set<String> _namespaces = {
  'GCamera',
  'OpCamera',
  'VCamera',
  'MiCamera',
  'AnimPhoto',
  'Item',
  'Container',
  'hdrgm',
  'Camera',
};

/// 动态照片标记（用于判定是否剥离）。
final RegExp _motionMarker = RegExp(
  r'(GCamera|OpCamera|VCamera|MiCamera|MotionPhoto|MicroVideo)',
);

/// "http://ns.adobe.com/xap/1.0/\x00"
const List<int> _xapPrefix = [
  0x68,
  0x74,
  0x74,
  0x70,
  0x3A,
  0x2F,
  0x2F,
  0x6E,
  0x73,
  0x2E,
  0x61,
  0x64,
  0x6F,
  0x62,
  0x65,
  0x2E,
  0x63,
  0x6F,
  0x6D,
  0x2F,
  0x78,
  0x61,
  0x70,
  0x2F,
  0x31,
  0x2E,
  0x30,
  0x2F,
  0x00,
];

class XmpParser {
  XmpParser._();

  /// 扫描 JPEG 头部各段，返回 APP1 中的 XMP 解析结果。
  static XmpResult parse(Uint8List data) {
    final app1Segments = <({int start, Uint8List bytes})>[];
    var pos = 2;
    while (pos + 4 <= data.length) {
      if (data[pos] != 0xFF) break;
      final marker = data[pos + 1];
      if (marker == 0xDA || marker == 0xD9) break; // SOS / EOI
      final len = (data[pos + 2] << 8) | data[pos + 3];
      if (len < 2 || pos + 2 + len > data.length) break;
      if (marker == 0xE1) {
        app1Segments.add((
          start: pos,
          bytes: Uint8List.sublistView(data, pos, pos + 2 + len),
        ));
      }
      pos += 2 + len;
    }
    return parseApp1Segments(app1Segments);
  }

  /// 解析通过随机访问读取的完整 APP1 段。
  static XmpResult parseApp1Segments(
    List<({int start, Uint8List bytes})> app1Segments,
  ) {
    final offsets = <int>[];
    final texts = <String>[];
    final segments = <XmpSegment>[];
    for (final segment in app1Segments) {
      final bytes = segment.bytes;
      if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xE1) continue;
      final len = (bytes[2] << 8) | bytes[3];
      if (len < 2 || len + 2 > bytes.length) continue;
      final payload = Uint8List.sublistView(bytes, 4, 2 + len);
      if (payload.length < _xapPrefix.length ||
          ByteUtils.findBytes(
                payload,
                _xapPrefix,
                start: 0,
                end: _xapPrefix.length,
              ) !=
              0) {
        continue;
      }
      final text = utf8.decode(
        payload.sublist(_xapPrefix.length),
        allowMalformed: true,
      );
      offsets.add(segment.start);
      texts.add(text);
      segments.add(
        XmpSegment(
          start: segment.start,
          end: segment.start + 2 + len,
          isMotion: _motionMarker.hasMatch(text),
          isContainer: text.contains('Container:Directory'),
        ),
      );
    }
    final tags = <String, String>{};
    final items = <ContainerItem>[];
    final tagRe = RegExp(r'([A-Za-z]+):([A-Za-z0-9]+)="([^"]*)"');
    final itemRe = RegExp(r'<Container:Item\b([^>]*)/>');
    final attrRe = RegExp(r'(Item:[A-Za-z]+)="([^"]*)"');
    for (final text in texts) {
      for (final m in tagRe.allMatches(text)) {
        final ns = m.group(1)!;
        if (_namespaces.contains(ns)) {
          tags['$ns:${m.group(2)}'] = m.group(3)!;
        }
      }
      for (final m in itemRe.allMatches(text)) {
        final attrs = <String, String>{};
        for (final a in attrRe.allMatches(m.group(1)!)) {
          attrs[a.group(1)!] = a.group(2)!;
        }
        items.add(
          ContainerItem(
            mime: attrs['Item:Mime'],
            semantic: attrs['Item:Semantic'],
            length: attrs['Item:Length'],
            padding: attrs['Item:Padding'],
          ),
        );
      }
    }
    return XmpResult(
      offsets: offsets,
      texts: texts,
      tags: tags,
      items: items,
      segments: segments,
    );
  }
}
