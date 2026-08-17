/// 大文件分块 IO 工具（禁止一次性读入 >64MB，见 AGENT.md 7.4）。
library;

import 'dart:io';

class FileIo {
  FileIo._();

  static const int chunkSize = 1 << 20; // 1 MiB

  /// 把 [srcPath] 的 [start, end) 区间分块复制到 [dstPath]（新建）。
  static Future<void> copyRange(String srcPath, String dstPath, int start, int end) async {
    final src = await File(srcPath).open();
    final dstFile = File(dstPath);
    await dstFile.parent.create(recursive: true);
    final dst = await dstFile.open(mode: FileMode.write);
    try {
      await src.setPosition(start);
      var pos = start;
      while (pos < end) {
        final len = (end - pos) < chunkSize ? (end - pos) : chunkSize;
        final buf = await src.read(len);
        if (buf.isEmpty) break;
        await dst.writeFrom(buf);
        pos += buf.length;
      }
    } finally {
      await dst.close();
      await src.close();
    }
  }
}
