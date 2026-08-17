/// 动态照片相关数据模型（纯 Dart，无 UI 依赖）。
library;

/// 单文件动态照片的格式归类。
enum LivePhotoFormat {
  googleMotionPhoto, // Google 标准（GCamera + Container）
  oppo, // 附加 OpCamera 私有命名空间
  vivo, // 附加 VCamera 私有命名空间
  xiaomi, // 小米（GCamera，旧版可能用 MicroVideoOffset）
  honorHuaweiOld, // OpenHarmony 旧格式单文件（LIVE_ 尾标）
  unknown,
}

/// 转换目标格式（按本机品牌选择）。
enum TargetFormat {
  google, // 通用 Google Motion Photo 标准
  oppo,
  vivo,
  xiaomi,
  honorHuawei, // OpenHarmony 旧格式单文件（LIVE_ 尾标）
}

/// XMP 容器条目（Container:Directory 内的 Item）。
class ContainerItem {
  const ContainerItem({this.mime, this.semantic, this.length, this.padding});

  final String? mime;
  final String? semantic;
  final String? length;
  final String? padding;

  bool get isVideo => semantic == 'MotionPhoto' || mime == 'video/mp4';

  bool get isPrimary => semantic == 'Primary';

  int? get parsedLength => int.tryParse(length ?? '');

  @override
  String toString() =>
      'Item(mime: $mime, semantic: $semantic, length: $length)';
}

/// 文件中一段字节区间（左闭右开）。
class ByteSpan {
  const ByteSpan(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;

  @override
  String toString() => 'ByteSpan($start, $end)';
}

/// OpenHarmony 旧格式尾部标记信息。
class TrailerInfo {
  const TrailerInfo({
    this.liveTag,
    this.liveSize,
    this.versionTag,
    this.version,
    this.frameIndex,
    this.playInfo,
  });

  /// 如 `LIVE_5838362`。
  final String? liveTag;
  final int? liveSize;
  final String? versionTag;
  final int? version;
  final int? frameIndex;
  final String? playInfo;
}

/// 单个动态照片文件的解析结果。
class MotionPhotoInfo {
  MotionPhotoInfo({
    required this.path,
    required this.size,
    this.eoi = -1,
    this.videoOffset,
    this.videoOffsetMethod,
    this.format = LivePhotoFormat.unknown,
    this.xmpTags = const {},
    this.containerItems = const [],
    this.trailer,
    this.exifMake,
    this.exifModel,
    this.exifDateTimeOriginal,
    this.exifSoftware,
    this.motionXmpSpans = const [],
    this.containerXmpSpans = const [],
    this.videoEnd,
  });

  /// 文件绝对路径。
  final String path;
  final int size;

  /// JPEG EOI（FF D9）之后的绝对偏移；未找到为 -1。
  final int eoi;

  /// 视频区域起点（MP4 ftyp 盒子的 size 字段位置）；未识别为 null。
  final int? videoOffset;

  /// 视频定位方法描述。
  final String? videoOffsetMethod;

  final LivePhotoFormat format;
  final Map<String, String> xmpTags;
  final List<ContainerItem> containerItems;
  final TrailerInfo? trailer;
  final String? exifMake;
  final String? exifModel;

  /// EXIF DateTimeOriginal（如 `2026:08:10 18:05:34`）。
  final String? exifDateTimeOriginal;

  /// EXIF Software（相机固件/软件）。
  final String? exifSoftware;

  /// 图片区内**含动态照片标记**的 XMP APP1 段区间（转换时需剥离）。
  final List<ByteSpan> motionXmpSpans;

  /// 含 Container:Directory 的 XMP，转换时会连同 MotionPhoto/GainMap 目录一起重建。
  final List<ByteSpan> containerXmpSpans;

  /// 视频区域结束偏移（左闭右开）；null 表示到文件尾。
  final int? videoEnd;

  /// 有效视频区域结束偏移（默认文件尾）。
  int get effectiveVideoEnd => videoEnd ?? size;

  /// 是否为可识别的单文件动态照片。
  bool get isLivePhoto => videoOffset != null;

  /// 动态照片之前按容器顺序排列的辅助图片（例如 Ultra HDR GainMap）。
  List<ContainerItem> get auxiliaryItems => containerItems
      .where(
        (item) =>
            !item.isPrimary && !item.isVideo && (item.parsedLength ?? 0) > 0,
      )
      .toList(growable: false);

  /// 静态封面在视频中的时间戳。Google XMP 使用微秒；OpenHarmony playInfo 使用毫秒。
  int get presentationTimestampUs {
    for (final key in const [
      'GCamera:MotionPhotoPresentationTimestampUs',
      'OpCamera:MotionPhotoPrimaryPresentationTimestampUs',
      'GCamera:MicroVideoPresentationTimestampUs',
    ]) {
      final value = int.tryParse(xmpTags[key] ?? '');
      if (value != null && value >= 0) return value;
    }
    final playInfo = trailer?.playInfo;
    if (playInfo != null) {
      final parts = playInfo.split(':');
      final coverMs = int.tryParse(parts.isEmpty ? '' : parts.last);
      if (coverMs != null && coverMs >= 0) return coverMs * 1000;
    }
    return -1;
  }

