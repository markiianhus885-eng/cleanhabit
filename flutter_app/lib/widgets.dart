import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';

/// A small gold coin dot (radial gradient), matching the mockup.
class CoinDot extends StatelessWidget {
  final double size;
  const CoinDot({super.key, this.size = 18});
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [c.coinA, c.coinB],
        ),
      ),
    );
  }
}

/// 1-3 lightning bolts indicating difficulty (easy=1, medium=2, hard=3).
class DifficultyBolts extends StatelessWidget {
  final int level;
  final double size;
  final Color? color;
  const DifficultyBolts({super.key, required this.level, this.size = 12, this.color});
  @override
  Widget build(BuildContext context) {
    final c = color ?? context.ch.star;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        level.clamp(1, 3),
        (_) => Icon(Icons.bolt, size: size, color: c),
      ),
    );
  }
}

/// Rounded card surface used throughout.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.radius = 22,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Theme.of(context).brightness == Brightness.light
            ? [
                BoxShadow(
                  color: const Color(0x0D142819),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                )
              ]
            : null,
      ),
      child: child,
    );
  }
}

/// Circular progress ring with a centered child (e.g. a check icon or %).
class ProgressRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final double stroke;
  final Widget? center;
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 66,
    this.stroke = 7,
    this.center,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          value: value.clamp(0, 1),
          track: c.trackBg,
          accent: c.accent,
          stroke: stroke,
        ),
        child: Center(child: center),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double value;
  final Color track;
  final Color accent;
  final double stroke;
  _RingPainter({
    required this.value,
    required this.track,
    required this.accent,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - stroke) / 2;
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    final accentPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, trackPaint);
    if (value > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        2 * math.pi * value,
        false,
        accentPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.accent != accent || old.track != track;
}

/// Slim horizontal progress bar (effort points, room cleanliness).
class BarMeter extends StatelessWidget {
  final double value; // 0..1
  final double height;
  final Color? fill;
  const BarMeter({super.key, required this.value, this.height = 8, this.fill});
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: height,
        color: c.trackBg,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0, 1),
          child: Container(
            decoration: BoxDecoration(
              color: fill ?? c.accent,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small pill chip (e.g. "+1", "Clean!").
class Pill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final Widget? leading;
  const Pill({
    super.key,
    required this.text,
    required this.bg,
    required this.fg,
    this.leading,
  });
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 6)],
          Text(text,
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: fg)),
        ],
      ),
    );
  }
}

/// Full-screen loading spinner in theme color.
class Loader extends StatelessWidget {
  const Loader({super.key});
  @override
  Widget build(BuildContext context) =>
      Center(child: CircularProgressIndicator(color: context.ch.accent));
}

/// Scrollable page scaffold with a big title header, used by tab screens.
class ChPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final Widget? trailing;
  final Future<void> Function()? onRefresh;
  final EdgeInsetsGeometry padding;
  const ChPage({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.trailing,
    this.onRefresh,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 24),
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final body = ListView(
      padding: padding,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: c.textPrimary,
                          letterSpacing: -0.5)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        const SizedBox(height: 16),
        ...children,
      ],
    );
    return SafeArea(
      bottom: false,
      child: onRefresh != null
          ? RefreshIndicator(color: c.accent, onRefresh: onRefresh!, child: body)
          : body,
    );
  }
}

/// Three-way segmented control (used for leaderboard period, etc.).
class Segmented extends StatelessWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  const Segmented(
      {super.key,
      required this.labels,
      required this.index,
      required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: light ? const Color(0xFFEBEFEC) : c.card,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final sel = i == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  color: sel ? (light ? Colors.white : c.trackBg) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(labels[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                        color: sel ? c.textPrimary : c.textSecondary)),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Themed app bar for pushed detail screens.
AppBar chAppBar(BuildContext context, String title, {List<Widget>? actions}) {
  final c = context.ch;
  return AppBar(
    backgroundColor: c.pageBg,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    foregroundColor: c.textPrimary,
    title: Text(title,
        style: TextStyle(fontWeight: FontWeight.w800, color: c.textPrimary)),
    actions: actions,
  );
}

/// Lightweight snackbar helper.
void showSnack(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? const Color(0xFFB3261E) : context.ch.accent,
      behavior: SnackBarBehavior.floating,
    ));
}
