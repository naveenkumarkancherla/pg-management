import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// Android emulator reaches the host at 10.0.2.2; iOS sim / desktop use 127.0.0.1.
// flutter run --dart-define=API_BASE=http://10.0.2.2:8000
const apiBase = String.fromEnvironment('API_BASE', defaultValue: 'http://127.0.0.1:8000');

class ApiException implements Exception {
  final int status;
  final String body;
  ApiException(this.status, this.body);

  @override
  String toString() {
    try {
      final j = jsonDecode(body);
      if (j is Map) {
        if (j['detail'] != null) return j['detail'].toString();
        final first = j.values.isNotEmpty ? j.values.first : null;
        if (first is List && first.isNotEmpty) return first.first.toString();
        if (first != null) return first.toString();
      }
    } catch (_) {}
    if (status == 0) return 'Cannot reach the server. Is the backend running?';
    return 'Something went wrong (error $status).';
  }
}

enum _Refresh { ok, invalid, network }

class Api {
  static const _storage = FlutterSecureStorage();

  /// Set by main(): called when refresh fails and the user must log in again.
  static void Function()? onSessionExpired;

  static Future<bool> isLoggedIn() async => (await _storage.read(key: 'access')) != null;
  static Future<void> logout() async => _storage.deleteAll();

  static Future<Map<String, String>> _headers({bool json = true}) async {
    final t = await _storage.read(key: 'access');
    return {
      if (json) 'Content-Type': 'application/json',
      if (t != null) 'Authorization': 'Bearer $t',
    };
  }

  static Uri _uri(String path, [Map<String, dynamic>? q]) {
    final query = q?.map((k, v) => MapEntry(k, '$v'));
    return Uri.parse('$apiBase$path').replace(queryParameters: query);
  }

  /// Runs an authenticated request; on 401 tries a silent refresh once, then retries.
  /// The session is cleared ONLY when the server definitively rejects the refresh token
  /// (a true 401). Network/timeout failures (e.g. a sleeping server) keep the session and
  /// surface a friendly network error — the user is never logged out by a transient blip.
  static Future<http.Response> _send(
      Future<http.Response> Function(Map<String, String>) call,
      {bool json = true}) async {
    http.Response r;
    try {
      r = await call(await _headers(json: json));
    } catch (_) {
      throw ApiException(0, '');
    }
    if (r.statusCode != 401) return r;

    final refresh = await _tryRefresh();
    if (refresh == _Refresh.ok) {
      try {
        r = await call(await _headers(json: json));
      } catch (_) {
        throw ApiException(0, '');
      }
      if (r.statusCode != 401) return r;
      // still 401 with a fresh token → genuinely unauthorized → fall through to logout
    } else if (refresh == _Refresh.network) {
      throw ApiException(0, ''); // couldn't reach refresh (server waking) — keep session
    }

    await logout();
    onSessionExpired?.call();
    throw ApiException(401, '{"detail":"Your session expired. Please log in again."}');
  }

  static Future<_Refresh> _tryRefresh() async {
    final rt = await _storage.read(key: 'refresh');
    if (rt == null) return _Refresh.invalid;
    http.Response r;
    try {
      r = await http.post(_uri('/api/auth/refresh/'),
          headers: {'Content-Type': 'application/json'}, body: jsonEncode({'refresh': rt}));
    } catch (_) {
      return _Refresh.network; // network/timeout → do NOT clear the session
    }
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body);
      await _storage.write(key: 'access', value: data['access']);
      if (data['refresh'] != null) await _storage.write(key: 'refresh', value: data['refresh']);
      return _Refresh.ok;
    }
    return _Refresh.invalid; // server rejected the refresh token → real session end
  }

  static dynamic _decode(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return r.body.isEmpty ? null : jsonDecode(r.body);
    }
    throw ApiException(r.statusCode, r.body);
  }

  // --- auth (no token needed) ---
  static Future<void> register(String email, String password, String phone) async {
    final http.Response r;
    try {
      r = await http.post(_uri('/api/auth/register/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password, 'phone': phone}));
    } catch (_) {
      throw ApiException(0, '');
    }
    _decode(r);
  }

  static Future<void> login(String email, String password) async {
    final http.Response r;
    try {
      r = await http.post(_uri('/api/auth/login/'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}));
    } catch (_) {
      throw ApiException(0, '');
    }
    final data = _decode(r);
    await _storage.write(key: 'access', value: data['access']);
    await _storage.write(key: 'refresh', value: data['refresh']);
  }

  // --- generic verbs (auto-refresh) ---
  static Future<dynamic> get(String path, [Map<String, dynamic>? q]) async =>
      _decode(await _send((h) => http.get(_uri(path, q), headers: h), json: false));

  static Future<dynamic> post(String path, Map<String, dynamic> body) async =>
      _decode(await _send((h) => http.post(_uri(path), headers: h, body: jsonEncode(body))));

  static Future<dynamic> patch(String path, Map<String, dynamic> body) async =>
      _decode(await _send((h) => http.patch(_uri(path), headers: h, body: jsonEncode(body))));

  static Future<void> delete(String path) async {
    await _send((h) => http.delete(_uri(path), headers: h), json: false);
  }

  // --- typed helpers ---
  static Future<Map> me() async => await get('/api/me/') as Map;
  static Future<List> plans() async => await get('/api/plans/') as List;
  static Future<Map> createOrder(int planId) async =>
      await post('/api/subscription/create-order/', {'plan_id': planId}) as Map;
  static Future<void> activateTest(int planId) async {
    await post('/api/subscription/activate-test/', {'plan_id': planId});
  }

  static Future<List> pgs() async => await get('/api/pgs/') as List;
  static Future<Map> analytics(int? pgId) async =>
      await get('/api/analytics/', pgId != null ? {'pg': pgId} : null) as Map;
  static Future<List> monthlyIncome(int pgId) async =>
      await get('/api/income/', {'pg': pgId}) as List;
  static Future<List> floors(int pgId) async => await get('/api/floors/', {'pg': pgId}) as List;
  static Future<List> berths(int pgId, {String? status}) async =>
      await get('/api/berths/', {'pg': pgId, if (status != null) 'status': status}) as List;
  static Future<List> tenants(int pgId,
          {String? paymentStatus, String? name, bool activeOnly = false}) async =>
      await get('/api/tenants/', {
        'pg': pgId,
        if (paymentStatus != null) 'payment_status': paymentStatus,
        if (name != null && name.isNotEmpty) 'name': name,
        if (activeOnly) 'active': 'true',
      }) as List;
  static Future<List> payments({String? status}) async =>
      await get('/api/payments/', {if (status != null) 'status': status}) as List;

  // --- expenses / bills ---
  static Future<List> expenses(int pgId, {int? month, int? year}) async =>
      await get('/api/expenses/', {
        'pg': pgId,
        if (month != null) 'month': month,
        if (year != null) 'year': year,
      }) as List;
  static Future<void> addExpense(int pgId,
      {required String title, required String amount, String? category, String? spentOn}) async {
    await post('/api/expenses/', {
      'pg': pgId,
      'title': title,
      'amount': amount,
      if (category != null && category.isNotEmpty) 'category': category,
      if (spentOn != null) 'spent_on': spentOn,
    });
  }
  // Vacated tenants across all PGs (they hold no berth, so not pg-scoped).
  // [query] matches name OR phone.
  static Future<List> vacatedTenants({String? query}) async => await get('/api/tenants/', {
        'active': 'false',
        if (query != null && query.isNotEmpty) 'q': query,
      }) as List;
}
