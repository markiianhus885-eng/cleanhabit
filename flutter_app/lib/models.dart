/// Data models for the CleanHabit API payloads.
///
/// IMPORTANT: `/api/data` returns rows in snake_case, but `POST /api/tasks`
/// expects camelCase. Models parse snake_case here; the API layer sends
/// camelCase when creating.
library;

const Map<String, int> kFreqDays = {
  'daily': 1,
  'every2': 2,
  'weekly': 7,
  'biweekly': 14,
  'monthly': 30,
};

const Map<String, int> kDiffPts = {'easy': 1, 'medium': 2, 'hard': 3};

const int kDailyEffortTarget = 20;

DateTime? _parseDate(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}

bool _sameDay(DateTime? a, DateTime b) =>
    a != null && a.year == b.year && a.month == b.month && a.day == b.day;

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class CurrentUser {
  final String id;
  final String username;
  final String householdId;
  final String? memberId;
  final String role;

  CurrentUser({
    required this.id,
    required this.username,
    required this.householdId,
    this.memberId,
    required this.role,
  });

  bool get isAdmin => role == 'admin';

  factory CurrentUser.fromJson(Map<String, dynamic> j) => CurrentUser(
        id: j['id']?.toString() ?? '',
        username: j['username']?.toString() ?? '',
        householdId: j['household_id']?.toString() ?? '',
        memberId: j['member_id']?.toString(),
        role: j['role']?.toString() ?? 'member',
      );
}

class Member {
  final String id;
  final String name;
  final String emoji;
  final int points;
  final int coins;
  final int streak;
  final List<String> owned;
  final List<Badge> achievements;

  Member({
    required this.id,
    required this.name,
    required this.emoji,
    required this.points,
    required this.coins,
    required this.streak,
    required this.owned,
    required this.achievements,
  });

