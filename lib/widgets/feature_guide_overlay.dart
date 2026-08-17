import 'package:flutter/material.dart';

enum GuideTargetGesture { tap, longPress }

class FeatureGuideOverlay extends StatefulWidget {
  const FeatureGuideOverlay({
    super.key,
    required this.targetKey,
    required this.title,
    required this.message,
    this.stepText,
    this.onBackgroundTap,
    this.onTargetAction,
    this.targetGesture = GuideTargetGesture.tap,
    this.accentColor,
    this.dismissOnBackgroundTap = false,
  });

  final GlobalKey targetKey;
  final String title;
  final String message;
  final String? stepText;
  final VoidCallback? onBackgroundTap;
  final VoidCallback? onTargetAction;
  final GuideTargetGesture targetGesture;
  final Color? accentColor;
  final bool dismissOnBackgroundTap;

  @override
  State<FeatureGuideOverlay> createState() => _FeatureGuideOverlayState();
}

class _FeatureGuideOverlayState extends State<FeatureGuideOverlay> {
  Rect? _targetRect;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(covariant FeatureGuideOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetKey != widget.targetKey ||
        oldWidget.title != widget.title) {
      _targetRect = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  void _measure() {
    if (!mounted) return;
    final target = widget.targetKey.currentContext?.findRenderObject();
    final overlay = context.findRenderObject();
    if (target is! RenderBox || overlay is! RenderBox || !target.hasSize) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      return;
    }
    final topLeft = target.localToGlobal(Offset.zero, ancestor: overlay);
    setState(() => _targetRect = topLeft & target.size);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final rect = _targetRect;
    final scheme = Theme.of(context).colorScheme;
    final accent = widget.accentColor ?? scheme.primary;
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onBackgroundTap == null
                    ? () {}
                    : () {
                        widget.onBackgroundTap!();
                        if (widget.dismissOnBackgroundTap && mounted) {
                          setState(() => _dismissed = true);
                        }
                      },
                child: CustomPaint(
                  painter: _GuidePainter(target: rect, accent: accent),
                ),
              ),
            ),
            if (rect != null && widget.onTargetAction != null)
              Positioned.fromRect(
                rect: rect.inflate(8),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.targetGesture == GuideTargetGesture.tap
                      ? widget.onTargetAction
                      : null,
                  onLongPress:
                      widget.targetGesture == GuideTargetGesture.longPress
                      ? widget.onTargetAction
                      : null,
                ),
              ),
            _GuideMessage(
              target: rect,
              title: widget.title,
              message: widget.message,
              stepText: widget.stepText,
              accent: accent,
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideMessage extends StatelessWidget {
  const _GuideMessage({
    required this.target,
    required this.title,
    required this.message,
    required this.stepText,
    required this.accent,
  });

  final Rect? target;
  final String title;
  final String message;
  final String? stepText;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final targetBelowCenter = (target?.center.dy ?? 0) > size.height * 0.52;
    return Positioned(
      left: 20,
      right: 20,
      top: targetBelowCenter ? 92 : null,
      bottom: targetBelowCenter ? null : 42,
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (stepText != null) ...[
                Text(
                  stepText!,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter({required this.target, required this.accent});

  final Rect? target;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Path()..addRect(Offset.zero & size);
    if (target != null) {
      overlay.addRRect(
        RRect.fromRectAndRadius(target!.inflate(8), const Radius.circular(12)),
      );
      overlay.fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(
      overlay,
      Paint()..color = Colors.black.withValues(alpha: 0.72),
    );
    if (target != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(target!.inflate(8), const Radius.circular(12)),
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GuidePainter oldDelegate) =>
      oldDelegate.target != target || oldDelegate.accent != accent;
}
