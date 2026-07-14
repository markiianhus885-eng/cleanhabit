import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';

String freqLabel(BuildContext c, String freq) =>
    c.t(kFreqDays.containsKey(freq) || freq == 'custom' ? 'freq_$freq' : 'freq_weekly');

String diffLabel(BuildContext c, String diff) => c.t('diff_$diff');

const List<String> _dowAbbrEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Mirrors the web's fmtSchedule(): one-time tasks never show a recurrence
/// label, specific-day tasks list their weekdays, everything else falls
/// back to the plain frequency label.
String fmtSchedule(BuildContext c, Task task) {
  if (task.oneTime) return c.t('task_one_time_sched');
  final sd = task.specificDays;
  if (sd != null && sd.isNotEmpty) {
    final days = sd
        .split(',')
        .map((s) => int.tryParse(s.trim()))
        .whereType<int>()
        .toList()
      ..sort();
    return days.map((d) => _dowAbbrEn[d.clamp(0, 6)]).join(', ');
  }
  return freqLabel(c, task.freq);
}

String greetingKey() {
  final h = DateTime.now().hour;
  if (h < 12) return 'greet_morning';
  if (h < 18) return 'greet_afternoon';
  return 'greet_evening';
}

String cleanlinessKey(int avg) {
  if (avg >= 90) return 'clean_sparkling';
  if (avg >= 70) return 'clean_good';
  if (avg >= 40) return 'clean_love';
  return 'clean_dirty';
}

/// Mirrors the server's restriction in /api/tasks/{id}/complete: only the
/// assignee (or an admin/owner) may mark a task done.
bool canCompleteTask(HouseholdData data, Task task) {
  if (data.amAdmin) return true;
  if (task.assignedTo.isEmpty) return true;
  return task.assignedTo == data.me?.id;
}

/// Completes a task with feedback; shows approval / points snackbars.
Future<void> completeTaskFlow(
    BuildContext context, AppState app, Task task) async {
  try {
    final res = await app.completeTask(task.id);
    if (!context.mounted) return;
    if (res['pending_approval'] == true) {
      showSnack(context, context.t('sent_approval'));
    } else {
      final pts = res['pts'] ?? task.points;
      showSnack(context, context.t('nice_pts', {'n': pts}));
    }
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  } catch (_) {
    if (context.mounted) showSnack(context, context.t('net_error'), error: true);
  }
}

/// Confirms, then undoes today's most recent completion of a task — for
/// when someone taps "done" by mistake.
Future<void> uncompleteTaskFlow(
    BuildContext context, AppState app, Task task) async {
  final c = context.ch;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.card,
      title: Text(context.t('undo_complete_q'),
          style: TextStyle(color: c.textPrimary)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('cancel'),
                style: TextStyle(color: c.textSecondary))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('undo'), style: TextStyle(color: c.accent))),
      ],
    ),
  );
  if (ok != true) return;
  try {
    await app.uncompleteTask(task.id);
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  } catch (_) {
    if (context.mounted) showSnack(context, context.t('net_error'), error: true);
  }
}