  /// 视频区域字节数（有效区域，不含厂商私有尾随数据/尾标）。
  int? get videoBytes =>
      videoOffset == null ? null : effectiveVideoEnd - videoOffset!;

  MotionPhotoInfo copyWith({
    String? path,
    int? size,
    int? eoi,
    int? videoOffset,
    String? videoOffsetMethod,
    LivePhotoFormat? format,
    Map<String, String>? xmpTags,
    List<ContainerItem>? containerItems,
    TrailerInfo? trailer,
    String? exifMake,
    String? exifModel,
    String? exifDateTimeOriginal,
    String? exifSoftware,
    List<ByteSpan>? motionXmpSpans,
    List<ByteSpan>? containerXmpSpans,
    int? videoEnd,
  }) {
    return MotionPhotoInfo(
      path: path ?? this.path,
      size: size ?? this.size,
      eoi: eoi ?? this.eoi,
      videoOffset: videoOffset ?? this.videoOffset,
      videoOffsetMethod: videoOffsetMethod ?? this.videoOffsetMethod,
      format: format ?? this.format,
      xmpTags: xmpTags ?? this.xmpTags,
      containerItems: containerItems ?? this.containerItems,
      trailer: trailer ?? this.trailer,
      exifMake: exifMake ?? this.exifMake,
      exifModel: exifModel ?? this.exifModel,
      exifDateTimeOriginal: exifDateTimeOriginal ?? this.exifDateTimeOriginal,
      exifSoftware: exifSoftware ?? this.exifSoftware,
      motionXmpSpans: motionXmpSpans ?? this.motionXmpSpans,
      containerXmpSpans: containerXmpSpans ?? this.containerXmpSpans,
      videoEnd: videoEnd ?? this.videoEnd,
    );
  }

  /// 序列化为缓存 JSON（用于启动时免全量检测）。
  Map<String, dynamic> toCacheJson() => {
    'path': path,
    'size': size,
    'eoi': eoi,
    'videoOffset': videoOffset,
    'method': videoOffsetMethod,
    'format': format.name,
    'xmpTags': xmpTags,
    'containerItems': containerItems
        .map(
          (item) => {
            'mime': item.mime,
            'semantic': item.semantic,
            'length': item.length,
            'padding': item.padding,
          },
        )
        .toList(),
    'exifMake': exifMake,
    'exifModel': exifModel,
    'exifDateTimeOriginal': exifDateTimeOriginal,
    'exifSoftware': exifSoftware,
    'liveTag': trailer?.liveTag,
    'liveSize': trailer?.liveSize,
    'versionTag': trailer?.versionTag,
    'version': trailer?.version,
    'frameIndex': trailer?.frameIndex,
    'playInfo': trailer?.playInfo,
    'motionXmpSpans': motionXmpSpans.map((s) => [s.start, s.end]).toList(),
    'containerXmpSpans': containerXmpSpans
        .map((span) => [span.start, span.end])
        .toList(),
    'videoEnd': videoEnd,
  };

  /// 从缓存 JSON 还原。
  static MotionPhotoInfo fromCacheJson(Map<String, dynamic> j) {
    final spans = (j['motionXmpSpans'] as List<dynamic>? ?? const [])
        .map((e) => ByteSpan((e as List)[0] as int, e[1] as int))
        .toList();
    final containerSpans =
        (j['containerXmpSpans'] as List<dynamic>? ?? const [])
            .map((e) => ByteSpan((e as List)[0] as int, e[1] as int))
            .toList();
    return MotionPhotoInfo(
      path: j['path'] as String,
      size: j['size'] as int,
      eoi: j['eoi'] as int? ?? -1,
      videoOffset: j['videoOffset'] as int?,
      videoOffsetMethod: j['method'] as String?,
      format:
          LivePhotoFormat.values.asNameMap()[j['format']] ??
          LivePhotoFormat.unknown,
      xmpTags: (j['xmpTags'] as Map?)?.cast<String, String>() ?? const {},
      containerItems: (j['containerItems'] as List<dynamic>? ?? const []).map((
        value,
      ) {
        final item = (value as Map).cast<String, dynamic>();
        return ContainerItem(
          mime: item['mime'] as String?,
          semantic: item['semantic'] as String?,
          length: item['length'] as String?,
          padding: item['padding'] as String?,
        );
      }).toList(),
      exifMake: j['exifMake'] as String?,
      exifModel: j['exifModel'] as String?,
      exifDateTimeOriginal: j['exifDateTimeOriginal'] as String?,
      exifSoftware: j['exifSoftware'] as String?,
      trailer: TrailerInfo(
        liveTag: j['liveTag'] as String?,
        liveSize: j['liveSize'] as int?,
        versionTag: j['versionTag'] as String?,
        version: j['version'] as int?,
        frameIndex: j['frameIndex'] as int?,
        playInfo: j['playInfo'] as String?,
      ),
      motionXmpSpans: spans,
      containerXmpSpans: containerSpans,
      videoEnd: j['videoEnd'] as int?,
    );
  }
}
