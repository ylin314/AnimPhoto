/// 批量格式转换：对选中的多张动态照片逐张转换为目标厂商格式，
/// 保存到系统相册 Pictures/AnimPhoto（与单文件转换一致）。
///
/// 流程：
///   1) 进入格式选择页（默认本机品牌，与现有 ConvertPage 一致）；
///   2) 用户点击转换 → 确认弹窗（是否全部转换）；
///   3) 进入 BatchProgressPage 进度页执行批量转换。
library;

import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../core/motion_photo.dart';
import '../../models/live_photo_entry.dart';
import '../../services/conversion_service.dart';
import 'batch_progress_page.dart';

class BatchConvert {
  BatchConvert._();

  /// 入口：打开格式选择页（不立即执行）。
  static Future<void> start(
    BuildContext context, {
    required List<LivePhotoEntry> entries,
    required DeviceBrand deviceBrand,
  }) async {
    if (entries.isEmpty) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            _BatchConvertConfigPage(entries: entries, deviceBrand: deviceBrand),
      ),
    );
  }
}

/// 批量格式转换的配置页：选择目标格式 + 文件命名策略（保留原名）。
class _BatchConvertConfigPage extends StatefulWidget {
  const _BatchConvertConfigPage({
    required this.entries,
    required this.deviceBrand,
  });

  final List<LivePhotoEntry> entries;
  final DeviceBrand deviceBrand;

  @override
  State<_BatchConvertConfigPage> createState() =>
      _BatchConvertConfigPageState();
}

class _BatchConvertConfigPageState extends State<_BatchConvertConfigPage> {
  late TargetFormat _target;

  @override
  void initState() {
    super.initState();
    // 默认本机品牌（与单文件 ConvertPage 完全一致）
    _target = BrandDetector.targetForDevice(widget.deviceBrand);
  }

  Future<void> _onConvertPressed() async {
    // 非稳定格式提示
    if (!ConversionService.isStable(_target)) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('转换功能尚未开发完毕'),
          content: const Text('该格式的转换功能目前不稳定，可能无法正常转换与播放。是否仍要继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('仍要转换'),
            ),
          ],
        ),
      );
      if (shouldContinue != true || !mounted) return;
    }

    // 批量转换确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量格式转换'),
        content: Text(
          '将对选中的 ${widget.entries.length} 张动态照片全部转换为'
          '「${BrandDetector.targetLabel(_target)}」格式，'
          '并保存到相册「AnimPhoto」。是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('全部转换'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    // 进入进度页（替换当前配置页，避免回退栈过长）
    final target = _target;
    final tasks = <BatchTask>[
      for (final e in widget.entries)
        BatchTask(
          title: e.media.fileName,
          subtitle: '${e.formatLabel} → ${BrandDetector.targetLabel(target)}',
          run: () => _convertOne(e, target),
        ),
    ];
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            BatchProgressPage(kind: BatchKind.convertFormat, tasks: tasks),
      ),
    );
  }

  /// 转换单张并保存到相册；真实流程由 [ConversionService] 统一维护。
  static Future<BatchTaskResult> _convertOne(
    LivePhotoEntry entry,
    TargetFormat target,
  ) async {
    try {
      final result = await ConversionService.convertAndSave(
        entry: entry,
        target: target,
        outputStem: ConversionService.defaultStem(entry),
      );
      return BatchTaskResult(
        ok: result.saved,
        error: result.saved ? null : '保存到相册失败，请检查权限',
      );
    } catch (e) {
      return BatchTaskResult(ok: false, error: '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('批量转换格式')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            '已选中 ${widget.entries.length} 张动态照片',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '本机品牌：${widget.deviceBrand.name}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text('转换目标格式', style: theme.textTheme.titleSmall),
          RadioGroup<TargetFormat>(
            groupValue: _target,
            onChanged: (v) => setState(() => _target = v!),
            child: Column(
              children: TargetFormat.values
                  .map(
                    (t) => RadioListTile<TargetFormat>(
                      title: Text(BrandDetector.targetLabel(t)),
                      value: t,
                    ),
                  )
                  .toList(),
            ),
          ),
          const Divider(height: 32),
          Text(
            '转换后将保存到相册「AnimPhoto」，文件名保持原名。',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _onConvertPressed,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('批量转换并保存'),
          ),
        ],
      ),
    );
  }
}
