import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../templates.dart';
import '../theme.dart';
import '../widgets.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = app.data;
    final c = context.ch;
    if (data == null) {
      return Scaffold(
          backgroundColor: c.pageBg,
          appBar: chAppBar(context, context.t('goals_title')),
          body: const Loader());
    }
    final coins = data.me?.coins ?? 0;

    return Scaffold(
      backgroundColor: c.pageBg,
      appBar: chAppBar(context, context.t('goals_title'), actions: [
        if (data.amAdmin)
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: HeaderAddButton(onTap: () => _openAddGoal(context)),
          ),
      ]),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: c.accent,
          onRefresh: app.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
            children: [
              // Coins hero
              GradientHero(
                radius: 24,
                child: Row(
                  children: [
                    const CoinDot(size: 40),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.t('your_coins'),
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: c.onAccent.withValues(alpha: 0.7))),
                        Text('$coins',
                            style: TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w800,
                                color: c.onAccent)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              if (data.goals.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Column(children: [
                    const Text('🎯', style: TextStyle(fontSize: 44)),
                    const SizedBox(height: 10),
                    Text(
                        context.t(data.amAdmin ? 'add_first_goal' : 'no_goals'),
                        style: TextStyle(color: c.textSecondary)),
                  ]),
                )
              else
                for (final g in data.goals)
                  _GoalCard(goal: g, coins: coins, data: data),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Goal goal;
  final int coins;
  final HouseholdData data;
  const _GoalCard({required this.goal, required this.coins, required this.data});

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final app = context.read<AppState>();
    final canAfford = coins >= goal.price;
    final pending = goal.purchases.where((p) => !p.fulfilled).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        radius: 22,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(goal.emoji, style: const TextStyle(fontSize: 34)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.name,
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary)),
                      if ((goal.description ?? '').isNotEmpty)
                        Text(goal.description!,
                            style: TextStyle(
                                fontSize: 13, color: c.textSecondary)),
                    ],
                  ),
                ),
                if (data.amOwner)
                  GestureDetector(
                    onTap: () => _confirmDelete(context, app),
                    child: Icon(Icons.delete_outline, color: c.textFaint),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const CoinDot(size: 18),
                const SizedBox(width: 6),
                Text('${goal.price}',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary)),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: canAfford ? c.accent : c.trackBg,
                    foregroundColor: canAfford ? Colors.white : c.textFaint,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed:
                      canAfford ? () => _buy(context, app) : null,
                  child: Text(context.t(canAfford ? 'redeem' : 'not_enough')),
                ),
              ],
            ),
            if (pending.isNotEmpty) ...[
              const SizedBox(height: 12),
              Divider(color: c.divider, height: 1),
              const SizedBox(height: 10),
              ...pending.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Text('${p.memberEmoji} ${context.t('redeemed_this', {'name': p.memberName})}',
                            style: TextStyle(
                                fontSize: 12.5, color: c.textSecondary)),
                        const Spacer(),
                        if (data.amAdmin)
                          TextButton(
                            onPressed: () => _fulfill(context, app, p.id),
                            child: Text(context.t('mark_given'),
                                style: TextStyle(color: c.accent)),
                          )
                        else
                          Text(context.t('pending'),
                              style: TextStyle(
                                  fontSize: 12, color: c.textFaint)),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _buy(BuildContext context, AppState app) async {
    try {
      await app.buyGoal(goal.id);
      if (context.mounted) showSnack(context, '${context.t('redeemed')} ${goal.emoji}');
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _fulfill(BuildContext context, AppState app, String id) async {
    try {
      await app.fulfillPurchase(id);
      if (context.mounted) showSnack(context, context.t('marked_given'));
    } on ApiException catch (e) {
      if (context.mounted) showSnack(context, e.message, error: true);
    }
  }

  Future<void> _confirmDelete(BuildContext context, AppState app) async {
    final c = context.ch;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(context.t('delete_goal_q'),
            style: TextStyle(color: c.textPrimary)),
        content: Text(context.t('will_be_removed', {'name': goal.name}),
            style: TextStyle(color: c.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.t('cancel'),
                  style: TextStyle(color: c.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.t('delete'),
                  style: const TextStyle(color: Color(0xFFB3261E)))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await app.deleteGoal(goal.id);
        if (context.mounted) showSnack(context, context.t('goal_deleted'));
      } on ApiException catch (e) {
        if (context.mounted) showSnack(context, e.message, error: true);
      }
    }
  }
}

void _openAddGoal(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AddGoalSheet(),
  );
}

class _AddGoalSheet extends StatefulWidget {
  const _AddGoalSheet();
  @override
  State<_AddGoalSheet> createState() => _AddGoalSheetState();
}

class _AddGoalSheetState extends State<_AddGoalSheet> {
  final _name = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController(text: '50');
  String _emoji = '🎯';
  bool _busy = false;

  static const _emojis = [
    '🎯', '🍕', '🎮', '🎬', '🍦', '🏖️', '🎁', '⚽', '🛍️', '🧸', '📱', '🎢'
  ];

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final price = int.tryParse(_price.text.trim()) ?? 0;
    if (_name.text.trim().isEmpty || price < 1) {
      showSnack(context, context.t('enter_name_price'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context
          .read<AppState>()
          .addGoal(_name.text.trim(), _emoji, price, _desc.text.trim());
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, context.t('goal_added'));
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
            Text(context.t('new_goal'),
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary)),
            const SizedBox(height: 14),
            // Quick templates
            Text(context.t('goal_templates').toUpperCase(),
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: c.textFaint)),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: goalTemplates(context.read<AppState>().lang)
                    .map((tpl) => GestureDetector(
                          onTap: () => setState(() {
                            _emoji = tpl.emoji;
                            _name.text = tpl.name;
                            _desc.text = tpl.description;
                            _price.text = '${tpl.price}';
                          }),
                          child: Container(
                            width: 120,
                            margin: const EdgeInsets.only(right: 10),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(14),
                              border: _emoji == tpl.emoji &&
                                      _name.text == tpl.name
                                  ? Border.all(color: c.accent, width: 1.5)
                                  : null,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(tpl.emoji,
                                    style: const TextStyle(fontSize: 24)),
                                const Spacer(),
                                Text(tpl.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: c.textPrimary)),
                                const SizedBox(height: 2),
                                Row(children: [
                                  const CoinDot(size: 13),
                                  const SizedBox(width: 4),
                                  Text('${tpl.price}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: c.textSecondary)),
                                ]),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 16),
            _input(c, _name, context.t('reward_hint')),
            const SizedBox(height: 10),
            _input(c, _desc, context.t('desc_optional')),
            const SizedBox(height: 10),
            _input(c, _price, context.t('price_coins'), number: true),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _emojis.map((e) {
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
                    : Text(context.t('add_goal'),
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

  Widget _input(ChColors c, TextEditingController ctrl, String hint,
      {bool number = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: c.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.textFaint),
        filled: true,
        fillColor: c.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}
