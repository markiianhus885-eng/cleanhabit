import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api.dart';
import '../l10n.dart';
import '../models.dart';
import '../state.dart';
import '../templates.dart';
import '../theme.dart';
import '../widgets.dart';
import 'task_actions.dart';

enum _Filter { all, today, done }

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  _Filter _filter = _Filter.all;
  String _diff = 'all'; // all | easy | medium | hard
  String? _memberFilter; // null = not yet initialized; 'all' = everyone

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final data = app.data;
    final c = context.ch;
    if (data == null) return const Loader();

    _memberFilter ??= data.me?.id ?? 'all';

    Iterable<Task> tasks = data.tasks;
    if (_filter == _Filter.today) {
      tasks = tasks.where((t) => t.dueToday && !data.isDoneToday(t.id));
    } else if (_filter == _Filter.done) {
      tasks = tasks.where((t) => data.isDoneToday(t.id));
    }
    if (_diff != 'all') tasks = tasks.where((t) => t.diff == _diff);
    if (_memberFilter != 'all') {
      tasks = tasks.where(
          (t) => t.assignedTo.isEmpty || t.assignedTo == _memberFilter);
    }
    final list = tasks.toList();

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
                        Text(context.t('quest_board'),
                            style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: c.textPrimary,
                                letterSpacing: -0.5)),
                        const SizedBox(height: 2),
                        Text(context.t('quest_board_sub'),
                            style: TextStyle(
                                fontSize: 13.5, color: c.textSecondary)),
                      ],
                    ),
                  ),
                  HeaderAddButton(onTap: () => _openAddSheet(context, data)),
                ],
              ),
              const SizedBox(height: 14),

              _memberChips(c, data),
              const SizedBox(height: 10),
              _segmented(c),
              const SizedBox(height: 14),
              _diffChips(c),
              const SizedBox(height: 12),

              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(context.t('no_tasks'),
                        style: TextStyle(color: c.textSecondary)),
                  ),
                )
              else
                for (final t in list) ...[
                  _TaskRow(task: t, data: data),
                  const SizedBox(height: 12),
                ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _segmented(ChColors c) {
    Widget seg(String label, _Filter f) {
      final sel = _filter == f;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _filter = f),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: sel ? c.card : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              boxShadow: sel && Theme.of(context).brightness == Brightness.light
                  ? [
                      const BoxShadow(
                          color: Color(0x0F142819),
                          blurRadius: 2,
                          offset: Offset(0, 1))
                    ]
                  : null,
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
                    color: sel ? c.textPrimary : c.textSecondary)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.light
            ? const Color(0xFFEBEFEC)
            : c.card,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(children: [
        seg(context.t('seg_all'), _Filter.all),
        seg(context.t('seg_today'), _Filter.today),
        seg(context.t('seg_done'), _Filter.done),
      ]),
    );
  }

  Widget _memberChips(ChColors c, HouseholdData data) {
    Widget chip(String label, String value) {
      final sel = _memberFilter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _memberFilter = value),
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip(context.t('all'), 'all'),
        for (final m in data.members) chip('${m.emoji} ${m.name}', m.id),
      ]),
    );
  }

  Widget _diffChips(ChColors c) {
    Widget chip(String label, String value, int bolts) {
      final sel = _diff == value;
      return GestureDetector(
        onTap: () => setState(() => _diff = value),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: sel ? c.accent : c.card,
            borderRadius: BorderRadius.circular(999),
            boxShadow: !sel && Theme.of(context).brightness == Brightness.light
                ? [
                    const BoxShadow(
                        color: Color(0x0D142819),
                        blurRadius: 2,
                        offset: Offset(0, 1))
                  ]
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (bolts > 0) ...[
              DifficultyBolts(
                  level: bolts, color: sel ? Colors.white : c.star),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: sel
                        ? Colors.white
                        : (bolts > 0 ? c.textSecondary : c.textSecondary))),
          ]),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip(context.t('seg_all'), 'all', 0),
        chip(context.t('diff_easy'), 'easy', 1),
        chip(context.t('diff_medium'), 'medium', 2),
        chip(context.t('diff_hard'), 'hard', 3),
      ]),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Task task;
  final HouseholdData data;
  const _TaskRow({required this.task, required this.data});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final c = context.ch;
    final done = data.isDoneToday(task.id);
    final qi = questIcon(context, task);
    final xp = task.points;
    final canDo = canCompleteTask(data, task);
    final pendingApproval = data.approvals.any((a) => a.taskId == task.id);
    final assignee = task.assignedTo.isNotEmpty
        ? data.memberById(task.assignedTo)
        : null;

    return GestureDetector(
      onLongPress: () => _confirmDelete(context, app, task),
      child: QuestTile(
        icon: qi.icon,
        iconColor: qi.color,
        title: task.name,
        done: done,
        doneLabel: context.t('claimed_xp', {'n': xp}),
        onTap: done
            ? () => uncompleteTaskFlow(context, app, task)
            : (!canDo || pendingApproval
                ? null
                : () => completeTaskFlow(context, app, task)),
        trailing: done
            ? TaskCheckbox(
                done: true,
                size: 28,
                onTap: () => uncompleteTaskFlow(context, app, task),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TaskCheckbox(
                    done: false,
                    pendingApproval: pendingApproval,
                    locked: !canDo,
                    size: 28,
                    onTap: canDo && !pendingApproval
                        ? () => completeTaskFlow(context, app, task)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => openTaskEditSheet(context, data, task),
                    child: Icon(Icons.edit_outlined, size: 18, color: c.textFaint),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _confirmDelete(context, app, task),
                    child: const Text('✕',
                        style: TextStyle(
                            color: Color(0xFFE5557A),
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
        subtitle: Wrap(
          spacing: 7,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            RewardTags(xp: xp, coins: task.points),
            DiffTag(
              diffLevel: task.diffLevel,
              quickLabel: context.t('q_quick'),
              epicLabel: context.t('q_epic'),
            ),
            if (assignee != null)
              Text(assignee.emoji, style: const TextStyle(fontSize: 13)),
            Text(fmtSchedule(context, task),
                style: TextStyle(fontSize: 11.5, color: c.textSecondary)),
            if (pendingApproval)
              Text('⏳ ${context.t('task_pending_approval')}',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: c.star))
            else if (task.approvalNeeded)
              Text('🔒 ${context.t('task_acceptance')}',
                  style: TextStyle(fontSize: 11.5, color: c.star)),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AppState app, Task task) async {
    final c = context.ch;
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
    }
  }
}

void _openAddSheet(BuildContext context, HouseholdData data) =>
    openTaskAddSheet(context, data);

Future<void> openTaskAddSheet(BuildContext context, HouseholdData data,
    {DateTime? forDate}) async {
  if (data.rooms.isEmpty) {
    showSnack(context, context.t('add_room_first'), error: true);
    return;
  }
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddTaskSheet(data: data, initialDueDate: forDate),
  );
}

void openTaskEditSheet(BuildContext context, HouseholdData data, Task task) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddTaskSheet(data: data, existingTask: task),
  );
}

