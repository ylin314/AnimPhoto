/// 不可跳过的强制更新页。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/update_service.dart';

class MandatoryUpdatePage extends StatefulWidget {
  const MandatoryUpdatePage({
    super.key,
    required this.update,
    this.startUpdate = UpdateService.startUpdate,
  });

  final AppUpdateInfo update;
  final Future<bool> Function(AppUpdateInfo update) startUpdate;

  @override
  State<MandatoryUpdatePage> createState() => _MandatoryUpdatePageState();
}

class _MandatoryUpdatePageState extends State<MandatoryUpdatePage>
    with SingleTickerProviderStateMixin {
  bool _starting = false;
  bool _downloadStarted = false;
  String? _error;
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    HapticFeedback.lightImpact();
    setState(() {
      _starting = true;
      _error = null;
    });
    try {
      final started = await widget.startUpdate(widget.update);
      if (!mounted) return;
      setState(() {
        _downloadStarted = started;
        if (!started) _error = '下载页没有打开，请稍后再试一次。';
      });
    } catch (error) {
      if (mounted) setState(() => _error = '更新失败：$error');
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: theme.brightness == Brightness.dark
              ? Brightness.light
              : Brightness.dark,
        ),
        child: Scaffold(
          extendBodyBehindAppBar: true,
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primaryContainer.withValues(alpha: 0.82),
                        scheme.surface,
                        scheme.secondaryContainer.withValues(alpha: 0.58),
                      ],
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 56,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: AnimatedBuilder(
                                animation: _motion,
                                builder: (context, child) {
                                  final value = reduceMotion
                                      ? 0.5
                                      : _motion.value;
                                  return Transform.translate(
                                    offset: Offset(0, -3 * value),
                                    child: child,
                                  );
                                },
                                child: const _UpdateIllustration(),
                              ),
                            ),
                            const SizedBox(height: 34),
                            Text(
                              '有一份新的瞬影\n等你拆开',
                              style: theme.textTheme.headlineMedium?.copyWith(
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '发现新版本',
                              style: theme.textTheme.bodyLarge?.copyWith(
                                height: 1.55,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 22),
                            _VersionRoute(update: widget.update),
                            if (widget.update.notes.trim().isNotEmpty) ...[
                              const SizedBox(height: 18),
                              _ReleaseNotes(notes: widget.update.notes),
                            ],
                            if (_downloadStarted) ...[
                              const SizedBox(height: 14),
                              _StatusMessage(
                                icon: Icons.check_circle_outline_rounded,
                                color: scheme.secondary,
                                text: '下载页已打开，安装完成后再回来见。',
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 14),
                              _StatusMessage(
                                icon: Icons.info_outline_rounded,
                                color: scheme.error,
                                text: _error!,
                              ),
                            ],
                            const SizedBox(height: 26),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                              ),
                              onPressed: _starting ? null : _update,
                              icon: _starting
                                  ? const SizedBox.square(
                                      dimension: 19,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                      ),
                                    )
                                  : Icon(
                                      _downloadStarted
                                          ? Icons.open_in_new_rounded
                                          : Icons.system_update_alt_rounded,
                                    ),
                              label: Text(
                                _downloadStarted ? '重新打开下载页' : '下载更新',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateIllustration extends StatelessWidget {
  const _UpdateIllustration();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 190,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 8,
            top: 24,
            child: Transform.rotate(
              angle: -0.1,
              child: _PhotoTile(
                color: scheme.secondaryContainer,
                icon: Icons.landscape_rounded,
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 15,
            child: Transform.rotate(
              angle: 0.1,
              child: _PhotoTile(
                color: scheme.primaryContainer,
                icon: Icons.favorite_rounded,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            child: Container(
              width: 66,
              height: 66,
              decoration: BoxDecoration(
                color: scheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: scheme.surface, width: 5),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                Icons.arrow_downward_rounded,
                color: scheme.onPrimary,
                size: 30,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  const _PhotoTile({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 88,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
    );
  }
}

class _VersionRoute extends StatelessWidget {
  const _VersionRoute({required this.update});

  final AppUpdateInfo update;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _VersionLabel(
              caption: '当前版本',
              version: update.currentVersionName,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.arrow_forward_rounded,
              size: 20,
              color: scheme.primary,
            ),
          ),
          Expanded(
            child: _VersionLabel(
              caption: '新版本',
              version: update.latestVersionName,
              alignEnd: true,
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionLabel extends StatelessWidget {
  const _VersionLabel({
    required this.caption,
    required this.version,
    this.alignEnd = false,
  });

  final String caption;
  final String version;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          caption,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          version,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ReleaseNotes extends StatelessWidget {
  const _ReleaseNotes({required this.notes});

  final String notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: scheme.tertiary,
              ),
              const SizedBox(width: 8),
              Text(
                '更新日志',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            notes,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        ],
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.45))),
      ],
    );
  }
}