  factory Member.fromJson(Map<String, dynamic> j) => Member(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '?',
        emoji: j['emoji']?.toString() ?? '👤',
        points: (j['points'] ?? 0) as int,
        coins: (j['coins'] ?? 0) as int,
        streak: (j['streak'] ?? 0) as int,
        owned: (j['owned'] as List?)?.map((e) => e.toString()).toList() ?? [],
        achievements: (j['achievements'] as List?)
                ?.map((e) => Badge.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class Badge {
  final String key;
  final String name;
  final String emoji;
  final String desc;
  Badge({required this.key, required this.name, required this.emoji, required this.desc});
  factory Badge.fromJson(Map<String, dynamic> j) => Badge(
        key: j['key']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        emoji: j['emoji']?.toString() ?? '🏅',
        desc: j['desc']?.toString() ?? '',
      );
}

class Room {
  final String id;
  final String name;
  final String emoji;
  final int cleanliness; // already computed server-side in /api/data
  final DateTime? lastCleaned;

  Room({
    required this.id,
    required this.name,
    required this.emoji,
    required this.cleanliness,
    this.lastCleaned,
  });

  factory Room.fromJson(Map<String, dynamic> j) => Room(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '?',
        emoji: j['emoji']?.toString() ?? '🏠',
        cleanliness: (j['cleanliness'] ?? 100) as int,
        lastCleaned: _parseDate(j['last_cleaned']),
      );
}

class Task {
  final String id;
  final String name;
  final String roomId;
  final String assignedTo;
  final String freq;
  final String diff;
  final DateTime? lastCompleted;
  final bool approvalNeeded;
  final String? specificDays;
  final bool oneTime;
  final DateTime? createdAt;

  Task({
    required this.id,
    required this.name,
    required this.roomId,
    required this.assignedTo,
    required this.freq,
    required this.diff,
    this.lastCompleted,
    required this.approvalNeeded,
    this.specificDays,
    required this.oneTime,
    this.createdAt,
  });

  factory Task.fromJson(Map<String, dynamic> j) => Task(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        roomId: j['room_id']?.toString() ?? '',
        assignedTo: j['assigned_to']?.toString() ?? '',
        freq: j['freq']?.toString() ?? 'weekly',
        diff: j['diff']?.toString() ?? 'medium',
        lastCompleted: _parseDate(j['last_completed']),
        approvalNeeded: (j['approval_needed'] ?? 0) == 1,
        specificDays: (j['specific_days']?.toString().isEmpty ?? true)
            ? null
            : j['specific_days'].toString(),
        oneTime: (j['one_time'] ?? 0) == 1,
        createdAt: _parseDate(j['created_at']),
      );

  int get points => kDiffPts[diff] ?? 1;

  /// Difficulty as a 1-3 count (for the lightning-bolt chips).
  int get diffLevel => kDiffPts[diff] ?? 1;

  /// Mirrors the server's /api/calendar due algorithm (app.py).
  bool isDueOn(DateTime day) {
    // A completed one-time task never becomes due again; it lingers only in
    // "Done" for its completion day, then the backend sweeps it the next day.
    if (oneTime && lastCompleted != null) return false;

    final created = createdAt ?? day;
    if (_dateOnly(created).isAfter(_dateOnly(day))) return false;

    final sd = specificDays;
    if (sd != null && sd.isNotEmpty) {
      final chosen = sd
          .split(',')
          .where((x) => int.tryParse(x.trim()) != null)
          .map((x) => int.parse(x.trim()))
          .toSet();
      // Python weekday: Mon=0..Sun=6 ; Dart weekday: Mon=1..Sun=7
      return chosen.contains(day.weekday - 1);
    }

    final freqDays = kFreqDays[freq] ?? 7;
    final nextDue = lastCompleted != null
        ? lastCompleted!.add(Duration(days: freqDays))
        : created;
    final diffDays = _dateOnly(day).difference(_dateOnly(nextDue)).inDays;
    return (diffDays >= 0 && diffDays < freqDays) || freqDays == 1;
  }

  bool get dueToday => isDueOn(DateTime.now());
}

class HistoryEntry {
  final String taskId;
  final String memberId;
  final DateTime? completedAt;
  final int pts;
  final String type; // 'done' | 'missed'

  HistoryEntry({
    required this.taskId,
    required this.memberId,
    this.completedAt,
    required this.pts,
    required this.type,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        taskId: j['task_id']?.toString() ?? '',
        memberId: j['member_id']?.toString() ?? '',
        completedAt: _parseDate(j['completed_at']),
        pts: (j['pts'] ?? 0) as int,
        type: j['type']?.toString() ?? 'done',
      );

  bool get isToday => _sameDay(completedAt, DateTime.now());
}

class Goal {
  final String id;
  final String name;
  final String? description;
  final String emoji;
  final int price;
  final List<GoalPurchase> purchases;
  Goal({
    required this.id,
    required this.name,
    this.description,
    required this.emoji,
    required this.price,
    required this.purchases,
  });
  factory Goal.fromJson(Map<String, dynamic> j) => Goal(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        description: j['description']?.toString(),
        emoji: j['emoji']?.toString() ?? '🎯',
        price: (j['price'] ?? 0) as int,
        purchases: (j['purchases'] as List?)
                ?.map((e) => GoalPurchase.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class GoalPurchase {
  final String id;
  final String goalId;
  final String memberId;
  final String memberName;
  final String memberEmoji;
  final bool fulfilled;
  GoalPurchase({
    required this.id,
    required this.goalId,
    required this.memberId,
    required this.memberName,
    required this.memberEmoji,
    required this.fulfilled,
  });
  factory GoalPurchase.fromJson(Map<String, dynamic> j) => GoalPurchase(
        id: j['id']?.toString() ?? '',
        goalId: j['goal_id']?.toString() ?? '',
        memberId: j['member_id']?.toString() ?? '',
        memberName: j['member_name']?.toString() ?? '?',
        memberEmoji: j['member_emoji']?.toString() ?? '👤',
        fulfilled: (j['fulfilled'] ?? 0) == 1,
      );
}

class Approval {
  final String id;
  final String taskId;
  final String memberId;
  Approval({required this.id, required this.taskId, required this.memberId});
  factory Approval.fromJson(Map<String, dynamic> j) => Approval(
        id: j['id']?.toString() ?? '',
        taskId: j['task_id']?.toString() ?? '',
        memberId: j['member_id']?.toString() ?? '',
      );
}

/// Full /api/data payload.
class HouseholdData {
  final String household;
  final String householdToken;
  final String? adminMemberId;
  final Map<String, String> membersRoles;
  final List<Member> members;
  final List<Room> rooms;
  final List<Task> tasks;
  final List<HistoryEntry> history;
  final List<Goal> goals;
  final List<Approval> approvals;
  final CurrentUser? currentUser;

  HouseholdData({
    required this.household,
    required this.householdToken,
    required this.adminMemberId,
    required this.membersRoles,
    required this.members,
    required this.rooms,
    required this.tasks,
    required this.history,
    required this.goals,
    required this.approvals,
    required this.currentUser,
  });

  factory HouseholdData.fromJson(Map<String, dynamic> j) => HouseholdData(
        household: j['household']?.toString() ?? 'My Family',
        householdToken: j['household_token']?.toString() ?? '',
        adminMemberId: j['household_admin_member']?.toString(),
        membersRoles: (j['members_roles'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
            {},
        members: (j['members'] as List?)
                ?.map((e) => Member.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        rooms: (j['rooms'] as List?)
                ?.map((e) => Room.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        tasks: (j['tasks'] as List?)
                ?.map((e) => Task.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        history: (j['history'] as List?)
                ?.map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        goals: (j['goals'] as List?)
                ?.map((e) => Goal.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        approvals: (j['approvals'] as List?)
                ?.map((e) => Approval.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        currentUser: j['current_user'] != null &&
                (j['current_user'] as Map).isNotEmpty
            ? CurrentUser.fromJson(j['current_user'] as Map<String, dynamic>)
            : null,
      );

  Member? get me {
    final mid = currentUser?.memberId;
    if (mid == null) return null;
    for (final m in members) {
      if (m.id == mid) return m;
    }
    return null;
  }

  Member? memberById(String id) {
    for (final m in members) {
      if (m.id == id) return m;
    }
    return null;
  }

  Room? roomById(String id) {
    for (final r in rooms) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// True only for a real completion today — a skipped/missed occurrence
  /// (history type 'missed') doesn't count, even though it also touches
  /// the task's last_completed timestamp.
  bool isDoneToday(String taskId) => history.any(
      (h) => h.taskId == taskId && h.type != 'missed' && h.isToday);

  // ── Derived dashboard numbers (mirror server) ──
  List<Task> get dueTodayTasks => tasks.where((t) => t.dueToday).toList();

  int get todoCount =>
      dueTodayTasks.where((t) => !isDoneToday(t.id)).length;

  int get doneTodayCount =>
      history.where((h) => h.type == 'done' && h.isToday).length;

  int get missedTodayCount =>
      history.where((h) => h.type == 'missed' && h.isToday).length;

  int get effortToday => history
      .where((h) => h.type == 'done' && h.isToday)
      .fold(0, (sum, h) => sum + h.pts);

  int get avgCleanliness {
    if (rooms.isEmpty) return 100;
    final total = rooms.fold(0, (s, r) => s + r.cleanliness);
    return (total / rooms.length).round();
  }

  bool get amAdmin => currentUser?.isAdmin ?? false;

  /// True only for the household creator (owner) — the member whose id equals
  /// [adminMemberId]. Owner-only powers: delete goals, assign the admin role.
  bool get amOwner =>
      currentUser?.memberId != null && currentUser!.memberId == adminMemberId;
}

// ── Levels (mirror templates/index.html) ──
const List<int> kLevelPts = [0, 50, 150, 350, 700, 1200, 2000, 3500, 5000];
const List<String> kLevelNames = [
  'Beginner', 'Helper', 'Cleaner', 'Pro Cleaner', 'Expert',
  'Master', 'Champion', 'Legend', 'Grandmaster'
];
const List<String> kLevelIcons = ['🌱', '🧹', '🫧', '⭐', '💎', '🏅', '👑', '🏆', '✨'];
const List<String> kMemberEmojis = [
  '😊', '😎', '🤩', '🥳', '😄', '👩', '👨', '👧', '👦', '🧑',
  '🐶', '🐱', '🐼', '🐰', '🦊', '🤖', '👾', '🦸', '🧙', '🥷'
];

int levelOf(int pts) {
  int l = 0;
  for (int i = 0; i < kLevelPts.length; i++) {
    if (pts >= kLevelPts[i]) l = i;
  }
  return l;
}

String levelName(int pts) => kLevelNames[levelOf(pts)];
String levelIcon(int pts) => kLevelIcons[levelOf(pts)];

/// Progress 0..1 toward the next level (1.0 if max level).
double levelProgress(int pts) {
  final l = levelOf(pts);
  if (l + 1 >= kLevelPts.length) return 1.0;
  final cur = kLevelPts[l], next = kLevelPts[l + 1];
  return ((pts - cur) / (next - cur)).clamp(0, 1);
}

/// Points still needed for next level, or null at max.
int? ptsToNext(int pts) {
  final l = levelOf(pts);
  if (l + 1 >= kLevelPts.length) return null;
  return kLevelPts[l + 1] - pts;
}

// ── Badge catalog (English; mirrors backend BADGES keys/emojis) ──
class BadgeDef {
  final String key;
  final String emoji;
  final String name;
  final String desc;
  final String category;
  const BadgeDef(this.key, this.emoji, this.name, this.desc, this.category);
}

const List<BadgeDef> kBadgeCatalog = [
  BadgeDef('first_step', '👟', 'First Step', 'Complete your first task', 'First steps'),
  BadgeDef('tasks_10', '⚡', 'Hardworking', 'Complete 10 tasks', 'First steps'),
  BadgeDef('tasks_50', '🦸', 'Superhero', 'Complete 50 tasks', 'First steps'),
  BadgeDef('tasks_100', '👑', 'Legend', 'Complete 100 tasks', 'First steps'),
  BadgeDef('streak_3', '🔥', '3-Day Streak', '3 days in a row', 'Day streaks'),
  BadgeDef('streak_7', '🔥', 'Week Streak', '7 days in a row', 'Day streaks'),
  BadgeDef('streak_30', '💎', 'Unbreakable', '30 days in a row', 'Day streaks'),
  BadgeDef('daily_5', '⚡', 'Lightning', '5 tasks in one day', 'Special'),
  BadgeDef('perfect_room', '✨', 'Perfectionist', 'Get a room to 100%', 'Special'),
  BadgeDef('hard_worker', '💪', 'Tough', 'Complete 5 hard tasks', 'Special'),
  BadgeDef('week_champ', '🏆', 'Cleaner of the Week', 'Most points this week', 'Special'),
  BadgeDef('month_champ', '🥇', 'Master of the Month', 'Most points this month', 'Special'),
  BadgeDef('early_bird', '🐦', 'Early Bird', 'A task before 9:00', 'Special'),
  BadgeDef('night_owl', '🦉', 'Night Owl', 'A task after 22:00', 'Special'),
];

final Map<String, BadgeDef> kBadgeByKey = {for (final b in kBadgeCatalog) b.key: b};

// ── Leaderboard ──
class LeaderEntry {
  final String id;
  final String name;
  final String emoji;
  final int points;
  final int coins;
  final int streak;
  final int periodPts;
  final bool isAdmin;
  final List<Badge> achievements;
  LeaderEntry({
    required this.id,
    required this.name,
    required this.emoji,
    required this.points,
    required this.coins,
    required this.streak,
    required this.periodPts,
    required this.isAdmin,
    required this.achievements,
  });
  factory LeaderEntry.fromJson(Map<String, dynamic> j) => LeaderEntry(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '?',
        emoji: j['emoji']?.toString() ?? '👤',
        points: (j['points'] ?? 0) as int,
        coins: (j['coins'] ?? 0) as int,
        streak: (j['streak'] ?? 0) as int,
        periodPts: (j['period_pts'] ?? 0) as int,
        isAdmin: j['is_admin'] == true,
        achievements: (j['achievements'] as List?)
                ?.map((e) => Badge.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

// ── Calendar ──
class CalendarDay {
  final DateTime date;
  final bool isToday;
  final List<CalendarTask> tasks;
  CalendarDay({required this.date, required this.isToday, required this.tasks});
  factory CalendarDay.fromJson(Map<String, dynamic> j) => CalendarDay(
        date: DateTime.parse(j['date'].toString()),
        isToday: j['is_today'] == true,
        tasks: (j['tasks'] as List?)
                ?.map((e) => CalendarTask.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
  int get doneCount => tasks.where((t) => t.done).length;
}

class CalendarTask {
  final String id;
  final String name;
  final String diff;
  final String memberName;
  final String memberEmoji;
  final String roomName;
  final bool done;
  CalendarTask({
    required this.id,
    required this.name,
    required this.diff,
    required this.memberName,
    required this.memberEmoji,
    required this.roomName,
    required this.done,
  });
  factory CalendarTask.fromJson(Map<String, dynamic> j) => CalendarTask(
        id: j['id']?.toString() ?? '',
        name: j['name']?.toString() ?? '',
        diff: j['diff']?.toString() ?? 'medium',
        memberName: j['member_name']?.toString() ?? '?',
        memberEmoji: j['member_emoji']?.toString() ?? '👤',
        roomName: j['room_name']?.toString() ?? '',
        done: j['done'] == true,
      );
}