class _AddTaskSheet extends StatefulWidget {
  final HouseholdData data;
  final Task? existingTask;
  final DateTime? initialDueDate;
  const _AddTaskSheet({required this.data, this.existingTask, this.initialDueDate});
  @override
  State<_AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<_AddTaskSheet> {
  final _name = TextEditingController();
  String? _roomId;
  String? _assignedTo;
  String _freq = 'weekly';
  String _diff = 'easy';
  bool _approval = false;
  bool _oneTime = false;
  bool _busy = false;
  bool _showSugg = false;

  bool get _isEdit => widget.existingTask != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existingTask;
    if (t != null) {
      _name.text = t.name;
      _roomId = t.roomId.isNotEmpty ? t.roomId : null;
      _assignedTo = t.assignedTo.isNotEmpty ? t.assignedTo : null;
      _freq = kFreqDays.containsKey(t.freq) ? t.freq : 'weekly';
      _diff = t.diff;
      _approval = t.approvalNeeded;
      _oneTime = t.oneTime;
    } else if (widget.data.rooms.isNotEmpty) {
      _roomId = widget.data.rooms.first.id;
      if (widget.initialDueDate != null) _oneTime = true;
    }
    if (_assignedTo == null && widget.data.members.isNotEmpty) {
      _assignedTo = widget.data.members.first.id;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      showSnack(context, context.t('give_task_name'), error: true);
      return;
    }
    if (_roomId == null) {
      showSnack(context, context.t('add_room_first'), error: true);
      return;
    }
    if (_assignedTo == null || _assignedTo!.isEmpty) {
      showSnack(context, context.t('assign_someone_first'), error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isEdit) {
        await context.read<AppState>().editTask(
              id: widget.existingTask!.id,
              name: _name.text.trim(),
              roomId: _roomId!,
              assignedTo: _assignedTo!,
              freq: _freq,
              diff: _diff,
              approvalNeeded: _approval,
              oneTime: _oneTime,
            );
      } else {
        final due = widget.initialDueDate;
        await context.read<AppState>().addTask(
              name: _name.text.trim(),
              roomId: _roomId!,
              assignedTo: _assignedTo!,
              freq: _freq,
              diff: _diff,
              approvalNeeded: _approval,
              oneTime: _oneTime,
              dueDate: due == null
                  ? null
                  : '${due.year.toString().padLeft(4, '0')}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}',
            );
      }
      if (mounted) {
        Navigator.pop(context);
        showSnack(context, context.t(_isEdit ? 'task_saved' : 'task_added'));
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
                    borderRadius: BorderRadius.circular(999)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(context.t(_isEdit ? 'modal_edit_task' : 'new_task'),
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _showSugg = !_showSugg),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _showSugg ? c.accent : c.card,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('💡', style: TextStyle(fontSize: 13)),
                      const SizedBox(width: 5),
                      Text(context.t('task_suggestions'),
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: _showSugg ? Colors.white : c.textSecondary)),
                    ]),
                  ),
                ),
              ],
            ),
            if (_showSugg) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: taskSuggestions(context.read<AppState>().lang)
                    .map((s) => GestureDetector(
                          onTap: () => setState(() {
                            _name.text = s.name;
                            _diff = s.diff;
                            _showSugg = false;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: c.card,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Flexible(
                                child: Text(s.name,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: c.textPrimary)),
                              ),
                              const SizedBox(width: 6),
                              DifficultyBolts(
                                  level: kDiffPts[s.diff] ?? 1, size: 11),
                              const SizedBox(width: 3),
                              Text('+${kDiffPts[s.diff] ?? 1}',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: c.successPillText)),
                            ]),
                          ),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 16),
            _label(c, context.t('task_label')),
            TextField(
              controller: _name,
              style: TextStyle(color: c.textPrimary),
              decoration: _dec(c, context.t('task_hint')),
            ),
            const SizedBox(height: 14),
            _label(c, context.t('room_label')),
            _dropdown<String>(
              c,
              value: _roomId,
              hint: context.t('select_room'),
              items: widget.data.rooms
                  .map((r) => DropdownMenuItem(
                      value: r.id, child: Text('${r.emoji}  ${r.name}')))
                  .toList(),
              onChanged: (v) => setState(() => _roomId = v),
            ),
            const SizedBox(height: 14),
            _label(c, context.t('assign_to')),
            _dropdown<String>(
              c,
              value: _assignedTo,
              hint: context.t('select_member'),
              items: widget.data.members
                  .map((m) => DropdownMenuItem(
                      value: m.id, child: Text('${m.emoji}  ${m.name}')))
                  .toList(),
              onChanged: (v) => setState(() => _assignedTo = v),
            ),
            if (!_oneTime) ...[
              const SizedBox(height: 14),
              _label(c, context.t('repeats')),
              _dropdown<String>(
                c,
                value: _freq,
                items: const ['daily', 'every2', 'weekly', 'biweekly', 'monthly']
                    .map((k) =>
                        DropdownMenuItem(value: k, child: Text(freqLabel(context, k))))
                    .toList(),
                onChanged: (v) => setState(() => _freq = v ?? 'weekly'),
              ),
            ],
            const SizedBox(height: 14),
            _label(c, context.t('difficulty')),
            Row(
              children: [
                for (final e in const [
                  ['easy', 'Easy', 1],
                  ['medium', 'Medium', 2],
                  ['hard', 'Hard', 3],
                ])
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _diff = e[0] as String),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _diff == e[0] ? c.accent : c.card,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(children: [
                          DifficultyBolts(
                              level: e[2] as int,
                              color: _diff == e[0] ? Colors.white : c.star),
                          const SizedBox(height: 4),
                          Text(diffLabel(context, e[0] as String),
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: _diff == e[0]
                                      ? Colors.white
                                      : c.textSecondary)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: c.accent,
              value: _approval,
              onChanged: (v) => setState(() => _approval = v),
              title: Text(context.t('needs_approval'),
                  style: TextStyle(color: c.textPrimary, fontSize: 14)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: c.accent,
              value: _oneTime,
              onChanged: (v) => setState(() => _oneTime = v),
              title: Text(context.t('one_time'),
                  style: TextStyle(color: c.textPrimary, fontSize: 14)),
            ),
            const SizedBox(height: 12),
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
                    : Text(context.t(_isEdit ? 'modal_task_save_btn' : 'add_task'),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(ChColors c, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: c.textSecondary)),
      );

  InputDecoration _dec(ChColors c, String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: c.textFaint),
        filled: true,
        fillColor: c.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );

  Widget _dropdown<T>(
    ChColors c, {
    required T? value,
    String? hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          hint: hint != null
              ? Text(hint, style: TextStyle(color: c.textFaint))
              : null,
          dropdownColor: c.card,
          style: TextStyle(color: c.textPrimary, fontSize: 14),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}
