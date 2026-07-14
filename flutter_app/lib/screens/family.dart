import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

/// Manage household members — add, remove, change roles.
class FamilyScreen extends StatelessWidget {
  const FamilyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = app.data;
    final c = context.ch;
    if (data == null) return const Loader();

    return ChPage(
      title: context.t('family_title'),
      subtitle: context.t('manage_members'),
      onRefresh: () => app.refresh(),
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
        for (final m in data.members) _MemberRow(member: m, data: data),
      ],
    );
  }

  static void _openAddMember(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddMemberSheet(),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final Member member;
  final HouseholdData data;
  const _MemberRow({required this.member, required this.data});

  bool get _isCreator => member.id == data.adminMemberId;
  bool get _isAdmin => data.membersRoles[member.id] == 'admin';

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final canManage = data.amAdmin && !_isCreator;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: canManage ? () => _openManage(context) : null,
        child: AppCard(
          child: Row(
            children: [
              Text(member.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(member.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: c.textPrimary)),
                      ),
                      if (_isCreator) ...[
                        const SizedBox(width: 6),
                        const Text('👑', style: TextStyle(fontSize: 13)),
                      ] else if (_isAdmin) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.shield, size: 13, color: c.accent),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(
                        '${levelIcon(member.points)} ${levelName(member.points)} · Lv.${levelOf(member.points)}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: c.accent)),
                    const SizedBox(height: 5),
                    Row(children: [
                      Text('${member.points} ${context.t('pts')}',
                          style:
                              TextStyle(fontSize: 12, color: c.textSecondary)),
                      const SizedBox(width: 10),
                      const CoinDot(size: 12),
                      const SizedBox(width: 3),
                      Text('${member.coins}',
                          style:
                              TextStyle(fontSize: 12, color: c.textSecondary)),
                      const SizedBox(width: 10),
                      Text('🔥 ${member.streak}',
                          style:
                              TextStyle(fontSize: 12, color: c.textSecondary)),
                    ]),
                  ],
                ),
              ),
              if (canManage)
                Icon(Icons.more_horiz, color: c.textFaint),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openManage(BuildContext context) async {
    final c = context.ch;
    final app = context.read<AppState>();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.of(ctx).padding.bottom),
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
                      color: c.divider,
                      borderRadius: BorderRadius.circular(999))),
            ),
            const SizedBox(height: 16),
            Text('${member.emoji}  ${member.name}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary)),
            const SizedBox(height: 12),
            if (data.amOwner)
              ListTile(
                leading: Icon(
                    _isAdmin
                        ? Icons.remove_moderator_outlined
                        : Icons.admin_panel_settings_outlined,
                    color: c.accent),
                title: Text(context.t(_isAdmin ? 'make_member' : 'make_admin'),
                    style: TextStyle(
                        color: c.textPrimary, fontWeight: FontWeight.w600)),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _run(
                      context,
                      () => app.setMemberRole(
                          member.id, _isAdmin ? 'member' : 'admin'),
                      context.t('role_updated'));
                },
              ),
            ListTile(
              leading:
                  const Icon(Icons.delete_outline, color: Color(0xFFB3261E)),
              title: Text(context.t('remove_member'),
                  style: const TextStyle(
                      color: Color(0xFFB3261E), fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                await _run(context, () => app.deleteMember(member.id),
                    context.t('member_removed'));
              },
            ),
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
    final mq = MediaQuery.of(context);
    final bottom = mq.viewInsets.bottom > 0 ? mq.viewInsets.bottom : mq.padding.bottom;
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
