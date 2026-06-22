import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Thin wrapper around the existing Flask JSON API.
///
/// Auth is the backend's cookie session: a [PersistCookieJar] keeps the
/// session cookie on disk so the user stays logged in across restarts.
class Api {
  static const String baseUrl = 'https://cleanhouse.myroapp.org';

  late final Dio _dio;
  late final PersistCookieJar _jar;

  Api._();

  static Future<Api> create() async {
    final api = Api._();
    final dir = await getApplicationDocumentsDirectory();
    api._jar = PersistCookieJar(
      storage: FileStorage('${dir.path}/.cookies'),
    );
    api._dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Content-Type': 'application/json'},
      // We handle non-2xx ourselves so we can surface the server's error text.
      validateStatus: (s) => s != null && s < 500,
    ));
    api._dio.interceptors.add(CookieManager(api._jar));
    return api;
  }

  /// Extracts the server's `{error: ...}` message, or a generic fallback.
  static String _err(Response r) {
    final data = r.data;
    if (data is Map && data['error'] != null) return data['error'].toString();
    return 'Something went wrong (${r.statusCode}).';
  }

  // ── AUTH ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> login(String username, String password) async {
    final r = await _dio.post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });
    if (r.statusCode == 200 && r.data['ok'] == true) {
      return Map<String, dynamic>.from(r.data);
    }
    throw ApiException(_err(r));
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> body) async {
    final r = await _dio.post('/api/auth/register', data: body);
    if (r.statusCode == 200 && r.data['ok'] == true) {
      return Map<String, dynamic>.from(r.data);
    }
    throw ApiException(_err(r));
  }

  Future<void> logout() async {
    await _dio.post('/api/auth/logout');
    await _jar.deleteAll();
  }

  /// Returns the `user` map if a session is active, else null.
  Future<Map<String, dynamic>?> me() async {
    final r = await _dio.get('/api/auth/me');
    if (r.statusCode == 200 && r.data['user'] != null) {
      return Map<String, dynamic>.from(r.data['user']);
    }
    return null;
  }

  Future<Map<String, dynamic>> householdLookup(String token) async {
    final r = await _dio.get('/api/household/lookup',
        queryParameters: {'token': token});
    if (r.statusCode == 200) return Map<String, dynamic>.from(r.data);
    throw ApiException(_err(r));
  }

  // ── DATA ──────────────────────────────────────────────────────
  Future<Map<String, dynamic>> data() async {
    final r = await _dio.get('/api/data');
    if (r.statusCode == 200) return Map<String, dynamic>.from(r.data);
    throw ApiException(_err(r));
  }

  // ── TASKS (note: POST expects camelCase) ──────────────────────
  Future<void> addTask({
    required String name,
    required String roomId,
    required String assignedTo,
    required String freq,
    required String diff,
    bool approvalNeeded = false,
    bool oneTime = false,
    String? specificDays,
  }) async {
    final r = await _dio.post('/api/tasks', data: {
      'name': name,
      'roomId': roomId,
      'assignedTo': assignedTo,
      'freq': freq,
      'diff': diff,
      'approvalNeeded': approvalNeeded,
      'oneTime': oneTime,
      if (specificDays != null) 'specificDays': specificDays,
    });
    if (r.statusCode != 200) throw ApiException(_err(r));
  }

  /// Returns the server response (may contain `pending_approval`, `pts`, ...).
  Future<Map<String, dynamic>> completeTask(String id, {String? memberId}) async {
    final r = await _dio.post('/api/tasks/$id/complete',
        data: {if (memberId != null) 'memberId': memberId});
    if (r.statusCode == 200) return Map<String, dynamic>.from(r.data);
    throw ApiException(_err(r));
  }

  Future<void> deleteTask(String id) async {
    final r = await _dio.delete('/api/tasks/$id');
    if (r.statusCode != 200) throw ApiException(_err(r));
  }

  // ── ROOMS ─────────────────────────────────────────────────────
  Future<void> addRoom(String name, String emoji) async {
    final r = await _dio.post('/api/rooms', data: {'name': name, 'emoji': emoji});
    if (r.statusCode != 200) throw ApiException(_err(r));
  }

  Future<void> deleteRoom(String id) async {
    final r = await _dio.delete('/api/rooms/$id');
    if (r.statusCode != 200) throw ApiException(_err(r));
  }

  // ── HOUSEHOLD ─────────────────────────────────────────────────
  Future<void> renameHousehold(String name) async {
    final r = await _dio.put('/api/household', data: {'name': name});
    if (r.statusCode != 200) throw ApiException(_err(r));
  }

  // ── MEMBERS ───────────────────────────────────────────────────
  Future<void> addMember(String name, String emoji) async {
    final r = await _dio.post('/api/members', data: {'name': name, 'emoji': emoji});
    if (r.statusCode != 200) throw ApiException(_err(r));
  }

  Future<void> deleteMember(String id) async {
    final r = await _dio.delete('/api/members/$id');
    if (r.statusCode != 200) throw ApiException(_err(r));
  }

  Future<void> setMemberRole(String id, String role) async {
    final r = await _dio.put('/api/members/$id/role', data: {'role': role});
    if (r.statusCode != 200) throw ApiException(_err(r));
  }

  // ── LEADERBOARD ───────────────────────────────────────────────
  Future<List<dynamic>> leaderboard(String period) async {
    final r = await _dio.get('/api/leaderboard', queryParameters: {'period': period});
    if (r.statusCode == 200) return r.data as List<dynamic>;
    throw ApiException(_err(r));
  }

  // ── CALENDAR ──────────────────────────────────────────────────
  Future<List<dynamic>> calendar(int year, int month) async {
    final r = await _dio.get('/api/calendar',
        queryParameters: {'year': year, 'month': month});
    if (r.statusCode == 200) return r.data as List<dynamic>;
    throw ApiException(_err(r));
  }

  // ── GOALS ─────────────────────────────────────────────────────
  Future<void> addGoal(String name, String emoji, int price, String description) async {
    final r = await _dio.post('/api/goals',
        data: {'name': name, 'emoji': emoji, 'price': price, 'description': description});
    if (r.statusCode != 200) throw ApiException(_err(r));
  }

  Future<void> deleteGoal(String id) async {
    final r = await _dio.delete('/api/goals/$id');
    if (r.statusCode != 200) throw ApiException(_err(r));
  }

  Future<Map<String, dynamic>> buyGoal(String id) async {
    final r = await _dio.post('/api/goals/$id/buy');
    if (r.statusCode == 200) return Map<String, dynamic>.from(r.data);
    throw ApiException(_err(r));
  }

  Future<void> fulfillPurchase(String purchaseId) async {
    final r = await _dio.post('/api/goal-purchases/$purchaseId/fulfill');
    if (r.statusCode != 200) throw ApiException(_err(r));
  }

  // ── VOICE ─────────────────────────────────────────────────────
  Future<Map<String, dynamic>> voice(String transcript) async {
    final r = await _dio.post('/api/voice', data: {'transcript': transcript});
    if (r.statusCode == 200) return Map<String, dynamic>.from(r.data);
    throw ApiException(_err(r));
  }

  // ── APPROVALS ─────────────────────────────────────────────────
  Future<void> approve(String id, bool approved) async {
    final r = await _dio.post('/api/approvals/$id/approve', data: {'approved': approved});
    if (r.statusCode != 200) throw ApiException(_err(r));
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}
