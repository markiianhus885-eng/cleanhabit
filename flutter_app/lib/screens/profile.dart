import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = app.data;
    final c = context.ch;
    if (data == null) {
      return Scaffold(
          backgroundColor: c.pageBg,
          appBar: chAppBar(context, context.t('profile_title')),
          body: const Loader());
    }
    final me = data.me;
    final username = data.currentUser?.username ?? '';
    final pts = me?.points ?? 0;

    return Scaffold(
      backgroundColor: c.pageBg,
      appBar: chAppBar(context, context.t('profile_title'), actions: [
        TextButton(
          onPressed: () => app.logout(),
          child: Text(context.t('logout'),
              style: const TextStyle(
                  color: Color(0xFFB3261E), fontWeight: FontWeight.w700)),
        ),
      ]),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            // Identity card
            AppCard(
              radius: 24,
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: c.pageBg,
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(me?.emoji ?? '🧑',
                            style: const TextStyle(fontSize: 34)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(me?.name ?? username,
                                style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: c.textPrimary)),
                            if (username.isNotEmpty)
                              Text('@$username',
                                  style: TextStyle(
                                      fontSize: 13, color: c.textSecondary)),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: c.successPillBg,
                                  borderRadius: BorderRadius.circular(999)),
                              child: Text(
                                  '${levelIcon(pts)} ${levelName(pts)} · Lv.${levelOf(pts)}',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: c.successPillText)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(context.t('progress_next'),
                          style:
                              TextStyle(fontSize: 12.5, color: c.textSecondary)),
                      Text(
                          ptsToNext(pts) == null
                              ? context.t('max_level')
                              : context.t('pts_to_go', {'n': ptsToNext(pts)!}),
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: c.accent)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  BarMeter(value: levelProgress(pts)),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Stat tiles
            Row(
              children: [
                _stat(c, '${me?.points ?? 0}', context.t('points')),
                const SizedBox(width: 12),
                _stat(c, '${me?.coins ?? 0}', context.t('coins'),
                    icon: const CoinDot(size: 16)),
                const SizedBox(width: 12),
                _stat(c, '${me?.streak ?? 0}', context.t('streak'),
                    icon: const Text('🔥', style: TextStyle(fontSize: 15))),
              ],
            ),
            const SizedBox(height: 14),

            // My badges
            Text(context.t('my_badges_n', {'n': me?.achievements.length ?? 0}),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary)),
            const SizedBox(height: 10),
            if ((me?.achievements ?? []).isEmpty)
              AppCard(
                child: Text(context.t('no_badges'),
                    style: TextStyle(color: c.textSecondary)),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: me!.achievements
                    .map((b) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(14)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(b.emoji, style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 6),
                            Text(
                                kBadgeByKey.containsKey(b.key)
                                    ? context.t('b_${b.key}_n')
                                    : b.name,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary)),
                          ]),
                        ))
                    .toList(),
              ),
            const SizedBox(height: 16),

            // Family code
            if (data.householdToken.isNotEmpty)
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('🔑', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      Text(context.t('family_code'),
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary)),
                    ]),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(
                            ClipboardData(text: data.householdToken));
                        showSnack(context, context.t('code_copied'));
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                            color: c.accent.withOpacity(0.08),
                            border: Border.all(
                                color: c.accent.withOpacity(0.25)),
                            borderRadius: BorderRadius.circular(14)),
                        child: Text(data.householdToken.split('').join('  '),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                color: c.accent)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(ChColors c, String value, String label, {Widget? icon}) {
    return Expanded(
      child: AppCard(
        radius: 18,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            if (icon != null) ...[icon, const SizedBox(height: 4)],
            Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 12, color: c.textFaint)),
          ],
        ),
      ),
    );
  }
}
