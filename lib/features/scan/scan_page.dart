/// 扫描页：按系统相册分组展示本机全部动态照片（带缩略图与扫描缓存）。
/// 支持：前台恢复自动增量扫描、顶部下拉刷新（增量）、全量重扫按钮。
/// 注意：扫描任务通过队列串行执行，防止并发扫描导致进度计数错乱。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/brand.dart';
import '../../models/live_photo_entry.dart';
import '../../services/gallery_scanner.dart';
import '../../utils/log.dart';
import '../onboarding/intro_page.dart';
import 'album_page.dart';
import 'thumbnail_cache.dart';

/// 一个相册分组。
class _Album {
  const _Album(
    this.name,
    this.entries, {
    this.bucketId,
    this.unsupported = false,
  });

  final String name;
  final List<LivePhotoEntry> entries;

  /// MediaStore 相册 ID；null 表示「全部」虚拟相册（不按 bucket 过滤）。
  final String? bucketId;

  /// 是否为「本机不支持的动态照片」特殊虚拟相册。
  final bool unsupported;
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with WidgetsBindingObserver {
  DeviceBrand _deviceBrand = DeviceBrand.other;

  List<LivePhotoEntry>? _entries;
  Object? _error;
  bool _initialLoading = true;

  int _scanned = 0;
  int _total = 0;
  int _found = 0;

  /// 扫描串行化：队列 + 在途/排队计数，防止并发扫描叠加进度计数。
  Future<void> _scanQueue = Future<void>.value();
  int _pendingScans = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialScan();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 后台 → 前台：增量扫描（新增/删除同步）；扫描在途/排队时忽略，避免并发
    if (state == AppLifecycleState.resumed &&
        !_initialLoading &&
        _pendingScans == 0) {
      log('回到前台，执行增量扫描');
      _incrementalScan(notifyOnChange: true);
    }
  }

  /// 提交一次扫描任务到串行队列；返回其结果（失败时抛出）。
  Future<List<LivePhotoEntry>> _runScan({required bool force}) {
    _pendingScans++;
    final future = _scanQueue.then((_) => _doScan(force: force));
    _scanQueue = future.then<void>(
      (_) => _pendingScans--,
      onError: (Object _) => _pendingScans--,
    );
    return future;
  }

  /// 实际执行扫描（保证同一时刻只有一个在执行）。
  Future<List<LivePhotoEntry>> _doScan({required bool force}) async {
    try {
      final result = await GalleryScanner.scan(
        force: force,
        onProgress: (progress) {
          _scanned = progress.scanned;
          _total = progress.total;
          _found = progress.found;
          if (mounted &&
              (progress.scanned == 0 || progress.scanned % 10 == 0)) {
            setState(() {});
          }
        },
      );
      _deviceBrand = result.deviceBrand;
      return result.entries;
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _initialScan({bool force = false}) async {
    try {
      final entries = await _runScan(force: force);
      if (mounted) {
        setState(() {
          _entries = entries;
          _initialLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _initialLoading = false;
        });
      }
    }
  }

  Future<void> _incrementalScan({required bool notifyOnChange}) async {
    final before = _entries?.length ?? 0;
    try {
      final entries = await _runScan(force: false);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _error = null;
      });
      final changed = entries.length != before;
      if (notifyOnChange && changed) {
        _showSnack('已刷新 · 共 ${entries.length} 条动态照片');
      }
    } catch (e) {
      if (mounted && notifyOnChange) {
        _showSnack('刷新失败：$e');
      }
    }
  }

  Future<void> _pullRefresh() async {
    log('下拉刷新（增量扫描）');
    await _incrementalScan(notifyOnChange: true);
  }

  /// 相册详情页下拉刷新：执行增量扫描，仅返回指定相册（bucketId）的条目。
  /// bucketId 为 null 时返回全部动态照片（对应「全部」虚拟相册）。
  Future<List<LivePhotoEntry>> _refreshAlbum(String? bucketId) async {
    final entries = await _runScan(force: false);
    if (!mounted) return const [];
    setState(() => _entries = entries);
    final filtered = _filterByBucket(entries, bucketId);
    log('相册刷新（bucketId=$bucketId）：命中 ${filtered.length} 条');
    return filtered;
  }

