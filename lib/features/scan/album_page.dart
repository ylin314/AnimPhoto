/// 相册详情页：按日期分组、网格缩略图展示该相册内的动态照片；点击进入照片查看页。
/// 支持下拉刷新（仅刷新当前相册）。
/// 支持长按图片进入多选模式：批量提取视频、批量格式转换、删除、全选。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../utils/feature_guide_prefs.dart';
import '../../widgets/feature_guide_overlay.dart';
import '../batch/batch_convert.dart';
import '../batch/batch_extract.dart';
import '../../platform/media_scan.dart';
import '../viewer/photo_viewer_page.dart';
import 'live_photo_order.dart';
import '../../models/live_photo_entry.dart';
import 'thumbnail_cache.dart';
import 'unsupported_intro_page.dart';

class AlbumPage extends StatefulWidget {
  const AlbumPage({
    super.key,
    required this.title,
    required this.entries,
    required this.deviceBrand,
    this.onRefresh,
    this.unsupportedAlbum = false,
  });

  final String title;
  final List<LivePhotoEntry> entries;
  final DeviceBrand deviceBrand;

  /// 下拉刷新回调：返回当前相册刷新后的条目列表；null 表示不支持刷新。
  /// 由 ScanPage 提供，内部执行仅针对本相册的增量扫描。
  final Future<List<LivePhotoEntry>> Function()? onRefresh;

  /// 是否为「本机不支持的动态照片」特殊相册：首次进入展示温柔宣传页。
  final bool unsupportedAlbum;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

/// 某一天的分组。
class _DayGroup {
  _DayGroup(this.dateKey, this.label, this.items);

  /// 日期键，用于排序与去重（`yyyyMMdd`）。
  final String dateKey;

  /// 显示标签（「今天」「昨天」或「yyyy年M月d日」）。
  final String label;

  /// 该天的条目（与查看页使用同一排序）。
  final List<LivePhotoEntry> items;
}

class _AlbumPageState extends State<AlbumPage> {
  late List<LivePhotoEntry> _entries = widget.entries;
  final GlobalKey _firstTileGuideKey = GlobalKey();
  final GlobalKey _selectAllGuideKey = GlobalKey();
  final GlobalKey _extractGuideKey = GlobalKey();
  final GlobalKey _convertGuideKey = GlobalKey();
  final GlobalKey _deleteGuideKey = GlobalKey();

  /// 是否处于多选模式。
  bool _selecting = false;
  _MultiSelectGuideStage? _guideStage;
  bool _actionsGuideCompleted = false;

  /// 选中条目的媒体路径集合（用路径去重，与条目一一对应）。
  final Set<String> _selectedPaths = {};

  bool get _allSelected =>
      _selectedPaths.length == _entries.length && _entries.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadMultiSelectGuide();
    if (widget.unsupportedAlbum) {
      _maybeShowIntro();
    }
  }

  Future<void> _loadMultiSelectGuide() async {
    final used = await isFeatureGuideCompleted(kMultiSelectUsedKey);
    final actionsCompleted = await isFeatureGuideCompleted(
      kMultiSelectActionsGuideCompletedKey,
    );
    if (!mounted) return;
    setState(() {
      _actionsGuideCompleted = actionsCompleted;
      if (!used && _entries.isNotEmpty) {
        _guideStage = _MultiSelectGuideStage.enter;
      }
    });
  }

