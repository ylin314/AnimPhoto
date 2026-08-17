/// 转换页：把单文件动态照片按本机品牌转换为目标格式，写入系统相册。
library;

import 'package:flutter/material.dart';
import '../../core/brand.dart';
import '../../core/motion_photo.dart';
import '../../models/live_photo_entry.dart';
import '../../services/conversion_service.dart';

class ConvertPage extends StatefulWidget {
  const ConvertPage({
    super.key,
    required this.entry,
    required this.deviceBrand,
  });

  final LivePhotoEntry entry;
  final DeviceBrand deviceBrand;

  @override
  State<ConvertPage> createState() => _ConvertPageState();
}

class _ConvertPageState extends State<ConvertPage> {
  late TargetFormat _target;
  late final TextEditingController _nameController;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _target = BrandDetector.targetForDevice(widget.deviceBrand);
    final name = widget.entry.media.fileName;
    final dot = name.lastIndexOf('.');
    _nameController = TextEditingController(
      text: dot > 0 ? name.substring(0, dot) : name,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _convertAndSave() async {
    if (!ConversionService.isStable(_target)) {
      final shouldContinue = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('转换功能尚未开发完毕'),
          content: const Text('该格式的转换功能目前不稳定，可能无法正常转换与播放。是否仍要继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('仍要转换'),
            ),
          ],
        ),
      );
      if (shouldContinue != true || !mounted) return;
    }

    setState(() => _busy = true);
    try {
      final result = await ConversionService.convertAndSave(
        entry: widget.entry,
        target: _target,
        outputStem: _stemText(),
      );
      if (mounted) {
        _showToast(
          result.saved
              ? '已转换并保存到相册「AnimPhoto」：${result.fileName}'
              : '保存到相册失败，请检查权限',
          error: !result.saved,
        );
      }
    } catch (e) {
      if (mounted) _showToast('转换失败：$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showToast(String message, {bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 4),
          backgroundColor: error
              ? scheme.errorContainer
              : scheme.inverseSurface,
          content: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                error
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: error
                    ? scheme.onErrorContainer
                    : scheme.onInverseSurface,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: error
                        ? scheme.onErrorContainer
                        : scheme.onInverseSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  /// 输入名称去掉扩展名，作为文件名主干。
  String _stemText() {
    var s = _nameController.text.trim();
    for (final ext in ['.jpg', '.jpeg', '.JPG', '.JPEG']) {
      if (s.endsWith(ext)) {
        s = s.substring(0, s.length - ext.length);
        break;
      }
    }
    return s.isEmpty ? 'animphoto_${DateTime.now().millisecondsSinceEpoch}' : s;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('转换格式')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('源文件', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(widget.entry.media.fileName),
          const SizedBox(height: 4),
          Text(
            '格式：${widget.entry.formatLabel}'
            '${widget.entry.info?.videoOffset == null ? '' : ' · 视频偏移：${widget.entry.info!.videoOffset}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const Divider(height: 32),
          Text(
            '本机品牌：${widget.deviceBrand.name}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text('转换目标格式', style: Theme.of(context).textTheme.titleSmall),
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
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '保存名称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _busy ? null : _convertAndSave,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.photo_library_outlined),
            label: Text(_busy ? '转换中…' : '转换并保存到相册'),
          ),
        ],
      ),
    );
  }
}