  /// 按 bucketId 过滤；null 返回全部。bucketId 为空字符串的条目归入 '__none__'。
  List<LivePhotoEntry> _filterByBucket(
    List<LivePhotoEntry> entries,
    String? bucketId,
  ) {
    if (bucketId == null) return entries;
    return entries.where((e) {
      final id = e.media.bucketId.isEmpty ? '__none__' : e.media.bucketId;
      return id == bucketId;
    }).toList();
  }

  void _forceRescan() {
    setState(() => _initialLoading = true);
    log('用户触发全量重新扫描（忽略现有扫描缓存）');
    _initialScan(force: true);
  }

  Future<void> _confirmForceRescan() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新全盘扫描？'),
        content: const Text('这会忽略现有扫描缓存，重新检查相册中的所有照片，可能需要一些时间。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('开始扫描'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _forceRescan();
    }
  }

  void _openIntro() {
    log('打开「关于瞬影」介绍页');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IntroPage(onDone: _onIntroDone, firstLaunch: false),
      ),
    );
  }

  void _onIntroDone(bool neverShow) {
    // 帮助模式不使用，仅满足签名
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('瞬影'),
        actions: [
          IconButton(
            tooltip: '关于瞬影',
            icon: const Icon(Icons.info_outline),
            onPressed: _openIntro,
          ),
          IconButton(
            tooltip: '全量重新扫描',
            icon: const Icon(Icons.refresh),
            onPressed: _confirmForceRescan,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_initialLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _total > 0
                  ? '扫描中… 已扫描 $_scanned/$_total · 已找到 $_found'
                  : '正在扫描动态照片…',
            ),
          ],
        ),
      );
    }
    if (_error != null && _entries == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_outlined, size: 48),
              const SizedBox(height: 12),
              Text('$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.tonal(
                onPressed: _forceRescan,
                child: const Text('重新扫描'),
              ),
            ],
          ),
        ),
      );
    }
    final entries = _entries ?? const <LivePhotoEntry>[];
    return RefreshIndicator(
      onRefresh: _pullRefresh,
      child: entries.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 200),
                Center(child: Text('未发现动态照片\n下拉可刷新')),
              ],
            )
          : _AlbumsList(
              albums: _groupAlbums(entries),
              deviceBrand: _deviceBrand,
              onRefreshAlbum: _refreshAlbum,
            ),
    );
  }

  /// 按 MediaStore 相册分组（buckets）：
  /// 第一项「本机不支持的动态照片」（特殊虚拟相册，仅含不支持格式），
  /// 第二项「全部动态照片」，之后为各 MediaStore 相册。
  List<_Album> _groupAlbums(List<LivePhotoEntry> entries) {
    // 本机不支持的动态照片（跨所有相册）
    final unsupported = entries
        .where((e) => !isEntrySupportedOnDevice(e, _deviceBrand))
        .toList(growable: false);
    // bucketId 为 null 表示「全部」虚拟相册（刷新时不按 bucket 过滤）。
    final all = _Album('全部动态照片', entries);
    final byBucket = <String, List<LivePhotoEntry>>{};
    final names = <String, String>{};
    for (final e in entries) {
      final id = e.media.bucketId.isEmpty ? '__none__' : e.media.bucketId;
      byBucket.putIfAbsent(id, () => []).add(e);
      names[id] = e.media.bucketName.isEmpty ? '未分类' : e.media.bucketName;
    }
    final rest =
        byBucket.entries
            .map(
              (kv) =>
                  _Album(names[kv.key] ?? '未分类', kv.value, bucketId: kv.key),
            )
            .toList()
          ..sort((a, b) => b.entries.length.compareTo(a.entries.length));
    return [
      // 即使为空也始终展示「本机不支持的动态照片」入口（便于发现功能）
      _Album('本机不支持的动态照片', unsupported, unsupported: true),
      all,
      ...rest,
    ];
  }
}

class _AlbumsList extends StatelessWidget {
  const _AlbumsList({
    required this.albums,
    required this.deviceBrand,
    required this.onRefreshAlbum,
  });

  final List<_Album> albums;
  final DeviceBrand deviceBrand;

