import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Read-only ranking of household members (week / month / all-time).
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  int _period = 0; // 0 week, 1 month, 2 all
  static const _periods = ['week', 'month', 'all'];
  late Future<List<LeaderEntry>> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final api = context.read<AppState>().api;
    _future = api.leaderboard(_periods[_period]).then((list) => list
        .map((e) => LeaderEntry.fromJson(e as Map<String, dynamic>))
        .toList());
  }

  Future<void> _refresh() async {
    await context.read<AppState>().refresh();
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = app.data;
    final c = context.ch;
    if (data == null) return const Loader();

    return ChPage(
      title: context.t('leaderboard_title'),
      subtitle: context.t('n_members', {'n': data.members.length}),
      onRefresh: _refresh,
      children: [
        Segmented(
          labels: [
            context.t('period_week'),
            context.t('period_month'),
            context.t('period_all')
          ],
          index: _period,
          onChanged: (i) => setState(() {
            _period = i;
            _load();
          }),
        ),
        const SizedBox(height: 16),
        FutureBuilder<List<LeaderEntry>>(
          future: _future,
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.only(top: 40), child: Loader());
            }
            if (snap.hasError) {
              return Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                    child: Text(context.t('lb_error'),
                        style: TextStyle(color: c.textSecondary))),
              );
            }
            final entries = snap.data ?? [];
            return Column(
              children: [
                for (int i = 0; i < entries.length; i++)
                  _LbCard(
                    entry: entries[i],
                    rank: i + 1,
                    period: _period,
                    isCreator: entries[i].id == data.adminMemberId,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _LbCard extends StatelessWidget {
  final LeaderEntry entry;
  final int rank;
  final int period;
  final bool isCreator;
  const _LbCard({
    required this.entry,
    required this.rank,
    required this.period,
    required this.isCreator,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final medal = switch (rank) { 1 => '🥇', 2 => '🥈', 3 => '🥉', _ => '' };
    final pts = period == 2 ? entry.points : entry.periodPts;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Row(
          children: [
            SizedBox(
              width: 30,
              child: medal.isNotEmpty
                  ? Text(medal, style: const TextStyle(fontSize: 22))
                  : Text('$rank',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: c.textFaint)),
            ),
            const SizedBox(width: 8),
            Text(entry.emoji, style: const TextStyle(fontSize: 30)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(entry.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary)),
                    ),
                    if (isCreator) ...[
                      const SizedBox(width: 6),
                      const Text('👑', style: TextStyle(fontSize: 13)),
                    ] else if (entry.isAdmin) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.shield, size: 13, color: c.accent),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(
                      '${levelIcon(entry.points)} ${levelName(entry.points)} · Lv.${levelOf(entry.points)}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: c.accent)),
                  const SizedBox(height: 4),
                  Row(children: [
                    Text('🔥 ${entry.streak}',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: c.flame)),
                    const SizedBox(width: 12),
                    Text('🏅 ${entry.achievements.length}',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: c.textSecondary)),
                  ]),
                  const SizedBox(height: 5),
                  SizedBox(
                    width: 130,
                    child:
                        BarMeter(value: levelProgress(entry.points), height: 5),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('$pts',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: rank == 1 ? c.accent : c.textPrimary)),
                Text(context.t('pts'),
                    style: TextStyle(
                        fontSize: 11,
                        color: c.textFaint,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const CoinDot(size: 12),
                  const SizedBox(width: 3),
                  Text('${entry.coins}',
                      style: TextStyle(fontSize: 12, color: c.textSecondary)),
                ]),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
