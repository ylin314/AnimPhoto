import 'dart:convert';
import 'dart:typed_data';

/// OPPO/vivo 相册识别所需的厂商私有元数据构造器。
///
/// 这里只重组 JPEG/MP4 容器字节，不修改图像或视频码流。
class VendorMetadata {
  VendorMetadata._();

  static const int vivoBoundaryLength = 11;
  static final Uint8List vivoBoundary = Uint8List.fromList(
    ascii.encode('cameralbum!'),
  );

  /// OPPO 原生照片在 EXIF UserComment 中写入 `oplus_*` 特征位。
  ///
  /// 保留原 TIFF 数据及全部已有标签，仅把 ExifIFD 克隆到 TIFF 尾部并
  /// 增加/替换 UserComment，再修正 ExifIFD 指针；不会重编码 JPEG。
  static Uint8List? buildOppoExifApp1(Uint8List? original) {
    final comment = Uint8List(264);
    comment.setRange(0, 8, ascii.encode('ASCII\x00\x00\x00'));
    final value = ascii.encode('oplus_8388608');
    comment.setRange(8, 8 + value.length, value);

    if (original == null) return _minimalExif(comment);
    if (original.length < 18 ||
        original[0] != 0xFF ||
        original[1] != 0xE1 ||
        ascii.decode(original.sublist(4, 10), allowInvalid: true) !=
            'Exif\x00\x00') {
      return null;
    }
    // 已是 OPPO EXIF 时不重复扩展，避免接近 64 KiB 的 MakerNote 段溢出。
    final existing = latin1.decode(original, allowInvalid: true);
    if (existing.contains('oplus_')) return original;

    final tiff = Uint8List.fromList(original.sublist(10));
    if (tiff.length < 8) return null;
    final little = tiff[0] == 0x49 && tiff[1] == 0x49;
    if (!little && !(tiff[0] == 0x4D && tiff[1] == 0x4D)) return null;
    final ifd0 = _u32(tiff, 4, little);
    final ifd0Entries = _readIfdEntries(tiff, ifd0, little);
    if (ifd0Entries == null) return null;

    final mutable = BytesBuilder(copy: false)..add(tiff);
    var bytes = mutable.takeBytes();
    final exifEntryIndex = ifd0Entries.indexWhere(
      (entry) => _u16(entry, 0, little) == 0x8769,
    );

    if (exifEntryIndex >= 0) {
      final exifOffset = _u32(ifd0Entries[exifEntryIndex], 8, little);
      final exifEntries = _readIfdEntries(bytes, exifOffset, little);
      if (exifEntries == null) return null;
      final oldCount = _u16(bytes, exifOffset, little);
      final oldNextPos = exifOffset + 2 + oldCount * 12;
      final next = oldNextPos + 4 <= bytes.length
          ? _u32(bytes, oldNextPos, little)
          : 0;
      final kept = exifEntries
          .where((entry) => _u16(entry, 0, little) != 0x9286)
          .toList();
      final newIfdOffset = _align2(bytes.length);
      final directoryLength = 2 + (kept.length + 1) * 12 + 4;
      final commentOffset = newIfdOffset + directoryLength;
      kept.add(
        _entry(
          tag: 0x9286,
          type: 7,
          count: comment.length,
          value: commentOffset,
          little: little,
        ),
      );
      kept.sort((a, b) => _u16(a, 0, little).compareTo(_u16(b, 0, little)));
      bytes = _appendIfdAndData(
        bytes,
        offset: newIfdOffset,
        entries: kept,
        next: next,
        data: comment,
        little: little,
      );
      final pointerPos = ifd0 + 2 + exifEntryIndex * 12 + 8;
      _setU32(bytes, pointerPos, newIfdOffset, little);
    } else {
      final exifOffset = _align2(bytes.length);
      final exifLength = 2 + 12 + 4;
      final commentOffset = exifOffset + exifLength;
      bytes = _appendIfdAndData(
        bytes,
        offset: exifOffset,
        entries: [
          _entry(
            tag: 0x9286,
            type: 7,
            count: comment.length,
            value: commentOffset,
            little: little,
          ),
        ],
        next: 0,
        data: comment,
        little: little,
      );
      final newIfd0Offset = _align2(bytes.length);
      final entries = [
        ...ifd0Entries,
        _entry(
          tag: 0x8769,
          type: 4,
          count: 1,
          value: exifOffset,
          little: little,
        ),
      ]..sort((a, b) => _u16(a, 0, little).compareTo(_u16(b, 0, little)));
      final oldCount = _u16(bytes, ifd0, little);
      final oldNextPos = ifd0 + 2 + oldCount * 12;
      final next = oldNextPos + 4 <= bytes.length
          ? _u32(bytes, oldNextPos, little)
          : 0;
      bytes = _appendIfdAndData(
        bytes,
        offset: newIfd0Offset,
        entries: entries,
        next: next,
        data: Uint8List(0),
        little: little,
      );
      _setU32(bytes, 4, newIfd0Offset, little);
    }

    final payloadLength = 6 + bytes.length;
    if (payloadLength + 2 > 0xFFFF) return null;
    final out = Uint8List(payloadLength + 4);
    out[0] = 0xFF;
    out[1] = 0xE1;
    out[2] = ((payloadLength + 2) >> 8) & 0xFF;
    out[3] = (payloadLength + 2) & 0xFF;
    out.setRange(4, 10, ascii.encode('Exif\x00\x00'));
    out.setRange(10, out.length, bytes);
    return out;
  }

