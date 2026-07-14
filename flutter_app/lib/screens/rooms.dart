import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../theme.dart';
import '../widgets.dart';
import 'task_actions.dart';
import 'tasks.dart' show openTaskEditSheet;

class RoomsScreen extends StatelessWidget {
  const RoomsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = app.data;
    final c = context.ch;
    if (data == null) return const Loader();

    int taskCount(String roomId) =>
        data.tasks.where((t) => t.roomId == roomId).length;

    return Scaffold(
      backgroundColor: c.pageBg,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: c.accent,
          onRefresh: app.refresh,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.t('rooms_title'),
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 2),
                        Text(context.t('n_rooms', {'n': data.rooms.length}),
                            style: TextStyle(
                                fontSize: 13.5, color: c.textSecondary)),
                      ],
                    ),
                  ),
                  HeaderAddButton(onTap: () => _openAddRoom(context)),
                ],
              ),
              const SizedBox(height: 16),
              if (data.rooms.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 50),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.grid_view_rounded,
                          size: 44, color: c.textFaint),
                      const SizedBox(height: 10),
                      Text(context.t('add_first_room'),
                          style: TextStyle(color: c.textSecondary)),
                    ]),
                  ),
                )
              else
                for (final room in data.rooms)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _RoomCard(room: room, tasks: taskCount(room.id)),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final Room room;
  final int tasks;
  const _RoomCard({required this.room, required this.tasks});

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final clean = room.cleanliness;
    final isClean = clean >= 90;

    return GestureDetector(
      onTap: () => _openRoomDetail(context, room),
      child: AppCard(
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.pageBg,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(room.emoji, style: const TextStyle(fontSize: 28)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(room.name,
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary)),
                    const SizedBox(height: 1),
                    Text(
                      _cleanedLabel(context, room.lastCleaned),
                      style: TextStyle(fontSize: 13, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _confirmDelete(context, room),
                child: Icon(Icons.more_horiz, color: c.textFaint),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('$clean%',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: c.accent)),
              const Spacer(),
              Pill(
                text: isClean ? context.t('clean_badge') : context.t('needs_work'),
                bg: isClean ? c.successPillBg : c.pageBg,
                fg: isClean ? c.successPillText : c.textSecondary,
                leading: isClean
                    ? Icon(Icons.check, size: 13, color: c.successPillText)
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          BarMeter(value: clean / 100, height: 10),
          const SizedBox(height: 12),
          Pill(
            text: context.t(tasks == 1 ? 'n_task' : 'n_tasks', {'n': tasks}),
            bg: c.pageBg,
            fg: c.textSecondary,
          ),
        ],
      ),
      ),
    );
  }

  String _cleanedLabel(BuildContext context, DateTime? d) {
    if (d == null) return context.t('never_cleaned');
    final days = DateTime.now().difference(d).inDays;
    if (days <= 0) return context.t('cleaned_today');
    if (days == 1) return context.t('cleaned_yesterday');
    return context.t('cleaned_days', {'n': days});
  }

  Future<void> _confirmDelete(BuildContext context, Room room) async {
    final c = context.ch;
    final app = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.card,
        title: Text(context.t('delete_room_q'),
            style: TextStyle(color: c.textPrimary)),
        content: Text(context.t('room_will_remove', {'name': room.name}),
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
        await app.deleteRoom(room.id);
        if (context.mounted) showSnack(context, context.t('room_deleted'));
      } on ApiException catch (e) {
        if (context.mounted) showSnack(context, e.message, error: true);
      }
    }
  }
}

void _openRoomDetail(BuildContext context, Room room) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _RoomDetailSheet(room: room),
  );
}

class _RoomDetailSheet extends StatefulWidget {
  final Room room;
  const _RoomDetailSheet({required this.room});
  @override
  State<_RoomDetailSheet> createState() => _RoomDetailSheetState();
}

