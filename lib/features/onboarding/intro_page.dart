/// 首次启动介绍页与「关于瞬影」帮助页。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/log.dart';

const String kIntroNeverShowKey = 'animphoto.intro_never_show';

class IntroPage extends StatefulWidget {
  const IntroPage({super.key, required this.onDone, this.firstLaunch = true});

  final ValueChanged<bool> onDone;
  final bool firstLaunch;

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();
  bool _featuresExpanded = false;

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _copyLog(BuildContext context) async {
    try {
      final path = await logFilePath();
      if (path == null) {
        if (context.mounted) _toast(context, '日志文件不可用');
        return;
      }
      final file = File(path);
      if (!await file.exists()) {
        if (context.mounted) _toast(context, '暂无日志，请先完整扫描一次');
        return;
      }
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      if (text.trim().isEmpty) {
        if (context.mounted) _toast(context, '日志为空，请先完整扫描一次');
        return;
      }
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) _toast(context, '日志已复制');
    } catch (error) {
      if (context.mounted) _toast(context, '复制失败：$error');
    }
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _finish(bool neverShow) async {
    if (neverShow) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kIntroNeverShowKey, true);
    }
    widget.onDone(neverShow);
  }

  Animation<double> _fade(double begin, double end) {
    return CurvedAnimation(
      parent: _entrance,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: theme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarColor: scheme.surface,
      systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        body: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.primaryContainer.withValues(alpha: 0.66),
                      scheme.surface,
                      scheme.surface,
                    ],
                    stops: const [0, 0.48, 1],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
                children: [
                  FadeTransition(
                    opacity: reduceMotion
                        ? const AlwaysStoppedAnimation(1)
                        : _fade(0, 0.55),
                    child: _MemoryHero(animation: _entrance),
                  ),
                  const SizedBox(height: 24),
                  _EntranceSlide(
                    animation: reduceMotion
                        ? const AlwaysStoppedAnimation(1)
                        : _fade(0.2, 0.75),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '让每一张动态照片\n都好好动起来',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            height: 1.18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          '瞬影会找到手机里的动态照片，帮你播放、转换和分享，不再受品牌格式限制。',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.55,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  _EntranceSlide(
                    animation: reduceMotion
                        ? const AlwaysStoppedAnimation(1)
                        : _fade(0.38, 0.9),
                    child: const _QuickBenefits(),
                  ),
                  const SizedBox(height: 26),
                  _EntranceSlide(
                    animation: reduceMotion
                        ? const AlwaysStoppedAnimation(1)
                        : _fade(0.56, 1),
                    child: Column(
                      children: [
                        if (widget.firstLaunch)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                            ),
                            onPressed: () => _finish(true),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: const Text('开始找回鲜活瞬间'),
                          )
                        else ...[
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(54),
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('关闭'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            icon: const Icon(Icons.content_copy_rounded),
                            label: const Text('复制诊断日志'),
                            onPressed: () => _copyLog(context),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _featuresExpanded = !_featuresExpanded,
                          ),
                          icon: Icon(
                            _featuresExpanded
                                ? Icons.expand_less_rounded
                                : Icons.expand_more_rounded,
                          ),
                          label: Text(_featuresExpanded ? '收起功能介绍' : '了解更多功能'),
                        ),
                      ],
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 260),
                    sizeCurve: Curves.easeOutCubic,
                    crossFadeState: _featuresExpanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: _FeatureDetails(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntranceSlide extends StatelessWidget {
  const _EntranceSlide({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) => Opacity(
        opacity: animation.value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - animation.value)),
          child: child,
        ),
      ),
    );
  }
}

class _MemoryHero extends StatelessWidget {
  const _MemoryHero({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 226,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 15,
            right: 18,
            child: Transform.rotate(
              angle: 0.09,
              child: _MemoryTile(
                color: scheme.secondaryContainer,
                icon: Icons.wb_sunny_rounded,
                iconColor: scheme.secondary,
              ),
            ),
          ),
          Positioned(
            top: 29,
            left: 18,
            child: Transform.rotate(
              angle: -0.08,
              child: _MemoryTile(
                color: scheme.tertiaryContainer,
                icon: Icons.landscape_rounded,
                iconColor: scheme.tertiary,
              ),
            ),
          ),
          Container(
            width: 132,
            height: 132,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset('assets/icon/app_icon.png'),
            ),
          ),
          Positioned(
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.2),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.play_arrow_rounded,
                    size: 20,
                    color: scheme.onPrimary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '瞬影 AnimPhoto',
                    style: TextStyle(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemoryTile extends StatelessWidget {
  const _MemoryTile({
    required this.color,
    required this.icon,
    required this.iconColor,
  });

  final Color color;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 118,
      height: 142,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.8),
          width: 5,
        ),
      ),
      child: Icon(icon, color: iconColor, size: 42),
    );
  }
}

class _QuickBenefits extends StatelessWidget {
  const _QuickBenefits();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(
          child: _Benefit(icon: Icons.search_rounded, label: '自动发现'),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _Benefit(
            icon: Icons.play_circle_outline_rounded,
            label: '直接播放',
          ),
        ),
        SizedBox(width: 8),
        Expanded(
          child: _Benefit(icon: Icons.swap_horiz_rounded, label: '一键转换'),
        ),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: theme.colorScheme.primary, size: 25),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureDetails extends StatelessWidget {
  const _FeatureDetails();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        children: [
          _FeatureRow(
            icon: Icons.photo_library_outlined,
            title: '跨品牌识别',
            subtitle: '识别 OPPO、vivo、小米、荣耀、华为等动态照片',
          ),
          Divider(height: 24),
          _FeatureRow(
            icon: Icons.share_outlined,
            title: '分享动态',
            subtitle: '生成网页链接，让对方直接播放和下载',
          ),
          Divider(height: 24),
          _FeatureRow(
            icon: Icons.shield_outlined,
            title: '本机处理',
            subtitle: '扫描、播放与格式转换优先在设备本地完成',
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: theme.colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
