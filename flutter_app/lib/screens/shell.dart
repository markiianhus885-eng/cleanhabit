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
    return Container(
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final t = tabs[i];
              final sel = i == index;
              final color = sel ? c.accent : c.textFaint;
              return Expanded(
                child: InkResponse(
                  onTap: () => onTap(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(sel ? t.activeIcon : t.icon, size: 23, color: color),
                      const SizedBox(height: 4),
                      Text(context.t(t.label),
                          style: TextStyle(
                              fontSize: 11,
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
      ),
    );
  }
}
