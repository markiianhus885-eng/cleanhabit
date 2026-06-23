import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'rooms.dart';
import 'family.dart';
import 'badges.dart';
import 'profile.dart';
import 'assistant.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = app.data;
    final c = context.ch;

    return ChPage(
      title: context.t('more_title'),
      subtitle: data?.household,
      trailing: (data != null && data.amAdmin)
          ? GestureDetector(
              onTap: () => _renameHousehold(context, data.household),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: c.card, borderRadius: BorderRadius.circular(13)),
                child: Icon(Icons.edit_outlined, size: 18, color: c.accent),
              ),
            )
          : null,
      children: [
        // Features
        AppCard(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              _nav(context, Icons.mic_none_rounded, context.t('ai_assistant'),
                  const AssistantScreen(), highlight: true),
              _nav(context, Icons.grid_view_outlined, context.t('nav_rooms'),
                  const RoomsScreen()),
              _nav(context, Icons.people_outline, context.t('nav_family'),
                  const FamilyScreen()),
              _nav(context, Icons.emoji_events_outlined,
                  context.t('badges_title'), const BadgesScreen()),
              _nav(context, Icons.person_outline, context.t('profile_title'),
                  const ProfileScreen()),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Language
        _sectionLabel(context, c, context.t('language')),
        AppCard(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: kLangs
                .map((code) => ListTile(
                      onTap: () => app.setLang(code),
                      leading: Text(_flag(code),
                          style: const TextStyle(fontSize: 20)),
                      title: Text(kLangNames[code]!,
                          style: TextStyle(
                              color: c.textPrimary,
                              fontWeight: FontWeight.w600)),
                      trailing: app.lang == code
                          ? Icon(Icons.check, color: c.accent)
                          : null,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 16),

        // Theme
        _sectionLabel(context, c, context.t('appearance')),
        AppCard(
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              _theme(c, app, Icons.light_mode_outlined,
                  context.t('theme_light'), ThemeMode.light),
              _theme(c, app, Icons.dark_mode_outlined, context.t('theme_dark'),
                  ThemeMode.dark),
              _theme(c, app, Icons.brightness_auto_outlined,
                  context.t('theme_system'), ThemeMode.system),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Family code
        if (data != null && data.householdToken.isNotEmpty)
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('🔑', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Text(context.t('family_code'),
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: c.textPrimary)),
                ]),
                const SizedBox(height: 4),
                Text(context.t('share_code'),
                    style: TextStyle(fontSize: 13, color: c.textSecondary)),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: data.householdToken));
                    showSnack(context, context.t('code_copied'));
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: c.accent.withOpacity(0.08),
                      border: Border.all(color: c.accent.withOpacity(0.25)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      data.householdToken.split('').join('  '),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: c.accent),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // Logout
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: c.divider),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => context.read<AppState>().logout(),
            icon: const Icon(Icons.logout, color: Color(0xFFB3261E)),
            label: Text(context.t('logout'),
                style: const TextStyle(
                    color: Color(0xFFB3261E), fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Future<void> _renameHousehold(BuildContext context, String current) async {
    final c = context.ch;
    final ctrl = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(context.t('edit_family_name'),
            style: TextStyle(color: c.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: c.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: c.pageBg,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.t('cancel'),
                  style: TextStyle(color: c.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(context.t('save'),
                  style: TextStyle(color: c.accent))),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      try {
        await context.read<AppState>().renameHousehold(name);
        if (context.mounted) showSnack(context, context.t('name_saved'));
      } on Object catch (e) {
        if (context.mounted) showSnack(context, '$e', error: true);
      }
    }
  }

  String _flag(String code) => switch (code) {
        'pl' => '🇵🇱',
        'uk' => '🇺🇦',
        _ => '🇬🇧',
      };

  Widget _sectionLabel(BuildContext context, ChColors c, String s) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(s,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textSecondary)),
      );

  Widget _nav(BuildContext context, IconData icon, String label, Widget page,
      {bool highlight = false}) {
    final c = context.ch;
    return ListTile(
      onTap: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => page)),
      leading: Icon(icon, color: highlight ? c.accent : c.textSecondary),
      title: Text(label,
          style: TextStyle(
              color: c.textPrimary,
              fontWeight: highlight ? FontWeight.w700 : FontWeight.w600)),
      trailing: Icon(Icons.chevron_right, color: c.textFaint),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _theme(
      ChColors c, AppState app, IconData icon, String label, ThemeMode mode) {
    final sel = app.themeMode == mode;
    return ListTile(
      onTap: () => app.setThemeMode(mode),
      leading: Icon(icon, color: sel ? c.accent : c.textSecondary),
      title: Text(label,
          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600)),
      trailing: sel ? Icon(Icons.check, color: c.accent) : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
