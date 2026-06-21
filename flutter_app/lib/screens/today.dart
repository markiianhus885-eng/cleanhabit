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
    final avg = data.avgCleanliness;
    final leader = data.members.isNotEmpty && data.members.first.points > 0
        ? data.members.first
        : null;

    final dueTasks = data.dueTodayTasks;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: c.accent,
        onRefresh: app.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
          children: [
            // ── Header ──
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    me?.emoji ?? name.characters.first.toUpperCase(),
                    style: const TextStyle(fontSize: 22, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.t(greetingKey()),
                          style:
                              TextStyle(fontSize: 13, color: c.textSecondary)),
                      Text(name,
                          style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const CoinDot(),
                    const SizedBox(width: 6),
                    Text('$coins',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary)),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Hero card ──
            AppCard(
              radius: 24,
              child: Row(
                children: [
                  ProgressRing(
                    value: avg / 100,
                    center: Icon(
                      avg >= 100 ? Icons.check_rounded : Icons.cleaning_services,
                      color: c.accent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.t(cleanlinessKey(avg)),
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary)),
                        const SizedBox(height: 3),
                        Text(context.t('avg_clean', {'n': avg}),
                            style: TextStyle(
                                fontSize: 13.5, color: c.textSecondary)),
                        if (leader != null) ...[
                          const SizedBox(height: 9),
                          Pill(
                            text: context.t('leader', {'name': leader.name}),
                            bg: c.successPillBg,
                            fg: c.successPillText,
                            leading: Icon(Icons.star_rounded,
                                size: 13, color: c.accent),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Effort today ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(context.t('effort_today'),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary)),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('${data.effortToday}',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: c.accent)),
                      Text(' / $kDailyEffortTarget ${context.t('pts')}',
                          style:
                              TextStyle(fontSize: 13, color: c.textSecondary)),
                    ]),
              ],
            ),
            const SizedBox(height: 9),
            BarMeter(value: data.effortToday / kDailyEffortTarget),
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
                Text(context.t('todays_tasks'),
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.textPrimary)),
                Text(context.t('n_total', {'n': dueTasks.length}),
                    style: TextStyle(fontSize: 13, color: c.textSecondary)),
              ],
            ),
            const SizedBox(height: 4),
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
              for (int i = 0; i < dueTasks.length; i++)
                _TodayRow(
                  task: dueTasks[i],
                  last: i == dueTasks.length - 1,
                ),
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
  final bool last;
  const _TodayRow({required this.task, required this.last});

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final app = context.read<AppState>();
    final done = task.doneToday;

    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: c.divider)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: done ? null : () => completeTaskFlow(context, app, task),
            child: done
                ? Container(
                    width: 24,
                    height: 24,
                    decoration:
                        BoxDecoration(color: c.accent, shape: BoxShape.circle),
                    child: const Icon(Icons.check,
                        size: 14, color: Colors.white),
                  )
                : Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: c.textFaint, width: 2),
                    ),
                  ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: done ? c.textFaint : c.textPrimary,
                    decoration:
                        done ? TextDecoration.lineThrough : TextDecoration.none,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${freqLabel(context, task.freq)} · ${diffLabel(context, task.diff)}',
                  style: TextStyle(fontSize: 12.5, color: c.textFaint),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: done ? c.pageBg : c.successPillBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('+${task.points}',
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: done ? c.textFaint : c.successPillText)),
          ),
        ],
      ),
    );
  }
}