  /// 相册详情页下拉刷新回调：传入 bucketId，返回该相册刷新后的条目。
  final Future<List<LivePhotoEntry>> Function(String? bucketId) onRefreshAlbum;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: albums.length,
      itemBuilder: (context, i) {
        final a = albums[i];
        // 「本机不支持的动态照片」特殊虚拟相册：始终展示，
        // 有内容时用首张缩略图 + 张数；无内容时用 app logo + 温柔文案。
        if (a.unsupported) {
          return _UnsupportedAlbumCard(
            album: a,
            deviceBrand: deviceBrand,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlbumPage(
                    title: a.name,
                    entries: a.entries,
                    deviceBrand: deviceBrand,
                    unsupportedAlbum: true,
                    onRefresh: () async {
                      final refreshed = await onRefreshAlbum(null);
                      return refreshed
                          .where(
                            (entry) =>
                                !isEntrySupportedOnDevice(entry, deviceBrand),
                          )
                          .toList(growable: false);
                    },
                  ),
                ),
              );
            },
          );
        }
        final cover = a.entries.first;
        return Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            leading: _Cover(entry: cover),
            title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${a.entries.length} 张动态照片'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlbumPage(
                    title: a.name,
                    entries: a.entries,
                    deviceBrand: deviceBrand,
                    onRefresh: () => onRefreshAlbum(a.bucketId),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// 「本机不支持的动态照片」特殊相册卡片：
/// 前景布局保持固定，仅让背景高光缓慢掠过。
class _UnsupportedAlbumCard extends StatefulWidget {
  const _UnsupportedAlbumCard({
    required this.album,
    required this.deviceBrand,
    required this.onTap,
  });

  final _Album album;
  final DeviceBrand deviceBrand;
  final VoidCallback onTap;

  @override
  State<_UnsupportedAlbumCard> createState() => _UnsupportedAlbumCardState();
}

class _UnsupportedAlbumCardState extends State<_UnsupportedAlbumCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat();

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final has = widget.album.entries.isNotEmpty;
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      color: scheme.primaryContainer.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: scheme.primary.withValues(alpha: 0.24),
          width: 1,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _motion,
          builder: (context, child) {
            final value = reduceMotion ? 0.35 : _motion.value;
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ShimmerPainter(
                      progress: value,
                      color: Colors.white.withValues(alpha: 0.24),
                    ),
                  ),
                ),
                child!,
              ],
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                SizedBox(
                  width: 62,
                  height: 62,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      has
                          ? _Cover(entry: widget.album.entries.first)
                          : const _LogoCover(),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 25,
                          height: 25,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.surface, width: 2),
                          ),
                          child: Icon(
                            has
                                ? Icons.play_arrow_rounded
                                : Icons.check_rounded,
                            size: 16,
                            color: scheme.onPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.album.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        has
                            ? '${widget.album.entries.length} 张照片等待恢复动态'
                            : '你抓住了每一个鲜活瞬间',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onPrimaryContainer.withValues(
                            alpha: 0.78,
                          ),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      has
                          ? Icons.auto_fix_high_rounded
                          : Icons.favorite_outline_rounded,
                      size: 20,
                      color: has ? scheme.secondary : scheme.primary,
                    ),
                    const SizedBox(height: 5),
                    Icon(Icons.chevron_right_rounded, color: scheme.primary),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  const _ShimmerPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * 0.28;
    final x = -width + (size.width + width * 2) * progress;
    final path = Path()
      ..moveTo(x - width, 0)
      ..lineTo(x, 0)
      ..lineTo(x + width, size.height)
      ..lineTo(x, size.height)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.transparent, color, Colors.transparent],
        ).createShader(Rect.fromLTWH(x - width, 0, width * 2, size.height)),
    );
  }

  @override
  bool shouldRepaint(covariant _ShimmerPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// 无不支持照片时的占位封面：APP logo。
class _LogoCover extends StatelessWidget {
  const _LogoCover();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        height: 56,
        child: Container(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Image.asset('assets/icon/app_icon.png', fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.entry});

  final LivePhotoEntry entry;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 56,
        height: 56,
        child: FutureBuilder<Uint8List?>(
          future: ThumbnailCache.get(entry.media.path, max: 240),
          builder: (context, snap) {
            final bytes = snap.data;
            if (bytes == null) {
              return Container(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
      ),
    );
  }
}
