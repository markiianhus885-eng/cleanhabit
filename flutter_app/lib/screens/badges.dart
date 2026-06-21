import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

const Map<String, String> _catKeys = {
  'First steps': 'cat_first_steps',
  'Day streaks': 'cat_day_streaks',
  'Special': 'cat_special',
};

class BadgesScreen extends StatefulWidget {
  const BadgesScreen({super.key});
  @override
  State<BadgesScreen> createState() => _BadgesScreenState();
}

class _BadgesScreenState extends State<BadgesScreen> {
  String _memberId = 'all';

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppState>().data;
    final c = context.ch;
    if (data == null) {
      return Scaffold(
          backgroundColor: c.pageBg,
          appBar: chAppBar(context, context.t('badges_title')),
          body: const Loader());
    }

    // Earned badge keys for the current filter.
    final Set<String> earned;
    if (_memberId == 'all') {
      earned = {
        for (final m in data.members) ...m.achievements.map((b) => b.key)
      };
    } else {
      final m = data.memberById(_memberId);
      earned = {...?m?.achievements.map((b) => b.key)};
    }

    final categories = <String, List<BadgeDef>>{};
    for (final b in kBadgeCatalog) {
      categories.putIfAbsent(b.category, () => []).add(b);
    }

    return Scaffold(
      backgroundColor: c.pageBg,
      appBar: chAppBar(context, context.t('badges_title')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Row(
              children: [
                Text(context.t('earned'),
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary)),
                const Spacer(),
                Text('${earned.length} / ${kBadgeCatalog.length}',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: c.accent)),
              ],
            ),
            const SizedBox(height: 10),
            BarMeter(value: earned.length / kBadgeCatalog.length, height: 8),
            const SizedBox(height: 16),

            // Member filter
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterChip(c, context.t('all'), 'all'),
                  for (final m in data.members)
                    _filterChip(c, '${m.emoji} ${m.name}', m.id),
                ],
              ),
            ),
            const SizedBox(height: 20),

            for (final entry in categories.entries) ...[
              Text(context.t(_catKeys[entry.key] ?? 'cat_special').toUpperCase(),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: c.textFaint)),
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.55,
                children: entry.value
                    .map((b) => _BadgeTile(def: b, unlocked: earned.contains(b.key)))
                    .toList(),
              ),
              const SizedBox(height: 18),
            ],
          ],
        ),
      ),
    );
  }

  Widget _filterChip(ChColors c, String label, String id) {
    final sel = _memberId == id;
    return GestureDetector(
      onTap: () => setState(() => _memberId = id),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: sel ? c.accent : c.card,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: sel ? Colors.white : c.textSecondary)),
      ),
    );
  }
}

class _BadgeTile extends StatelessWidget {
  final BadgeDef def;
  final bool unlocked;
  const _BadgeTile({required this.def, required this.unlocked});
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return Opacity(
      opacity: unlocked ? 1 : 0.5,
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(def.emoji,
                    style: TextStyle(
                        fontSize: 26,
                        color: unlocked ? null : c.textFaint)),
                const Spacer(),
                Icon(unlocked ? Icons.check_circle : Icons.lock_outline,
                    size: 18, color: unlocked ? c.accent : c.textFaint),
              ],
            ),
            const Spacer(),
            Text(context.t('b_${def.key}_n'),
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary)),
            const SizedBox(height: 1),
            Text(context.t('b_${def.key}_d'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}
