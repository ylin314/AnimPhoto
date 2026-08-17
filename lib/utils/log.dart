/// 统一日志：print 输出（flutter run 附加成功时终端可见）+ 追加写入日志文件
/// （持久化，wireless/附加失败时仍可查看）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

File? _logFile;

Future<File> _ensureLogFile() async {
  final cached = _logFile;
  if (cached != null) return cached;
  final dir = await getApplicationSupportDirectory();
  final f = File('${dir.path}/animphoto.log');
  _logFile = f;
  return f;
}

/// 将任意字符串规范化为合法 UTF-8 文本。
///
/// 日志内容可能包含来自原生层（MediaStore 文件路径、EXIF 数据、异常信息）
/// 的非 UTF-8 字节序列。先编码再解码（allowMalformed）可剔除/替换非法字节，
/// 确保写入磁盘的永远是合法 UTF-8，后续读取不会抛解码异常。
String _sanitize(String input) {
  final bytes = utf8.encode(input);
  return utf8.decode(bytes, allowMalformed: true);
}

void log(String message) {
  final line = _sanitize('[animphoto] $message');
  // ignore: avoid_print
  print(line);
  _append(line);
}

void _append(String line) {
  unawaited(_appendSafely(line));
}

Future<void> _appendSafely(String line) async {
  try {
    final f = await _ensureLogFile();
    final now = DateTime.now().toIso8601String();
    await f.writeAsString('$now $line\n', mode: FileMode.append, flush: true);
  } catch (_) {
    // 忽略目录获取与日志写入失败。
  }
}

/// 清空日志文件（调试用）。
Future<void> clearLog() async {
  try {
    final f = await _ensureLogFile();
    if (await f.exists()) {
      await f.writeAsString('');
    }
  } catch (_) {}
}

/// 日志文件路径（Android 应用私有目录）。
Future<String?> logFilePath() async {
  try {
    final f = await _ensureLogFile();
    return f.path;
  } catch (_) {
    return null;
  }
}
