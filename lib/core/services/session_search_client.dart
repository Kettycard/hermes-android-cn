import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/session_search_hit.dart';

/// Raised when a server-side session search cannot be completed.
///
/// Carries a human-readable reason so the session list can explain the failure
/// and offer local search instead of silently returning nothing.
class SessionSearchException implements Exception {
  final String message;

  const SessionSearchException(this.message);

  @override
  String toString() => message;
}

/// Queries the dashboard's full-text session search.
///
/// The Hermes dashboard exposes `GET /api/sessions/search`, which runs an FTS5
/// query across stored message content, applies prefix wildcards so partial
/// words match, and de-duplicates results by compression lineage. That is
/// strictly more capable than filtering the loaded list on device, which only
/// sees titles, previews, and model names.
///
/// This client owns HTTP only. Deciding *whether* to use it belongs to
/// [SessionSearchPreferences]; rendering belongs to the session list.
class SessionSearchClient {
  /// Upper bound accepted by the dashboard endpoint. Larger values are clamped
  /// server-side; clamping here keeps the request honest and the UI bounded.
  static const int maxLimit = 100;

  final http.Client _http;
  final String _baseUrl;
  final Future<Map<String, String>> Function() _authHeaders;

  SessionSearchClient({
    required String baseUrl,
    required Future<Map<String, String>> Function() headers,
    http.Client? httpClient,
  }) : // Trailing slashes would produce `//api/...` once joined below.
       _baseUrl = baseUrl.endsWith('/')
           ? baseUrl.substring(0, baseUrl.length - 1)
           : baseUrl,
       _authHeaders = headers,
       _http = httpClient ?? http.Client();

  /// Runs a full-text search and returns the matching sessions.
  ///
  /// Returns an empty list for a blank query rather than asking the server for
  /// everything. Throws [SessionSearchException] when the dashboard is
  /// unreachable, rejects the credentials, or answers with an unexpected shape
  /// — the caller surfaces that instead of showing an empty result set that
  /// would read as "no matches".
  Future<List<SessionSearchHit>> search(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final safeLimit = limit.clamp(1, maxLimit);
    final uri = Uri.parse(
      '$_baseUrl/api/sessions/search',
    ).replace(queryParameters: {'q': trimmed, 'limit': '$safeLimit'});

    final http.Response response;
    try {
      response = await _http.get(uri, headers: await _authHeaders());
    } catch (error) {
      throw SessionSearchException('无法连接到仪表盘：$error');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const SessionSearchException(
        '仪表盘拒绝了已保存的凭据。请检查此连接的仪表盘用户名和密码。',
      );
    }
    if (response.statusCode == 404) {
      throw const SessionSearchException(
        '此仪表盘不支持会话搜索。请更新主机上的 Hermes，或改回设备内搜索。',
      );
    }
    if (response.statusCode != 200) {
      throw SessionSearchException(
        '会话搜索失败，HTTP ${response.statusCode}。',
      );
    }

    return _decodeHits(response.body);
  }

  List<SessionSearchHit> _decodeHits(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw const SessionSearchException(
        '仪表盘返回了格式错误的搜索响应。',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const SessionSearchException(
        '仪表盘返回了意外的搜索响应。',
      );
    }

    final results = decoded['results'];
    if (results is! List) return const [];

    return results
        .whereType<Map<String, dynamic>>()
        .map(SessionSearchHit.fromJson)
        .toList(growable: false);
  }

  void close() => _http.close();
}
