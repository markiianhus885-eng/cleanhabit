import 'package:flutter/material.dart';
import '../theme.dart';
import '../l10n.dart';
import 'today.dart';
import 'tasks.dart';
import 'rooms.dart';
import 'family.dart';
import 'stub.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _tabs = <_TabDef>[
    _TabDef('nav_today', Icons.home_outlined, Icons.home_rounded),
    _TabDef('nav_tasks', Icons.check_circle_outline, Icons.check_circle),
    _TabDef('nav_rooms', Icons.grid_view_outlined, Icons.grid_view_rounded),
    _TabDef('nav_family', Icons.people_outline, Icons.people_rounded),
    _TabDef('nav_more', Icons.more_horiz, Icons.more_horiz),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = const [
      TodayScreen(),
      TasksScreen(),
      RoomsScreen(),
      FamilyScreen(),
      MoreScreen(),
    ];
    return Scaffold(
      backgroundColor: context.ch.pageBg,
      extendBody: true,
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _BottomNav(
        tabs: _tabs,
        index: _index,
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

class _TabDef {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  const _TabDef(this.label, this.icon, this.activeIcon);
}

class _BottomNav extends StatelessWidget {
  final List<_TabDef> tabs;
  final int index;
  final ValueChanged<int> onTap;
  const _BottomNav(
      {required this.tabs, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final light = Theme.of(context).brightness == Brightness.light;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        height: 66,
        decoration: BoxDecoration(
          color: c.navBar,
          borderRadius: BorderRadius.circular(24),
          boxShadow: light
              ? const [
                  BoxShadow(
                    color: Color(0x243C2D78),
                    blurRadius: 32,
                    spreadRadius: -10,
                    offset: Offset(0, 14),
                  )
                ]
              : const [
                  BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 24,
                    spreadRadius: -8,
                    offset: Offset(0, 10),
                  )
                ],
        ),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final t = tabs[i];
            final sel = i == index;
            final color = sel ? c.accent : c.textFaint;
            return Expanded(
              child: InkResponse(
                onTap: () => onTap(i),
                radius: 36,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(sel ? t.activeIcon : t.icon, size: 22, color: color),
                    const SizedBox(height: 4),
                    Text(context.t(t.label),
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight:
                                sel ? FontWeight.w700 : FontWeight.w600,
                            color: color)),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
