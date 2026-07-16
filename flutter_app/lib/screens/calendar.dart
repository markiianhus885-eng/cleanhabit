import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'task_actions.dart';
import 'tasks.dart' show openTaskEditSheet, openTaskAddSheet;

const Map<String, List<String>> _monthsByLang = {
  'en': ['January', 'February', 'March', 'April', 'May', 'June', 'July',
         'August', 'September', 'October', 'November', 'December'],
  'pl': ['Styczeń', 'Luty', 'Marzec', 'Kwiecień', 'Maj', 'Czerwiec', 'Lipiec',
         'Sierpień', 'Wrzesień', 'Październik', 'Listopad', 'Grudzień'],
  'uk': ['Січень', 'Лютий', 'Березень', 'Квітень', 'Травень', 'Червень', 'Липень',
         'Серпень', 'Вересень', 'Жовтень', 'Листопад', 'Грудень'],
};
const Map<String, List<String>> _weekdaysByLang = {
  'en': ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'],
  'pl': ['Pn', 'Wt', 'Śr', 'Cz', 'Pt', 'So', 'Nd'],
  'uk': ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Нд'],
};
List<String> _months(BuildContext c) =>
    _monthsByLang[c.watch<AppState>().lang] ?? _monthsByLang['en']!;
List<String> _weekdays(BuildContext c) =>
    _weekdaysByLang[c.watch<AppState>().lang] ?? _weekdaysByLang['en']!;

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late int _year;
  late int _month;
  String? _memberFilter; // null = not yet initialized; 'all' = everyone
  Future<List<CalendarDay>>? _future;
  // AppState hands out a new HouseholdData instance on every refresh() —
  // tracking the reference lets us reload the calendar's own separate
  // /api/calendar fetch whenever a task is added/completed/deleted
  // elsewhere, without an extra notifier just for this.
  HouseholdData? _lastData;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
  }

  void _load() {
    final api = context.read<AppState>().api;
    _future = api
        .calendar(_year, _month, memberId: _memberFilter)
        .then((list) => list
            .map((e) => CalendarDay.fromJson(e as Map<String, dynamic>))
            .toList());
  }

  void _setMember(String id) {
    setState(() {
      _memberFilter = id;
      _load();
    });
  }

  void _shift(int delta) {
    setState(() {
      _month += delta;
      if (_month < 1) {
        _month = 12;
        _year--;
      } else if (_month > 12) {
        _month = 1;
        _year++;
      }
      _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final data = context.watch<AppState>().data;
    if (_memberFilter == null) {
      _memberFilter = data?.me?.id ?? 'all';
      _load();
    } else if (data != null && !identical(data, _lastData)) {
      _lastData = data;
      _load();
    }
    _future ??= Future.value(<CalendarDay>[]);
    return Scaffold(
      backgroundColor: c.pageBg,
      appBar: chAppBar(context, context.t('calendar_title')),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: c.accent,
          onRefresh: () async {
            await context.read<AppState>().refresh();
            setState(_load);
          },
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _arrow(c, Icons.chevron_left, () => _shift(-1)),
                Text('${_months(context)[_month - 1]} $_year',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary)),
                _arrow(c, Icons.chevron_right, () => _shift(1)),
              ],
            ),
            const SizedBox(height: 12),
            if (data != null)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _memberChip(c, context.t('all'), 'all'),
                  for (final m in data.members)
                    _memberChip(c, '${m.emoji} ${m.name}', m.id),
                ]),
              ),
            const SizedBox(height: 14),
            Row(
              children: _weekdays(context)
                  .map((d) => Expanded(
                        child: Center(
                          child: Text(d,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: c.textFaint)),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<CalendarDay>>(
              future: _future!,
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                      padding: EdgeInsets.only(top: 40), child: Loader());
                }
                final days = snap.data ?? [];
                if (days.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                        child: Text(context.t('cal_no_data'),
                            style: TextStyle(color: c.textSecondary))),
                  );
                }
                final firstWeekday = days.first.date.weekday; // Mon=1..Sun=7
                final leading = firstWeekday - 1;
                final cells = <Widget>[];
                for (int i = 0; i < leading; i++) {
                  cells.add(const SizedBox());
                }
                for (final day in days) {
                  cells.add(_DayCell(
                    day: day,
                    onTap: day.tasks.isEmpty ? null : () => _openDay(context, day),
                  ));
                }
                return GridView.count(
                  crossAxisCount: 7,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                  childAspectRatio: 0.78,
                  children: cells,
                );
              },
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _memberChip(ChColors c, String label, String value) {
    final sel = _memberFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _setMember(value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: sel ? c.accent : c.card,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : c.textSecondary)),
        ),
      ),
    );
  }

  Widget _arrow(ChColors c, IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: c.card, borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: c.textPrimary),
        ),
      );

  void _openDay(BuildContext context, CalendarDay initialDay) {
    CalendarDay day = initialDay;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setSheetState) {
          final c = sheetCtx.ch;
          final data = sheetCtx.watch<AppState>().data;

          Future<void> reload() async {
            await context.read<AppState>().refresh();
            _load();
            final updated = await _future!;
            final match = updated.firstWhere(
              (d) =>
                  d.date.year == day.date.year &&
                  d.date.month == day.date.month &&
                  d.date.day == day.date.day,
              orElse: () =>
                  CalendarDay(date: day.date, isToday: day.isToday, tasks: []),
            );
            setSheetState(() => day = match);
            if (mounted) setState(() {});
          }

          final safeBottom = MediaQuery.of(sheetCtx).padding.bottom;
          return Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + safeBottom),
            decoration: BoxDecoration(
              color: c.pageBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${day.date.day} ${_months(sheetCtx)[day.date.month - 1]}',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: c.textPrimary)),
                      if (data != null)
                        GestureDetector(
                          onTap: () async {
                            await openTaskAddSheet(sheetCtx, data,
                                forDate: day.date);
                            await reload();
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                                color: c.accent.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.add, size: 18, color: c.accent),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (day.tasks.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(sheetCtx.t('cal_free_day'),
                          style: TextStyle(color: c.textSecondary)),
                    )
                  else if (data != null)
                    ...day.tasks.map((t) => _CalTaskRow(
                          calTask: t,
                          isToday: day.isToday,
                          dayIso:
                              '${day.date.year.toString().padLeft(4, '0')}-${day.date.month.toString().padLeft(2, '0')}-${day.date.day.toString().padLeft(2, '0')}',
                          data: data,
                          onChanged: reload,
                        )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CalTaskRow extends StatelessWidget {
  final CalendarTask calTask;
  final bool isToday;
  final String dayIso;
  final HouseholdData data;
  final Future<void> Function() onChanged;
  const _CalTaskRow({
    required this.calTask,
    required this.isToday,
    required this.dayIso,
    required this.data,
    required this.onChanged,
  });

  Task? get _full {
    try {
      return data.tasks.firstWhere((t) => t.id == calTask.id);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final app = context.read<AppState>();
    final full = _full;
    final canDo = isToday && !calTask.done && full != null && canCompleteTask(data, full);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          TaskCheckbox(
            done: calTask.done,
            locked: !calTask.done && !canDo,
            size: 26,
            onTap: calTask.done
                ? (isToday && full != null
                    ? () async {
                        await uncompleteTaskFlow(context, app, full);
                        await onChanged();
                      }
                    : null)
                : (canDo
                    ? () async {
                        await completeTaskFlow(context, app, full);
                        await onChanged();
                      }
                    : null),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(calTask.name,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                        decoration:
                            calTask.done ? TextDecoration.lineThrough : null)),
                Text('${calTask.memberEmoji} ${calTask.memberName} · ${calTask.roomName}',
                    style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
              ],
            ),
          ),
          DifficultyBolts(level: kDiffPts[calTask.diff] ?? 1, size: 13),
          if (full != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => openTaskEditSheet(context, data, full),
              child: Icon(Icons.edit_outlined, size: 18, color: c.textFaint),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _confirmDelete(context, app, full),
              child: const Text('✕',
                  style: TextStyle(
                      color: Color(0xFFE5557A),
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AppState app, Task task) async {
    final c = context.ch;
    if (task.oneTime) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: c.card,
          title: Text(context.t('delete_task_q'),
              style: TextStyle(color: c.textPrimary)),
          content: Text(context.t('will_be_removed', {'name': task.name}),
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
          await app.deleteTask(task.id);
          if (context.mounted) showSnack(context, context.t('task_deleted'));
        } on ApiException catch (e) {
          if (context.mounted) showSnack(context, e.message, error: true);
        }
        await onChanged();
      }
      return;
    }

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(context.t('cal_delete_recurring_q'),
            style: TextStyle(color: c.textPrimary)),
        content: Text(task.name, style: TextStyle(color: c.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(context.t('cancel'),
                  style: TextStyle(color: c.textSecondary))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'skip'),
              child: Text(context.t('cal_skip_occurrence'),
                  style: TextStyle(color: c.accent))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'all'),
              child: Text(context.t('cal_delete_all_future'),
                  style: const TextStyle(color: Color(0xFFB3261E)))),
        ],
      ),
    );
    if (choice == 'skip') {
      try {
        await app.expireTask(task.id, date: dayIso);
      } on ApiException catch (e) {
        if (context.mounted) showSnack(context, e.message, error: true);
      }
      await onChanged();
    } else if (choice == 'all') {
      try {
        await app.deleteTask(task.id);
        if (context.mounted) showSnack(context, context.t('task_deleted'));
      } on ApiException catch (e) {
        if (context.mounted) showSnack(context, e.message, error: true);
      }
      await onChanged();
    }
  }
}

class _DayCell extends StatelessWidget {
  final CalendarDay day;
  final VoidCallback? onTap;
  const _DayCell({required this.day, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final total = day.tasks.length;
    final done = day.doneCount;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: day.isToday ? c.successPillBg : c.card,
          borderRadius: BorderRadius.circular(12),
          border: day.isToday ? Border.all(color: c.accent, width: 1.5) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${day.date.day}',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary)),
            if (total > 0) ...[
              const SizedBox(height: 3),
              Wrap(
                spacing: 2,
                alignment: WrapAlignment.center,
                children: List.generate(
                  total.clamp(0, 3),
                  (i) => Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < done ? c.accent : c.textFaint,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