  /// 首次（且未永久关闭）进入「本机不支持的动态照片」时自动展示温柔宣传页。
  Future<void> _maybeShowIntro() async {
    final disabled = await isUnsupportedIntroDisabled();
    if (disabled) return;
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const UnsupportedIntroPage(),
          fullscreenDialog: false,
        ),
      );
    });
  }

  /// 右上角按钮：随时重新进入宣传页。
  void _reopenIntro() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const UnsupportedIntroPage()));
  }

  /// 将条目按天分组，返回按日期倒序排列的分组列表。
  List<_DayGroup> _groupByDay() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    // 排序规则在 live_photo_order.dart 中与查看页共用。
    final sorted = sortLivePhotoEntries(_entries);

    // 按日期键聚合；列表本身已倒序，组内同样保持最新在前。
    final byKey = <String, List<LivePhotoEntry>>{};
    final keyOrder = <String>[];
    for (final entry in sorted) {
      final key = entryDayKey(entry);
      byKey
          .putIfAbsent(key, () {
            keyOrder.add(key);
            return [];
          })
          .add(entry);
    }

    final groups = <_DayGroup>[];
    for (final key in keyOrder) {
      final items = byKey[key]!;
      final dt = entrySortDateTime(items.first);
      final dayOnly = DateTime(dt.year, dt.month, dt.day);
      String label;
      if (dayOnly == today) {
        label = '今天';
      } else if (dayOnly == yesterday) {
        label = '昨天';
      } else {
        label = '${dt.year}年${dt.month}月${dt.day}日';
      }
      groups.add(_DayGroup(key, label, items));
    }
    return groups;
  }

  void _openViewer(LivePhotoEntry entry) {
    if (_selecting) return; // 多选模式下不进入查看页
    // 网格展示与查看页左右滑动都基于这个已排序列表，保证顺序一致。
    final entries = sortLivePhotoEntries(_entries);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewerPage(
          entries: entries,
          initialIndex: entries.indexOf(entry),
          deviceBrand: widget.deviceBrand,
        ),
      ),
    );
  }

  /// 长按进入多选模式并选中该条目。
  void _enterSelecting(String path) {
    setState(() {
      _selecting = true;
      _selectedPaths
        ..clear()
        ..add(path);
      if (!_actionsGuideCompleted) {
        _guideStage = _MultiSelectGuideStage.selectAll;
      }
    });
    markFeatureGuideCompleted(kMultiSelectUsedKey);
  }

  /// 退出多选模式。
  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selectedPaths.clear();
    });
  }

  /// 切换某条目的选中状态。
  void _toggleSelect(String path) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (_selectedPaths.isEmpty) {
          _selecting = false;
        }
      } else {
        _selectedPaths.add(path);
      }
    });
  }

  /// 全选 / 取消全选。
  void _toggleSelectAll() {
    setState(() {
      if (_allSelected) {
        _selectedPaths.clear();
      } else {
        _selectedPaths
          ..clear()
          ..addAll(_entries.map((e) => e.media.path));
      }
    });
  }

  void _advanceMultiSelectGuide() {
    switch (_guideStage) {
      case _MultiSelectGuideStage.selectAll:
        setState(() => _guideStage = _MultiSelectGuideStage.extract);
      case _MultiSelectGuideStage.extract:
        setState(() => _guideStage = _MultiSelectGuideStage.convert);
      case _MultiSelectGuideStage.convert:
        setState(() => _guideStage = _MultiSelectGuideStage.delete);
      case _MultiSelectGuideStage.delete:
        setState(() {
          _guideStage = null;
          _actionsGuideCompleted = true;
        });
        markFeatureGuideCompleted(kMultiSelectActionsGuideCompletedKey);
      case _MultiSelectGuideStage.enter:
      case null:
        break;
    }
  }

  /// 获取当前选中的条目（保持 _entries 中的顺序）。
  List<LivePhotoEntry> get _selectedEntries => _entries
      .where((e) => _selectedPaths.contains(e.media.path))
      .toList(growable: false);

  /// 批量提取视频。
  Future<void> _batchExtract() async {
    final selected = _selectedEntries;
    if (selected.isEmpty) return;
    await BatchExtract.start(
      context,
      entries: selected,
      deviceBrand: widget.deviceBrand,
    );
    if (mounted) _exitSelecting();
  }

  /// 批量格式转换。
  Future<void> _batchConvert() async {
    final selected = _selectedEntries;
    if (selected.isEmpty) return;
    await BatchConvert.start(
      context,
      entries: selected,
      deviceBrand: widget.deviceBrand,
    );
    // 批量转换会进入配置页 → 进度页；退出多选由返回后统一处理
    if (mounted) _exitSelecting();
  }

  /// 删除选中的动态照片；先弹窗二次确认，再逐项调用系统媒体库删除。
  Future<void> _deleteSelected() async {
    final selected = _selectedEntries;
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除选中照片？'),
        content: Text('将删除 ${selected.length} 张动态照片，删除后无法恢复。系统可能还会要求你确认本次删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DeleteProgressDialog(total: selected.length),
    );

    final ids = selected
        .map((entry) => entry.media.id)
        .where((id) => id > 0)
        .toList(growable: false);
    int deleted;
    try {
      deleted = ids.isEmpty ? 0 : await MediaScanService.deleteImages(ids);
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
    final failed = selected.length - deleted;

    if (!mounted) return;
    if (deleted > 0) {
      await _handleRefresh();
    }
    if (!mounted) return;
    if (failed == 0) {
      _exitSelecting();
      _showSnack('已删除 $deleted 张照片');
    } else {
      _showSnack('已删除 $deleted 张，$failed 张删除失败');
    }
  }

  Future<void> _handleRefresh() async {
    final onRefresh = widget.onRefresh;
    if (onRefresh == null) return;
    try {
      final fresh = await onRefresh();
      if (!mounted) return;
      final before = _entries.length;
      setState(() => _entries = fresh);
      if (fresh.length != before) {
        _showSnack('已刷新 · 共 ${fresh.length} 张动态照片');
      }
    } catch (e) {
      if (mounted) {
        _showSnack('刷新失败：$e');
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 单个日期分组的网格网格代理（所有组共享同一列数）。
  SliverGridDelegate get _gridDelegate =>
      const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      );

  @override
  Widget build(BuildContext context) {
    final groups = _groupByDay();
    final theme = Theme.of(context);
    final firstGuidePath = groups.isEmpty
        ? null
        : groups.first.items.first.media.path;
    return Stack(
      children: [
        Scaffold(
          appBar: _buildAppBar(),
          body: RefreshIndicator(
            onRefresh: _handleRefresh,
            child: _entries.isEmpty
                // 无内容时的占位（主要面向「本机不支持的动态照片」空态）
                ? _buildEmptyBody(theme)
                : CustomScrollView(
                    // AlwaysScrollableScrollPhysics 保证内容不足一屏时仍可下拉触发刷新。
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      for (final g in groups) ...[
                        // 日期标题
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
                            child: Text(
                              g.label,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        // 该日期下的照片网格
                        SliverGrid(
                          gridDelegate: _gridDelegate,
                          delegate: SliverChildBuilderDelegate((context, i) {
                            final item = g.items[i];
                            return _Tile(
                              guideTargetKey: item.media.path == firstGuidePath
                                  ? _firstTileGuideKey
                                  : null,
                              entry: item,
                              selected: _selectedPaths.contains(
                                item.media.path,
                              ),
                              selecting: _selecting,
                              onTap: () {
                                if (_selecting) {
                                  _toggleSelect(item.media.path);
                                } else {
                                  _openViewer(item);
                                }
                              },
                              onLongPress: () {
                                if (!_selecting) {
                                  _enterSelecting(item.media.path);
                                }
                              },
                            );
                          }, childCount: g.items.length),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
        if (_guideStage != null) _buildMultiSelectGuide(),
      ],
    );
  }

  Widget _buildMultiSelectGuide() {
    return switch (_guideStage!) {
      _MultiSelectGuideStage.enter => FeatureGuideOverlay(
        targetKey: _firstTileGuideKey,
        title: '试试多选照片',
        message: '长按任意一张照片即可进入多选，批量提取视频、转换格式或删除。',
        stepText: '长按照片继续',
        targetGesture: GuideTargetGesture.longPress,
        onTargetAction: () => _enterSelecting(_entries.first.media.path),
      ),
      _MultiSelectGuideStage.selectAll => FeatureGuideOverlay(
        targetKey: _selectAllGuideKey,
        title: '全选',
        message: '点击这里可以一次选中当前相册里的全部照片。',
        stepText: '1 / 4 · 点击屏幕继续',
        onBackgroundTap: _advanceMultiSelectGuide,
      ),
      _MultiSelectGuideStage.extract => FeatureGuideOverlay(
        targetKey: _extractGuideKey,
        title: '批量提取视频',
        message: '把选中动态照片中的视频一次性导出到相册。',
        stepText: '2 / 4 · 点击屏幕继续',
        onBackgroundTap: _advanceMultiSelectGuide,
      ),
      _MultiSelectGuideStage.convert => FeatureGuideOverlay(
        targetKey: _convertGuideKey,
        title: '批量转换格式',
        message: '把选中的动态照片批量转换为本机相册支持的格式。',
        stepText: '3 / 4 · 点击屏幕继续',
        onBackgroundTap: _advanceMultiSelectGuide,
      ),
      _MultiSelectGuideStage.delete => FeatureGuideOverlay(
        targetKey: _deleteGuideKey,
        title: '删除选中照片',
        message: '删除前会弹出确认窗口；确认后才会从系统相册移除选中照片。',
        stepText: '4 / 4 · 点击屏幕完成',
        onBackgroundTap: _advanceMultiSelectGuide,
      ),
    };
  }

  /// 空态占位：温柔文案（面向「本机不支持的动态照片」无内容时）。
  Widget _buildEmptyBody(ThemeData theme) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: Image.asset(
              'assets/icon/app_icon.png',
              width: 96,
              height: 96,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              '你抓住了每一个鲜活瞬间\n'
              '本机相册已支持你手机里所有的动态照片',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.8,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 根据是否多选构建不同的 AppBar。
  PreferredSizeWidget _buildAppBar() {
    if (!_selecting) {
      return AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.unsupportedAlbum)
            IconButton(
              tooltip: '查看说明',
              icon: const Icon(Icons.favorite_outline),
              onPressed: _reopenIntro,
            ),
          Text('${_entries.length} 张'),
          const SizedBox(width: 16),
        ],
      );
    }

    // 多选模式顶栏
    return AppBar(
      leading: IconButton(
        tooltip: '退出多选',
        icon: const Icon(Icons.close),
        onPressed: _exitSelecting,
      ),
      title: Text('已选 ${_selectedPaths.length} 项'),
      actions: [
        // 全选
        IconButton(
          key: _selectAllGuideKey,
          tooltip: _allSelected ? '取消全选' : '全选',
          icon: Icon(
            _allSelected ? Icons.deselect_outlined : Icons.select_all_outlined,
          ),
          onPressed: _toggleSelectAll,
        ),
        // 批量提取视频
        IconButton(
          key: _extractGuideKey,
          tooltip: '全部提取视频',
          icon: const Icon(Icons.movie_outlined),
          onPressed: _selectedPaths.isEmpty ? null : () => _batchExtract(),
        ),
        // 批量格式转换
        IconButton(
          key: _convertGuideKey,
          tooltip: '全部格式转换',
          icon: const Icon(Icons.swap_horiz),
          onPressed: _selectedPaths.isEmpty ? null : () => _batchConvert(),
        ),
        // 删除选中照片
        IconButton(
          key: _deleteGuideKey,
          tooltip: '删除选中照片',
          icon: const Icon(Icons.delete_outline),
          onPressed: _selectedPaths.isEmpty ? null : _deleteSelected,
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _DeleteProgressDialog extends StatelessWidget {
  const _DeleteProgressDialog({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Text(
              '正在删除 $total 张照片，请稍候…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    this.guideTargetKey,
    required this.entry,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
  });

  final GlobalKey? guideTargetKey;
  final LivePhotoEntry entry;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: guideTargetKey,
      child: InkWell(
        key: ValueKey('album-tile-${entry.media.path}'),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<Uint8List?>(
              future: ThumbnailCache.get(entry.media.path, max: 240),
              builder: (context, snap) {
                final bytes = snap.data;
                if (bytes == null) {
                  return Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.image_outlined),
                  );
                }
                return Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.low,
                );
              },
            ),
            // 选中状态遮罩
            if (selected)
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.35),
                ),
              ),
            // 选中标记（左上角勾选圈）
            if (selecting)
              Positioned(
                left: 6,
                top: 6,
                child: Container(
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    selected ? Icons.check : Icons.circle_outlined,
                    size: 18,
                    color: selected
                        ? Theme.of(context).colorScheme.onPrimary
                        : Colors.white,
                  ),
                ),
              ),
            // 动态照片角标（非多选模式时显示）
            if (!selecting)
              Positioned(
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.motion_photos_on,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _MultiSelectGuideStage { enter, selectAll, extract, convert, delete }
