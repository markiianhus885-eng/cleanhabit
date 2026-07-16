import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'models.dart';

enum AuthStatus { loading, loggedOut, loggedIn }

class AppState extends ChangeNotifier {
  final Api api;
  final SharedPreferences prefs;

  AppState(this.api, this.prefs) {
    final saved = prefs.getString('themeMode');
    _themeMode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light, // Playful redesign is light-first
    };
    _lang = prefs.getString('lang') ?? 'en';
    _bootstrap();
  }

  String _lang = 'en';
  String get lang => _lang;
  void setLang(String lang) {
    _lang = lang;
    prefs.setString('lang', lang);
    notifyListeners();
  }

  AuthStatus _status = AuthStatus.loading;
  AuthStatus get status => _status;
  bool get isLoggedIn => _status == AuthStatus.loggedIn;

  HouseholdData? _data;
  HouseholdData? get data => _data;

  bool _refreshing = false;
  bool get refreshing => _refreshing;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  Future<void> _bootstrap() async {
    try {
      final user = await api.me();
      if (user != null) {
        await refresh();
        _status = AuthStatus.loggedIn;
      } else {
        _status = AuthStatus.loggedOut;
      }
    } catch (_) {
      _status = AuthStatus.loggedOut;
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    _refreshing = true;
    notifyListeners();
    try {
      final raw = await api.data();
      _data = HouseholdData.fromJson(raw);
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    await api.login(username, password);
    await refresh();
    _status = AuthStatus.loggedIn;
    notifyListeners();
  }

  /// Returns the raw response so the caller can tell a completed signup
  /// (`user`/`household` present, already logged in) apart from a pending
  /// one (`pending_verification: true` — a code was emailed, call
  /// [verifyEmail] once the user enters it).
  Future<Map<String, dynamic>> register(Map<String, dynamic> body) async {
    final res = await api.register(body);
    if (res['pending_verification'] == true) return res;
    await refresh();
    _status = AuthStatus.loggedIn;
    notifyListeners();
    return res;
  }

  Future<void> verifyEmail(String email, String code) async {
    await api.verifyEmail(email, code);
    await refresh();
    _status = AuthStatus.loggedIn;
    notifyListeners();
  }

  /// Returns the raw response — `needs_setup: true` means the caller must
  /// collect create/join household details and call again via [googleAuth].
  Future<Map<String, dynamic>> googleAuth(String idToken,
      [Map<String, dynamic>? extra]) async {
    final res = await api.googleAuth(idToken, extra);
    if (res['needs_setup'] == true) return res;
    await refresh();
    _status = AuthStatus.loggedIn;
    notifyListeners();
    return res;
  }

  Future<void> logout() async {
    // The session may already be gone server-side even if this request
    // fails or hangs (flaky network, etc) — cap the wait so the UI can
    // never be stranded on the logged-in screen forever.
    try {
      await api.logout().timeout(const Duration(seconds: 3));
    } catch (_) {}
    _data = null;
    _status = AuthStatus.loggedOut;
    notifyListeners();
  }

  // ── Mutations: call API then refresh so derived numbers stay correct ──
  Future<Map<String, dynamic>> completeTask(String id, {String? memberId}) async {
    final res = await api.completeTask(id, memberId: memberId);
    await refresh();
    return res;
  }

  Future<void> uncompleteTask(String id) async {
    await api.uncompleteTask(id);
    await refresh();
  }

  Future<void> deleteTask(String id) async {
    await api.deleteTask(id);
    await refresh();
  }

  /// "Delete only this occurrence" of a recurring task — skips its next
  /// cycle without deleting the task definition itself. Pass the specific
  /// calendar day (YYYY-MM-DD) being skipped so the right occurrence is
  /// affected, not just whatever's due "now".
  Future<void> expireTask(String id, {String? date}) async {
    await api.expireTask(id, date: date);
    await refresh();
  }

  Future<Map<String, dynamic>> roomStats(String id) => api.roomStats(id);

  Future<void> addTask({
    required String name,
    required String roomId,
    required String assignedTo,
    required String freq,
    required String diff,
    bool approvalNeeded = false,
    bool oneTime = false,
    String? specificDays,
    String? dueDate,
  }) async {
    await api.addTask(
      name: name,
      roomId: roomId,
      assignedTo: assignedTo,
      freq: freq,
      diff: diff,
      approvalNeeded: approvalNeeded,
      oneTime: oneTime,
      specificDays: specificDays,
      dueDate: dueDate,
    );
    await refresh();
  }

  Future<void> editTask({
    required String id,
    required String name,
    required String roomId,
    required String assignedTo,
    required String freq,
    required String diff,
    bool approvalNeeded = false,
    bool oneTime = false,
    String? specificDays,
  }) async {
    await api.editTask(
      id: id,
      name: name,
      roomId: roomId,
      assignedTo: assignedTo,
      freq: freq,
      diff: diff,
      approvalNeeded: approvalNeeded,
      oneTime: oneTime,
      specificDays: specificDays,
    );
    await refresh();
  }

  Future<void> addRoom(String name, String emoji) async {
    await api.addRoom(name, emoji);
    await refresh();
  }

  Future<void> deleteRoom(String id) async {
    await api.deleteRoom(id);
    await refresh();
  }

  Future<void> renameHousehold(String name) async {
    await api.renameHousehold(name);
    await refresh();
  }

  Future<void> addMember(String name, String emoji) async {
    await api.addMember(name, emoji);
    await refresh();
  }

  Future<void> deleteMember(String id) async {
    await api.deleteMember(id);
    await refresh();
  }

  Future<void> setMemberRole(String id, String role) async {
    await api.setMemberRole(id, role);
    await refresh();
  }

  Future<void> addGoal(String name, String emoji, int price, String description) async {
    await api.addGoal(name, emoji, price, description);
    await refresh();
  }

  Future<void> deleteGoal(String id) async {
    await api.deleteGoal(id);
    await refresh();
  }

  Future<Map<String, dynamic>> buyGoal(String id) async {
    final res = await api.buyGoal(id);
    await refresh();
    return res;
  }

  Future<void> fulfillPurchase(String id) async {
    await api.fulfillPurchase(id);
    await refresh();
  }

  Future<void> approve(String id, bool approved) async {
    await api.approve(id, approved);
    await refresh();
  }

  /// Sends a voice/text command; refreshes if it changed data.
  Future<Map<String, dynamic>> voice(String transcript) async {
    final res = await api.voice(transcript);
    final action = res['action'];
    if (action == 'add_task' || action == 'complete_task') {
      await refresh();
    }
    return res;
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    prefs.setString('themeMode', switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
    notifyListeners();
  }
}