class _RoomDetailSheetState extends State<_RoomDetailSheet> {
  Future<Map<String, dynamic>>? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _stats = context.read<AppState>().roomStats(widget.room.id);
  }

  Future<void> _reload() async {
    await context.read<AppState>().refresh();
    setState(_load);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final data = context.watch<AppState>().data;
    final room = data?.rooms.firstWhere((r) => r.id == widget.room.id,
            orElse: () => widget.room) ??
        widget.room;
    final roomTasks = data?.tasks.where((t) => t.roomId == room.id).toList() ?? [];

    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.of(context).padding.bottom),
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
            Center(
              child: Text(room.emoji, style: const TextStyle(fontSize: 48)),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(room.name,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: c.textPrimary)),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text('${room.cleanliness}%',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: c.accent)),
            ),
            const SizedBox(height: 8),
            BarMeter(value: room.cleanliness / 100, height: 10),
            const SizedBox(height: 18),
            FutureBuilder<Map<String, dynamic>>(
              future: _stats,
              builder: (ctx, snap) {
                final s = snap.data;
                if (s == null || s['error'] != null) return const SizedBox();
                final weekTotal = s['week_total'] as Map<String, dynamic>? ?? {};
                final breakdown =
                    (s['member_breakdown'] as List?)?.cast<Map<String, dynamic>>() ?? [];
                final maxCount = breakdown.isEmpty
                    ? 1
                    : breakdown
                        .map((b) => (b['count'] as num?)?.toInt() ?? 0)
                        .reduce((a, b) => a > b ? a : b)
                        .clamp(1, 1 << 30);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: _StatBox(
                              label: context.t('room_stat_today'),
                              value: '${s['done_count'] ?? 0}/${roomTasks.length}',
                              color: c.accent)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _StatBox(
                              label: context.t('room_stat_week'),
                              value: '${weekTotal['count'] ?? 0}',
                              color: c.successPillText)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _StatBox(
                              label: context.t('room_stat_points'),
                              value: '🪙${weekTotal['pts'] ?? 0}',
                              color: c.star)),
                    ]),
                    if (breakdown.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      for (final b in breakdown)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(children: [
                            Text('${b['emoji'] ?? '👤'}',
                                style: const TextStyle(fontSize: 14)),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 64,
                              child: Text('${b['name'] ?? '?'}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: c.textPrimary)),
                            ),
                            Expanded(
                              child: Container(
                                height: 8,
                                decoration: BoxDecoration(
                                  color: c.trackBg,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor:
                                      ((b['count'] as num?)?.toInt() ?? 0) / maxCount,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: c.accent,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('${b['count'] ?? 0}',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: c.textSecondary)),
                          ]),
                        ),
                    ],
                    const Divider(height: 24),
                  ],
                );
              },
            ),
            Text('${context.t('room_tasks_label')} (${roomTasks.length})',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.textPrimary)),
            const SizedBox(height: 8),
            if (roomTasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                    child: Text(context.t('no_tasks'),
                        style: TextStyle(color: c.textSecondary))),
              )
            else if (data != null)
              for (final t in roomTasks)
                _RoomTaskRow(task: t, data: data, onChanged: _reload),
          ],
        ),
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBox({required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: c.pageBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w900, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: c.textSecondary)),
      ]),
    );
  }
}

class _RoomTaskRow extends StatelessWidget {
  final Task task;
  final HouseholdData data;
  final Future<void> Function() onChanged;
  const _RoomTaskRow({required this.task, required this.data, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = context.ch;
    final app = context.read<AppState>();
    final done = data.isDoneToday(task.id);
    final canDo = !done && canCompleteTask(data, task);
    final assignee =
        task.assignedTo.isNotEmpty ? data.memberById(task.assignedTo) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          TaskCheckbox(
            done: done,
            locked: !done && !canDo,
            size: 26,
            onTap: done
                ? () async {
                    await uncompleteTaskFlow(context, app, task);
                    await onChanged();
                  }
                : (canDo
                    ? () async {
                        await completeTaskFlow(context, app, task);
                        await onChanged();
                      }
                    : null),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.name,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                        decoration: done ? TextDecoration.lineThrough : null)),
                Text(
                    '${assignee?.emoji ?? ''} ${assignee?.name ?? '?'} · ${fmtSchedule(context, task)}',
                    style: TextStyle(fontSize: 12.5, color: c.textSecondary)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => openTaskEditSheet(context, data, task),
            child: Icon(Icons.edit_outlined, size: 18, color: c.textFaint),
          ),
        ],
      ),
    );
  }
}

void _openAddRoom(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AddRoomSheet(),
  );
}

class _AddRoomSheet extends StatefulWidget {
  const _AddRoomSheet();
  @override
  State<_AddRoomSheet> createState() => _AddRoomSheetState();
}

class _AddRoomSheetState extends State<_AddRoomSheet> {
  final _name = TextEditingController();
  String _emoji = '🏠';
  bool _busy = false;

  static const _emojis = [
    '🍽️', '🛏️', '🛋️', '🚿', '🧸', '🚽', '🍳', '🧺', '🪴', '🚪', '🏠', '🧹'
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, context.t('give_room_name'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppState>().addRoom(_name.text.trim(), _emoji);
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, context.t('room_added'));
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
    final mq = MediaQuery.of(context);
    final bottom = mq.viewInsets.bottom > 0 ? mq.viewInsets.bottom : mq.padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
      decoration: BoxDecoration(
        color: c.pageBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: c.divider, borderRadius: BorderRadius.circular(999)),
            ),
          ),
          const SizedBox(height: 16),
          Text(context.t('new_room'),
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: c.textPrimary)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            style: TextStyle(color: c.textPrimary),
            decoration: InputDecoration(
              hintText: context.t('room_name_hint'),
              hintStyle: TextStyle(color: c.textFaint),
              filled: true,
              fillColor: c.card,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
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
                  : Text(context.t('add_room'),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
