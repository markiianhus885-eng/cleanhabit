import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../widgets.dart';

String freqLabel(BuildContext c, String freq) =>
    c.t(kFreqDays.containsKey(freq) || freq == 'custom' ? 'freq_$freq' : 'freq_weekly');

String diffLabel(BuildContext c, String diff) => c.t('diff_$diff');

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
