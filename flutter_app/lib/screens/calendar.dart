import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

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
  late Future<List<CalendarDay>> _future;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  void _load() {
    final api = context.read<AppState>().api;
    _future = api.calendar(_year, _month).then((list) =>
        list.map((e) => CalendarDay.fromJson(e as Map<String, dynamic>)).toList());
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
    return Scaffold(
      backgroundColor: c.pageBg,
      appBar: chAppBar(context, context.t('calendar_title')),
      body: SafeArea(
        top: false,
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
              future: _future,
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

  void _openDay(BuildContext context, CalendarDay day) {
    final c = context.ch;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        decoration: BoxDecoration(
          color: c.pageBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
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
            Text('${day.date.day} ${_months(context)[day.date.month - 1]}',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: c.textPrimary)),
            const SizedBox(height: 12),
            ...day.tasks.map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(
                        t.done
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: t.done ? c.accent : c.textFaint,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(t.name,
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary,
                                    decoration: t.done
                                        ? TextDecoration.lineThrough
                                        : null)),
                            Text('${t.memberEmoji} ${t.memberName} · ${t.roomName}',
                                style: TextStyle(
                                    fontSize: 12.5, color: c.textSecondary)),
                          ],
                        ),
                      ),
                      DifficultyBolts(level: kDiffPts[t.diff] ?? 1, size: 13),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
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
