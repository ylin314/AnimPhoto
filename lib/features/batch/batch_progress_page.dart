/// 批量处理通用进度页。
///
/// 由调用方通过 [BatchJob] 描述一批任务，本页负责：
/// - 显示整体进度条（已完成数 / 总数）；
/// - 列出逐项处理状态（成功 / 失败 + 失败原因）；
/// - 警示用户「转换/提取期间请勿退出 APP」；
/// - 全部结束后展示结果统计（成功 N 张，失败 M 张），并提供「完成」按钮。
///
/// 进度通过 [ValueNotifier] 驱动，后台任务在独立 isolate 之外串行执行
/// （与现有单文件转换保持一致，避免并发文件读写冲突）。
library;

import 'package:flutter/material.dart';

/// 单条批量任务：给定一条源 [LivePhotoEntry]，执行并返回是否成功。
typedef BatchTaskRunner = Future<BatchTaskResult> Function();

/// 单条任务的结果。
class BatchTaskResult {
  const BatchTaskResult({this.ok = true, this.error});
  final bool ok;
  final String? error;
}

/// 一项批量任务（标题 + 可选副标题 + 执行器）。
class BatchTask {
  const BatchTask({required this.title, this.subtitle, required this.run});
  final String title;
  final String? subtitle;
  final BatchTaskRunner run;
}

/// 单条任务在进度页中的展示状态。
class _TaskState {
  _TaskState({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  /// null=未开始 true=成功 false=失败
  bool? ok;
  String? error;
  bool get pending => ok == null;
  bool get running => _running;
  bool _running = false;
}

/// 批量任务的类型（仅用于页面标题/文案）。
enum BatchKind { extractVideo, convertFormat }

class BatchProgressPage extends StatefulWidget {
  const BatchProgressPage({
    super.key,
    required this.kind,
    required this.tasks,
  });

  final BatchKind kind;
  final List<BatchTask> tasks;

  @override
  State<BatchProgressPage> createState() => _BatchProgressPageState();
}

class _BatchProgressPageState extends State<BatchProgressPage> {
  final List<_TaskState> _states = [];
  bool _finished = false;

  String get _title => widget.kind == BatchKind.extractVideo
      ? '批量提取视频'
      : '批量格式转换';

  String get _warning => widget.kind == BatchKind.extractVideo
      ? '正在提取视频，请勿退出 APP…'
      : '正在转换格式，请勿退出 APP…';

  @override
  void initState() {
    super.initState();
    for (final t in widget.tasks) {
      _states.add(_TaskState(title: t.title, subtitle: t.subtitle));
    }
    // 延迟一帧后开始执行，保证页面先渲染出来
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  /// 处理中点击返回：弹确认框，确认后中断并返回上一页。
  Future<void> _confirmExit() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('当前正在处理，退出将中断本次操作。已完成的会保留，未完成的将被跳过。是否退出？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('继续处理'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _run() async {
    for (var i = 0; i < widget.tasks.length; i++) {
      if (!mounted) return;
      setState(() => _states[i]._running = true);
      try {
        final r = await widget.tasks[i].run();
        if (!mounted) return;
        setState(() {
          _states[i]
            .._running = false
            ..ok = r.ok
            ..error = r.error;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _states[i]
            .._running = false
            ..ok = false
            ..error = '$e';
        });
      }
    }
    if (!mounted) return;
    setState(() => _finished = true);
  }

  int get _doneCount =>
      _states.where((s) => s.ok == true || s.ok == false).length;

  int get _failCount => _states.where((s) => s.ok == false).length;

  /// 顶部提示条的文案：
  /// - 处理中：警示「正在…请勿退出 APP」；
  /// - 完成且全部成功：「处理完成」；
  /// - 完成但有失败：「处理完成（N 项失败）」。
  String get _bannerText {
    if (!_finished) return _warning;
    if (_failCount > 0) return '处理完成（$_failCount 项失败）';
    return '处理完成';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _states.length;
    final done = _doneCount;
    final progress = total == 0 ? 0.0 : done / total;

    return PopScope(
      // 处理中禁止系统返回键中断，避免文件写一半被中止；
      // 处理中触发返回时由 _confirmExit 弹确认框兜底。
      canPop: _finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_finished) _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: _finished ? '返回' : '退出',
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_finished) {
                Navigator.of(context).pop();
              } else {
                _confirmExit();
              }
            },
          ),
          title: Text(_title),
          automaticallyImplyLeading: false,
        ),
        body: Column(
          children: [
            // 顶部警示条
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              color: (_finished && _failCount == 0)
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
                  : theme.colorScheme.errorContainer.withValues(alpha: 0.35),
              child: Row(
                children: [
                  Icon(
                    _finished && _failCount == 0
                        ? Icons.check_circle
                        : Icons.warning_amber_rounded,
                    color: (_finished && _failCount == 0)
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _bannerText,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: (_finished && _failCount == 0)
                            ? theme.colorScheme.onPrimaryContainer
                            : theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 进度区
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _finished ? '已完成' : '处理中…',
                        style: theme.textTheme.titleMedium,
                      ),
                      Text('$done / $total'),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: _finished ? 1 : progress),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 逐项列表
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: _states.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final s = _states[i];
                  final leading = s.ok == true
                      ? const Icon(Icons.check_circle,
                          color: Colors.green, size: 22)
                      : s.ok == false
                          ? const Icon(Icons.cancel,
                              color: Colors.red, size: 22)
                          : s.running
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                )
                              : const Icon(Icons.radio_button_unchecked,
                                  size: 22, color: Colors.grey);
                  return ListTile(
                    leading: leading,
                    title: Text(
                      s.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: s.subtitle == null && s.error == null
                        ? null
                        : Text(
                            s.error != null
                                ? '失败：${s.error}'
                                : (s.subtitle ?? ''),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: s.error != null
                                ? TextStyle(color: theme.colorScheme.error,
                                    fontSize: 12)
                                : null,
                          ),
                  );
                },
              ),
            ),
            // 底部按钮
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _finished ? () => Navigator.of(context).pop() : null,
                  child: Text(_finished
                      ? (_failCount > 0
                          ? '完成（成功 ${done - _failCount} · 失败 $_failCount）'
                          : '完成（全部成功）')
                      : '处理中…'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

