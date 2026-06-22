import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'task_actions.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = app.data;
    final c = context.ch;
    if (data == null) return const Loader();

    final me = data.me;
    final name = me?.name ?? data.currentUser?.username ?? 'there';
    final coins = me?.coins ?? 0;
    final streak = me?.streak ?? 0;
    final pts = me?.points ?? 0;
    final lvl = levelOf(pts);
    final toNext = ptsToNext(pts);

    final dueTasks = data.dueTodayTasks;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: c.accent,
        onRefresh: app.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 96),
          children: [
            // ── Header ──
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: c.accentGradient,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    me?.emoji ?? name.characters.first.toUpperCase(),
                    style: const TextStyle(fontSize: 20, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.t(greetingKey()),
                          style: TextStyle(
                              fontSize: 12, color: c.textSecondary)),
                      Text(name,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: Theme.of(context).brightness == Brightness.light
                        ? const [
                            BoxShadow(
                                color: Color(0x143C2D78),
                                blurRadius: 18,
                                spreadRadius: -10,
                                offset: Offset(0, 8))
                          ]
                        : null,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const CoinDot(size: 15),
                    const SizedBox(width: 6),
                    Text('$coins',
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: c.textPrimary)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Level hero + streak/coin chips ──
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: LevelHeroCard(
                      pts: pts,
                      levelLabel: context.t(
                          'level_label', {'lvl': lvl, 'name': levelName(pts)}),
                      toNextLabel: toNext == null
                          ? context.t('max_level')
                          : context.t(
                              'xp_to_next', {'xp': toNext, 'lvl': lvl + 1}),
                    ),
                  ),
                  const SizedBox(width: 13),
                  SizedBox(
                    width: 96,
                    child: Column(
                      children: [
                        Expanded(
                          child: StatChip(
                            icon: const FlameIcon(),
                            value: '$streak',
                            label: context.t('day_streak'),
                          ),
                        ),
                        const SizedBox(height: 13),
                        Expanded(
                          child: StatChip(
                            icon: const CoinDot(size: 15),
                            value: '$coins',
                            label: context.t('coins_lc'),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFF4CBD8), Color(0xFFEFB9CC)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            valueColor: const Color(0xFF9C3460),
                            labelColor: const Color(0xFFB5557C),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // ── Effort today ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(context.t('daily_goal'),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary)),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('${data.effortToday}',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: c.accent)),
                      Text(' / $kDailyEffortTarget ${context.t('xp')}',
                          style:
                              TextStyle(fontSize: 13, color: c.textSecondary)),
                    ]),
              ],
            ),
            const SizedBox(height: 9),
            BarMeter(value: data.effortToday / kDailyEffortTarget, height: 9),
            const SizedBox(height: 18),

            // ── Stats ──
            AppCard(
              radius: 20,
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: Row(
                children: [
                  _stat(c, '${data.todoCount}', context.t('todo'), c.textPrimary),
                  _divider(c),
                  _stat(c, '${data.doneTodayCount}', context.t('done'), c.accent),
                  _divider(c),
                  _stat(c, '${data.missedTodayCount}', context.t('missed'),
                      c.textPrimary),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // ── Pending approvals ──
            if (data.approvals.isNotEmpty) ...[
              Text(context.t('pending_approvals'),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary)),
              const SizedBox(height: 8),
              for (final a in data.approvals)
                _ApprovalRow(approval: a, data: data),
              const SizedBox(height: 22),
            ],

            // ── Today's tasks ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(context.t('todays_quests'),
                    style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary)),
                Text(context.t('n_total', {'n': dueTasks.length}),
                    style: TextStyle(fontSize: 13, color: c.textSecondary)),
              ],
            ),
            const SizedBox(height: 12),
            if (dueTasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(children: [
                  Icon(Icons.check_circle_outline,
                      size: 40, color: c.textFaint),
                  const SizedBox(height: 8),
                  Text(context.t('all_done_today'),
                      style: TextStyle(color: c.textSecondary)),
                ]),
              )
            else
              for (int i = 0; i < dueTasks.length; i++) ...[
                _TodayRow(task: dueTasks[i]),
                if (i != dueTasks.length - 1) const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  Widget _stat(ChColors c, String value, String label, Color valueColor) {
    return Expanded(
      child: Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: valueColor)),
        const SizedBox(height: 2),
        Text(label.toUpperCase(),
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
                color: c.textFaint)),
      ]),
    );
  }

  Widget _divider(ChColors c) =>
      Container(width: 1, height: 34, color: c.divider);
}

class _ApprovalRow extends StatelessWidget {
  final Approval approval;
  final HouseholdData data;
  const _ApprovalRow({required this.approval, required this.data});

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final app = context.read<AppState>();
    final member = data.memberById(approval.memberId);
    String taskName = '?';
    for (final t in data.tasks) {
      if (t.id == approval.taskId) {
        taskName = t.name;
        break;
      }
    }

    Future<void> act(bool approved) async {
      try {
        await app.approve(approval.id, approved);
        if (context.mounted) {
          showSnack(context, context.t(approved ? 'approved' : 'rejected'));
        }
      } on ApiException catch (e) {
        if (context.mounted) showSnack(context, e.message, error: true);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(member?.emoji ?? '👤', style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(taskName,
                      style: TextStyle(
                          fontWeight: FontWeight.w600, color: c.textPrimary)),
                  Text(
                      context.t('wants_done',
                          {'name': member?.name ?? '?'}),
                      style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
                ],
              ),
            ),
            if (data.amAdmin) ...[
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => act(false),
                icon: const Icon(Icons.close, color: Color(0xFFB3261E)),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => act(true),
                icon: Icon(Icons.check_circle, color: c.accent),
              ),
            ] else
              Text(context.t('pending'),
                  style: TextStyle(fontSize: 12, color: c.textFaint)),
          ],
        ),
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  final Task task;
  const _TodayRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final done = task.doneToday;
    final qi = questIcon(context, task);
    final xp = task.points * 20; // points → xp scale

    return QuestTile(
      icon: qi.icon,
      iconColor: qi.color,
      title: task.name,
      done: done,
      doneLabel: context.t('claimed_xp', {'n': xp}),
      onTap: done ? null : () => completeTaskFlow(context, app, task),
      subtitle: Row(
        children: [
          RewardTags(xp: xp, coins: task.points),
          const SizedBox(width: 7),
          DiffTag(
            diffLevel: task.diffLevel,
            quickLabel: context.t('q_quick'),
            epicLabel: context.t('q_epic'),
          ),
        ],
      ),
    );
  }
}
