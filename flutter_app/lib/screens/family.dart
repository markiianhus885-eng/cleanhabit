import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

class FamilyScreen extends StatefulWidget {
  const FamilyScreen({super.key});
  @override
  State<FamilyScreen> createState() => _FamilyScreenState();
}

class _FamilyScreenState extends State<FamilyScreen> {
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
    _future = api
        .leaderboard(_periods[_period])
        .then((list) => list
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
      title: context.t('family_title'),
      subtitle: context.t('n_members', {'n': data.members.length}),
      onRefresh: _refresh,
      trailing: data.amAdmin
          ? GestureDetector(
              onTap: () => _openAddMember(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: c.accent, borderRadius: BorderRadius.circular(13)),
                child: const Icon(Icons.person_add_alt_1,
                    color: Colors.white, size: 20),
              ),
            )
          : null,
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
                  _MemberCard(
                    entry: entries[i],
                    rank: i + 1,
                    period: _period,
                    isCreator: entries[i].id == data.adminMemberId,
                    canManage: data.amAdmin,
                    hasAccount: data.membersRoles.containsKey(entries[i].id),
                    onManage: () => _openManage(context, data, entries[i]),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _openAddMember(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddMemberSheet(),
    );
  }

  Future<void> _openManage(
      BuildContext context, HouseholdData data, LeaderEntry m) async {
    final c = context.ch;
    final app = context.read<AppState>();
    final isCreator = m.id == data.adminMemberId;
    final hasAccount = data.membersRoles.containsKey(m.id);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: c.pageBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: c.divider, borderRadius: BorderRadius.circular(999))),
            ),
            const SizedBox(height: 16),
            Text('${m.emoji}  ${m.name}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary)),
            const SizedBox(height: 12),
            if (isCreator)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(context.t('creator_locked'),
                    style: TextStyle(color: c.textSecondary)),
              )
            else ...[
              if (hasAccount && data.amOwner)
                ListTile(
                  leading: Icon(
                      m.isAdmin
                          ? Icons.remove_moderator_outlined
                          : Icons.admin_panel_settings_outlined,
                      color: c.accent),
                  title: Text(context.t(m.isAdmin ? 'make_member' : 'make_admin'),
                      style: TextStyle(
                          color: c.textPrimary, fontWeight: FontWeight.w600)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _run(
                        context,
                        () => app.setMemberRole(
                            m.id, m.isAdmin ? 'member' : 'admin'),
                        context.t('role_updated'));
                    setState(_load);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFB3261E)),
                title: Text(context.t('remove_member'),
                    style: const TextStyle(
                        color: Color(0xFFB3261E), fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _run(context, () => app.deleteMember(m.id),
                      context.t('member_removed'));
                  setState(_load);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _run(
      BuildContext context, Future<void> Function() fn, String okMsg) async {
    try {
      await fn();
      if (context.mounted) showSnack(context, okMsg);
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }
}

class _MemberCard extends StatelessWidget {
  final LeaderEntry entry;
  final int rank;
  final int period;
  final bool isCreator;
  final bool canManage;
  final bool hasAccount;
  final VoidCallback onManage;
  const _MemberCard({
    required this.entry,
    required this.rank,
    required this.period,
    required this.isCreator,
    required this.canManage,
    required this.hasAccount,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final medal = switch (rank) { 1 => '🥇', 2 => '🥈', 3 => '🥉', _ => '' };
    final pts = period == 2 ? entry.points : entry.periodPts;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: canManage ? onManage : null,
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
                    Row(children: [
                      Text(
                          '${levelIcon(entry.points)} ${levelName(entry.points)} · Lv.${levelOf(entry.points)}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: c.accent)),
                    ]),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: 130,
                      child: BarMeter(
                          value: levelProgress(entry.points), height: 5),
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
      ),
    );
  }
}

class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet();
  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _name = TextEditingController();
  String _emoji = kMemberEmojis.first;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, context.t('enter_name'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().addMember(_name.text.trim(), _emoji);
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, context.t('member_added'));
      }
    } on ApiException catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: c.pageBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: c.divider,
                      borderRadius: BorderRadius.circular(999))),
            ),
            const SizedBox(height: 16),
            Text(context.t('add_member'),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary)),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: context.t('member_name_hint'),
                hintStyle: TextStyle(color: c.textFaint),
                filled: true,
                fillColor: c.card,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kMemberEmojis.map((e) {
                final sel = e == _emoji;
                return GestureDetector(
                  onTap: () => setState(() => _emoji = e),
                  child: Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: sel ? c.accent : c.card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(e, style: const TextStyle(fontSize: 22)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 50,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _busy ? null : _save,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white))
                    : Text(context.t('add_member_btn'),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