  /// 构造 vivo 新单文件格式的视频尾部 UUID 盒。
  static Uint8List buildVivoVideoExtensions({
    required int width,
    required int height,
    String? model,
    String? id,
    int? clockValue,
  }) {
    final resolvedId = id ?? _vivoId();
    final clock =
        clockValue ??
        DateTime.now().millisecondsSinceEpoch.remainder(1000000000000);
    final metadata = <String, Object>{
      'com.android.camera.compensation': '[$clock, ${clock + 76746}]',
      'com.android.camera.takenmodel': (model?.trim().isNotEmpty ?? false)
          ? model!.trim()
          : 'vivo',
      'com.android.camera.camerafacing': '0',
      'com.android.camera.imageTime': 33,
      'com.android.camera.livePhoto.firstFrame': clock,
      'com.android.camera.moduleid': 'photo',
      'version': 2103,
      'com.android.camera.livephoto': resolvedId,
      'com.android.camera.faceInfo': <String, Object>{},
    };
    final jsonObject = Uint8List.fromList(utf8.encode(jsonEncode(metadata)));
    final extInfoPayload = BytesBuilder(copy: false)
      ..add(ascii.encode('vivo'))
      ..add(jsonObject)
      ..add(_be32(jsonObject.length))
      ..add(ascii.encode('cameralbum!'));
    final tailLength = 4 + resolvedId.length + 15;
    extInfoPayload
      ..add(_be32(tailLength))
      ..add(ascii.encode(resolvedId))
      ..add(
        Uint8List.fromList(const [
          0xFF,
          0xFF,
          0xFF,
          0xFF,
          0x1B,
          0x2A,
          0x39,
          0x48,
          0x57,
          0x66,
          0x75,
          0x84,
          0x93,
          0xA2,
          0xB3,
        ]),
      );

    final streamPayload = _vivoStreamPayload(
      width: width,
      height: height,
      jsonObjectLength: jsonObject.length,
    );
    return Uint8List.fromList([
      ..._uuidBox('vivoMediaEStream', streamPayload),
      ..._uuidBox('vivoMediaExtInfo', extInfoPayload.takeBytes()),
    ]);
  }

  static Uint8List _vivoStreamPayload({
    required int width,
    required int height,
    required int jsonObjectLength,
  }) {
    final bytes = Uint8List.fromList(const [
      0x73,
      0x74,
      0x72,
      0x65,
      0x61,
      0x6D,
      0x64,
      0x61,
      0x74,
      0x61,
      0x44,
      0x45,
      0x47,
      0x53,
      0x00,
      0x02,
      0xFE,
      0x01,
      0x00,
      0x00,
      0xFE,
      0x02,
      0x00,
      0x00,
      0xFE,
      0x03,
      0x00,
      0x01,
      0x00,
      0x00,
      0xFE,
      0x04,
      0x00,
      0x00,
      0x00,
      0x00,
      0xFE,
      0x05,
      0x00,
      0x00,
      0x00,
      0x00,
      0xFE,
      0x06,
      0x00,
      0x00,
      0x00,
      0x00,
      0xFE,
      0x07,
      0x00,
      0x00,
      0x10,
      0x00,
      0xFE,
      0x08,
      0x00,
      0x00,
      0x09,
      0x00,
      0xFE,
      0x0A,
      0x00,
      0x00,
      0x01,
      0x79,
      0xFE,
      0x0B,
      0x00,
      0x00,
      0x00,
      0x5A,
      0xFE,
      0x0C,
      0x00,
      0x00,
      0x00,
      0x00,
      0x44,
      0x45,
      0x47,
      0x45,
      0x73,
      0x74,
      0x72,
      0x65,
      0x61,
      0x6D,
      0x69,
      0x6E,
      0x66,
      0x6F,
      0x00,
      0x06,
      0x00,
      0x01,
      0x06,
      0x00,
      0x00,
      0x00,
      0x48,
      0x73,
      0x74,
      0x72,
      0x65,
      0x61,
      0x6D,
      0x63,
      0x6F,
      0x75,
      0x6E,
      0x74,
      0x00,
      0x01,
    ]);
    final longEdge = width > height ? width : height;
    final shortEdge = width > height ? height : width;
    _setBe32(bytes, 50, longEdge);
    _setBe32(bytes, 56, shortEdge);
    // 原生样本中该字段等于 ext-info JSON 长度减 12。
    _setBe32(bytes, 62, jsonObjectLength > 12 ? jsonObjectLength - 12 : 0);
    return bytes;
  }

