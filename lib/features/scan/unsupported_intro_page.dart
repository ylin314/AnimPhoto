/// 「本机不支持的动态照片」首次进入时的介绍页。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String kUnsupportedIntroNeverShowKey =
    'animphoto.unsupported_intro_never_show';

Future<bool> isUnsupportedIntroDisabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kUnsupportedIntroNeverShowKey) ?? false;
}

class UnsupportedIntroPage extends StatefulWidget {
  const UnsupportedIntroPage({super.key});

  @override
  State<UnsupportedIntroPage> createState() => _UnsupportedIntroPageState();
}

class _UnsupportedIntroPageState extends State<UnsupportedIntroPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  Future<void> _close({bool permanent = false}) async {
    HapticFeedback.lightImpact();
    if (permanent) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kUnsupportedIntroNeverShowKey, true);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
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
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      scheme.primaryContainer.withValues(alpha: 0.72),
                      scheme.surface,
                      scheme.secondaryContainer.withValues(alpha: 0.25),
                    ],
                    stops: const [0, 0.55, 1],
                  ),
                ),
              ),
            ),
            SafeArea(
              bottom: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
                children: [
                  AnimatedBuilder(
                    animation: _motion,
                    builder: (context, child) {
                      final value = reduceMotion ? 0.5 : _motion.value;
                      return Transform.translate(
                        offset: Offset(0, -4 * value),
                        child: child,
                      );
                    },
                    child: const _FormatBridgeIllustration(),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    '有些瞬间，\n只发生了一次。',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.75,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const _EmotionalCopy(),
                  const SizedBox(height: 26),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                    ),
                    onPressed: () => _close(permanent: true),
                    icon: const Icon(Icons.auto_fix_high_rounded),
                    label: const Text('探寻封存的鲜活动态'),
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

class _FormatBridgeIllustration extends StatelessWidget {
  const _FormatBridgeIllustration();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 214,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 10,
            child: _PhoneFrame(
              label: '来自另一部手机',
              color: scheme.secondaryContainer,
              icon: Icons.image_rounded,
              iconColor: scheme.secondary,
            ),
          ),
          Positioned(
            right: 10,
            child: _PhoneFrame(
              label: '在本机鲜活播放',
              color: scheme.primaryContainer,
              icon: Icons.play_arrow_rounded,
              iconColor: scheme.primary,
            ),
          ),
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: scheme.surface,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Icon(
              Icons.arrow_forward_rounded,
              color: scheme.primary,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({
    required this.label,
    required this.color,
    required this.icon,
    required this.iconColor,
  });

  final String label;
  final Color color;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 118,
          height: 164,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: iconColor, size: 44),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 130,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmotionalCopy extends StatelessWidget {
  const _EmotionalCopy();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '他按下快门的那一刻，\n'
          '风正好吹过，笑声刚刚落下，\n'
          '而你，就在画面里。',
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.75,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '可当它来到你的手机，\n'
          '却只剩一帧静止——\n'
          '鲜活的，变成了沉默的。',
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.75,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '别让那些被认真记录的鲜活，\n在你这里失去声音。',
          style: theme.textTheme.bodyLarge?.copyWith(
            height: 1.75,
            color: scheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
