import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'models.dart';
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
            ? const [
                BoxShadow(
                  color: Color(0x1F3C2D78),
                  blurRadius: 26,
                  spreadRadius: -16,
                  offset: Offset(0, 14),
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
  final Gradient? gradient;
  final Color? track;
  const BarMeter({
    super.key,
    required this.value,
    this.height = 8,
    this.fill,
    this.gradient,
    this.track,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: height,
        color: track ?? c.trackBg,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: value.clamp(0, 1),
          child: Container(
            decoration: BoxDecoration(
              color: gradient == null ? (fill ?? c.accent) : null,
              gradient: gradient,
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

// ─────────────────────────────────────────────────────────────────────
// Playful gamified components
// ─────────────────────────────────────────────────────────────────────

/// Indigo gradient surface with a soft decorative circle in the corner.
/// Used by the level hero, daily-goal banner and reward cards.
class GradientHero extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  const GradientHero({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = 26,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return Container(
      decoration: BoxDecoration(
        gradient: c.accentGradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: c.accentGradB.withValues(alpha: 0.45),
            blurRadius: 30,
            spreadRadius: -14,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: [
            Positioned(
              top: -30,
              right: -18,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// The level + XP hero card. [pts] are the member's lifetime points.
class LevelHeroCard extends StatelessWidget {
  final int pts;
  final String levelLabel; // e.g. "Level 7 · Champion"
  final String toNextLabel; // e.g. "160 xp to level 8" (already localized)
  const LevelHeroCard({
    super.key,
    required this.pts,
    required this.levelLabel,
    required this.toNextLabel,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final white = c.onAccent;
    return GradientHero(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(levelLabel,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: white.withValues(alpha: 0.85))),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$pts',
                  style: TextStyle(
                      fontSize: 40,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: white)),
              const SizedBox(width: 5),
              Text('xp',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: white.withValues(alpha: 0.85))),
            ],
          ),
          const SizedBox(height: 6),
          Text(toNextLabel,
              style: TextStyle(
                  fontSize: 11.5, color: white.withValues(alpha: 0.78))),
          const SizedBox(height: 10),
          BarMeter(
            value: levelProgress(pts),
            height: 7,
            gradient: c.xpGradient,
            track: Colors.black.withValues(alpha: 0.18),
          ),
        ],
      ),
    );
  }
}

/// Small stat tile (streak / coins). Optionally tinted with a gradient.
class StatChip extends StatelessWidget {
  final Widget icon;
  final String value;
  final String label;
  final Gradient? gradient;
  final Color? valueColor;
  final Color? labelColor;
  const StatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.gradient,
    this.valueColor,
    this.labelColor,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
      decoration: BoxDecoration(
        color: gradient == null ? c.card : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: gradient == null &&
                Theme.of(context).brightness == Brightness.light
            ? const [
                BoxShadow(
                    color: Color(0x143C2D78),
                    blurRadius: 22,
                    spreadRadius: -14,
                    offset: Offset(0, 10))
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            icon,
            const SizedBox(width: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: valueColor ?? c.textPrimary)),
          ]),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: labelColor ?? c.textFaint)),
        ],
      ),
    );
  }
}

/// Flame glyph for streaks.
class FlameIcon extends StatelessWidget {
  final double size;
  const FlameIcon({super.key, this.size = 15});
  @override
  Widget build(BuildContext context) =>
      Icon(Icons.local_fire_department_rounded,
          size: size, color: context.ch.flame);
}

/// The +XP / +coins reward row shown under a quest title.
class RewardTags extends StatelessWidget {
  final int xp;
  final int coins;
  const RewardTags({super.key, required this.xp, required this.coins});
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('+$xp xp',
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: c.successPillText)),
      const SizedBox(width: 8),
      CoinDot(size: 10),
      const SizedBox(width: 3),
      Text('+$coins',
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: c.star)),
    ]);
  }
}

/// ⚡ quick / 🔥 epic difficulty tag.
class DiffTag extends StatelessWidget {
  final int diffLevel; // 1 easy, 2 medium, 3 hard
  final String quickLabel;
  final String epicLabel;
  const DiffTag({
    super.key,
    required this.diffLevel,
    required this.quickLabel,
    required this.epicLabel,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final epic = diffLevel >= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: epic ? c.epicBg : c.quickBg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(epic ? '🔥 $epicLabel' : '⚡ $quickLabel',
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: epic ? c.epicFg : c.quickFg)),
    );
  }
}

/// Maps a task to a representative line icon + tint for its quest tile.
({IconData icon, Color color}) questIcon(BuildContext context, Task task) {
  final c = context.ch;
  switch (task.diff) {
    case 'hard':
      return (icon: Icons.cleaning_services_rounded, color: c.epicFg);
    case 'medium':
      return (icon: Icons.auto_awesome_rounded, color: const Color(0xFF4D8DE8));
    default:
      return (icon: Icons.checkroom_rounded, color: const Color(0xFF7C5CFF));
  }
}

/// A single quest (task) row card with icon tile, reward tags and a trailing
/// action (incomplete ring, done check, or a "go" button).
class QuestTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget? subtitle; // reward tags + diff tag
  final bool done;
  final String? doneLabel; // "claimed +40 xp 🎉"
  final Widget? trailing; // overrides the default ring/check
  final VoidCallback? onTap;
  const QuestTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.done = false,
    this.doneLabel,
    this.trailing,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: done ? c.successPillBg : c.card,
          borderRadius: BorderRadius.circular(20),
          boxShadow: !done && Theme.of(context).brightness == Brightness.light
              ? const [
                  BoxShadow(
                      color: Color(0x1A3C2D78),
                      blurRadius: 24,
                      spreadRadius: -18,
                      offset: Offset(0, 12))
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? c.successPillBg : c.iconTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon,
                  size: 22, color: done ? c.successPillText : iconColor),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: done ? c.textFaint : c.textPrimary,
                        decoration: done
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                      )),
                  const SizedBox(height: 3),
                  if (done && doneLabel != null)
                    Text(doneLabel!,
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: c.successPillText))
                  else if (subtitle != null)
                    subtitle!,
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                (done
                    ? Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                            color: Color(0xFF16C172), shape: BoxShape.circle),
                        child: const Icon(Icons.check,
                            size: 17, color: Colors.white))
                    : Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: c.trackBg, width: 2.5),
                        ),
                      )),
          ],
        ),
      ),
    );
  }
}

/// Rounded gradient "+" button for screen headers (replaces floating FABs).
class HeaderAddButton extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  const HeaderAddButton({super.key, required this.onTap, this.icon = Icons.add});
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: c.accentGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: c.accentGradB.withValues(alpha: 0.5),
                blurRadius: 16,
                spreadRadius: -6,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Icon(icon, color: c.onAccent, size: 24),
      ),
    );
  }
}

/// Small solid "go" action button used on quest tiles.
class GoButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const GoButton({super.key, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          gradient: c.accentGradient,
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
                color: c.accentGradB.withValues(alpha: 0.5),
                blurRadius: 14,
                spreadRadius: -6,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: c.onAccent)),
      ),
    );
  }
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