  static Uint8List _uuidBox(String userType, Uint8List payload) {
    final type = ascii.encode(userType);
    if (type.length != 16) throw ArgumentError('vivo UUID type 必须为 16 字节');
    final size = 24 + payload.length;
    return Uint8List.fromList([
      ..._be32(size),
      ...ascii.encode('uuid'),
      ...type,
      ...payload,
    ]);
  }

  static String _vivoId() {
    final value = DateTime.now().millisecondsSinceEpoch
        .remainder(100000000000000000)
        .toString()
        .padLeft(17, '0');
    return 'motionphoto$value';
  }

  static Uint8List _minimalExif(Uint8List comment) {
    final tiff = Uint8List(44 + comment.length);
    tiff.setRange(0, 4, const [0x49, 0x49, 0x2A, 0x00]);
    _setU32(tiff, 4, 8, true);
    _setU16(tiff, 8, 1, true);
    tiff.setRange(
      10,
      22,
      _entry(tag: 0x8769, type: 4, count: 1, value: 26, little: true),
    );
    _setU32(tiff, 22, 0, true);
    _setU16(tiff, 26, 1, true);
    tiff.setRange(
      28,
      40,
      _entry(
        tag: 0x9286,
        type: 7,
        count: comment.length,
        value: 44,
        little: true,
      ),
    );
    _setU32(tiff, 40, 0, true);
    tiff.setRange(44, tiff.length, comment);
    final out = Uint8List(10 + tiff.length);
    out[0] = 0xFF;
    out[1] = 0xE1;
    final payloadLength = 6 + tiff.length;
    out[2] = ((payloadLength + 2) >> 8) & 0xFF;
    out[3] = (payloadLength + 2) & 0xFF;
    out.setRange(4, 10, ascii.encode('Exif\x00\x00'));
    out.setRange(10, out.length, tiff);
    return out;
  }

  static List<Uint8List>? _readIfdEntries(
    Uint8List bytes,
    int offset,
    bool little,
  ) {
    if (offset < 0 || offset + 2 > bytes.length) return null;
    final count = _u16(bytes, offset, little);
    if (offset + 2 + count * 12 + 4 > bytes.length) return null;
    return List.generate(
      count,
      (index) => Uint8List.fromList(
        bytes.sublist(offset + 2 + index * 12, offset + 14 + index * 12),
      ),
    );
  }

  static Uint8List _appendIfdAndData(
    Uint8List original, {
    required int offset,
    required List<Uint8List> entries,
    required int next,
    required Uint8List data,
    required bool little,
  }) {
    final directoryLength = 2 + entries.length * 12 + 4;
    final out = Uint8List(offset + directoryLength + data.length);
    out.setRange(0, original.length, original);
    _setU16(out, offset, entries.length, little);
    var cursor = offset + 2;
    for (final entry in entries) {
      out.setRange(cursor, cursor + 12, entry);
      cursor += 12;
    }
    _setU32(out, cursor, next, little);
    out.setRange(offset + directoryLength, out.length, data);
    return out;
  }

  static Uint8List _entry({
    required int tag,
    required int type,
    required int count,
    required int value,
    required bool little,
  }) {
    final out = Uint8List(12);
    _setU16(out, 0, tag, little);
    _setU16(out, 2, type, little);
    _setU32(out, 4, count, little);
    _setU32(out, 8, value, little);
    return out;
  }

  static int _align2(int value) => (value + 1) & ~1;

  static int _u16(Uint8List bytes, int offset, bool little) => little
      ? bytes[offset] | (bytes[offset + 1] << 8)
      : (bytes[offset] << 8) | bytes[offset + 1];

  static int _u32(Uint8List bytes, int offset, bool little) => little
      ? bytes[offset] |
            (bytes[offset + 1] << 8) |
            (bytes[offset + 2] << 16) |
            (bytes[offset + 3] << 24)
      : (bytes[offset] << 24) |
            (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) |
            bytes[offset + 3];

  static void _setU16(Uint8List bytes, int offset, int value, bool little) {
    if (little) {
      bytes[offset] = value & 0xFF;
      bytes[offset + 1] = (value >> 8) & 0xFF;
    } else {
      bytes[offset] = (value >> 8) & 0xFF;
      bytes[offset + 1] = value & 0xFF;
    }
  }

  static void _setU32(Uint8List bytes, int offset, int value, bool little) {
    if (little) {
      for (var i = 0; i < 4; i++) {
        bytes[offset + i] = (value >> (8 * i)) & 0xFF;
      }
    } else {
      _setBe32(bytes, offset, value);
    }
  }

  static Uint8List _be32(int value) => Uint8List.fromList([
    (value >> 24) & 0xFF,
    (value >> 16) & 0xFF,
    (value >> 8) & 0xFF,
    value & 0xFF,
  ]);

  static void _setBe32(Uint8List bytes, int offset, int value) {
    bytes[offset] = (value >> 24) & 0xFF;
    bytes[offset + 1] = (value >> 16) & 0xFF;
    bytes[offset + 2] = (value >> 8) & 0xFF;
    bytes[offset + 3] = value & 0xFF;
  }
}
