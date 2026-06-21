// Smoke test for CleanHouse models (no network).
import 'package:flutter_test/flutter_test.dart';
import 'package:app/models.dart';

void main() {
  test('daily task is always due today', () {
    final t = Task.fromJson({
      'id': '1',
      'name': 'Sweep',
      'freq': 'daily',
      'diff': 'easy',
      'created_at': '2026-01-01T00:00:00',
    });
    expect(t.isDueOn(DateTime.now()), isTrue);
    expect(t.points, 1);
  });

  test('weekly task not yet due after recent completion', () {
    final now = DateTime.now();
    final t = Task.fromJson({
      'id': '2',
      'name': 'Mop',
      'freq': 'weekly',
      'diff': 'hard',
      'created_at': '2026-01-01T00:00:00',
      'last_completed': now.toIso8601String(),
    });
    expect(t.isDueOn(now), isFalse);
    expect(t.doneToday, isTrue);
    expect(t.points, 3);
  });
}
