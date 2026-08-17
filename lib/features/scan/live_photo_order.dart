/// 动态照片排序：相册展示与查看页左右滑动共用同一顺序。
///
/// 排序规则：优先 EXIF DateTimeOriginal；没有有效 EXIF 时间时回退到
/// MediaStore DATE_ADDED；仍无法取值时回退到文件修改时间。
/// 这样可以兼容导入/迁移照片：拍摄时间保留在 EXIF，而添加时间反映进入
/// 本机媒体库的顺序。
library;

import '../../models/live_photo_entry.dart';

/// 标准格式 `yyyy:MM:dd HH:mm:ss`；时区归属由拍摄设备语义决定，
/// 这里只做时间轴排序，不做时区换算。
DateTime? _parseExifDateTime(String? value) {
  if (value == null || value.length < 19 || value[4] != ':') return null;
  final year = int.tryParse(value.substring(0, 4));
  final month = int.tryParse(value.substring(5, 7));
  final day = int.tryParse(value.substring(8, 10));
  final hour = int.tryParse(value.substring(11, 13));
  final minute = int.tryParse(value.substring(14, 16));
  final second = int.tryParse(value.substring(17, 19));
  if (year == null ||
      month == null ||
      day == null ||
      hour == null ||
      minute == null ||
      second == null ||
      year <= 1900) {
    return null;
  }
  return DateTime(year, month, day, hour, minute, second);
}

/// 获取 [entry] 的排序时间（完整到秒）。
///
/// 必须与 `entryDayKey(entry)` 使用同一来源；不要在相册页/查看页分别实现。
DateTime entrySortDateTime(LivePhotoEntry entry) {
  final exif = _parseExifDateTime(entry.info?.exifDateTimeOriginal);
  if (exif != null) return exif;

  final modified = entry.media.modified;
  if (modified > 0) {
    return DateTime.fromMillisecondsSinceEpoch(modified * 1000);
  }

  final added = entry.media.added;
  if (added > 0) {
    return DateTime.fromMillisecondsSinceEpoch(added * 1000);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

/// 获取 [entry] 的展示分组日期键（本地日历日 `yyyyMMdd`）。
String entryDayKey(LivePhotoEntry entry) {
  final dt = entrySortDateTime(entry);
  return '${dt.year}'
      '${dt.month.toString().padLeft(2, '0')}'
      '${dt.day.toString().padLeft(2, '0')}';
}

/// 返回按排序时间倒序的新列表，保持相对稳定顺序。
///
/// 调用方应在进入相册页前统一调用一次；相册网格和查看页共同消费该列表，
/// 防止两处排序规则以后漂移。
List<LivePhotoEntry> sortLivePhotoEntries(List<LivePhotoEntry> entries) {
  final decorated = List<int>.generate(entries.length, (i) => i);
  decorated.sort((a, b) {
    final result = entrySortDateTime(
      entries[b],
    ).compareTo(entrySortDateTime(entries[a]));
    return result != 0 ? result : a.compareTo(b);
  });
  return decorated.map((i) => entries[i]).toList(growable: false);
}
