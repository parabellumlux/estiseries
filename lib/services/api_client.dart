import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';

/// App-level configuration for the EstiSeries backend (contract v2).
class AppConfig {
  const AppConfig({this.backendBaseUrl = defaultBackendBaseUrl});

  static const String defaultBackendBaseUrl =
      'https://estiseries.ignisalgos.com';

  /// Backend URL override from `--dart-define=SKINSERIES_BACKEND_URL=...`.
  static const String _envBackendBaseUrl =
      String.fromEnvironment('SKINSERIES_BACKEND_URL');

  factory AppConfig.fromEnvironment() => AppConfig(
        backendBaseUrl: _envBackendBaseUrl.isEmpty
            ? defaultBackendBaseUrl
            : _envBackendBaseUrl,
      );

  final String backendBaseUrl;

  /// [backendBaseUrl] without a trailing slash, for joining paths.
  String get base => backendBaseUrl.replaceAll(RegExp(r'/+$'), '');

  /// The absolute URL for a client link path (`/?c=<token>`) or raw token.
  String clientUrl({required String link, required String token}) {
    if (link.startsWith('http')) return link;
    if (link.isNotEmpty) return '$base$link';
    return '$base/?c=$token';
  }
}

/// A backend failure, carrying its HTTP status and contract error code.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.errorCode, [this.message]);

  final int statusCode;
  final String errorCode;
  final String? message;

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() =>
      'ApiException($statusCode $errorCode${message == null ? '' : ': $message'})';
}

/// Result of creating a practice or signing in: token + profile.
typedef AuthResult = ({String token, PractitionerProfile practitioner});

/// The practitioner API of contract v2. The real implementation is
/// [HttpApiClient]; tests substitute a fake — no network in tests.
abstract class EstiSeriesApi {
  String? token;

  Future<AuthResult> createPractitioner({
    required String practiceName,
    required String practitionerName,
    String? accent,
    String? bookingLink,
  });

  Future<AuthResult> login(String login, String password);

  Future<PractitionerProfile> getMe();

  Future<PractitionerProfile> updateMe({
    String? practiceName,
    String? practitionerName,
    String? accent,
    String? bookingLink,
  });

  Future<List<ClientSummary>> listClients();

  Future<ClientDetail> createClient(String firstName);

  Future<ClientDetail> getClient(String clientId);

  Future<void> updatePlan(String clientId, Map<String, dynamic> plan);

  Future<void> deleteClient(String clientId);
}

/// Contract-v2 API client over `dart:io` [HttpClient] (no HTTP package).
class HttpApiClient implements EstiSeriesApi {
  HttpApiClient({AppConfig config = const AppConfig()}) : _config = config;

  final AppConfig _config;

  @override
  String? token;

  @override
  Future<AuthResult> createPractitioner({
    required String practiceName,
    required String practitionerName,
    String? accent,
    String? bookingLink,
  }) async {
    final decoded = await _request(
      'POST',
      '/api/practitioners',
      auth: false,
      body: {
        'practiceName': practiceName,
        'practitionerName': practitionerName,
        if (accent != null) 'accent': accent,
        if (bookingLink != null) 'bookingLink': bookingLink,
      },
    );
    final map = _asMap(decoded);
    return (
      token: map['token'] as String? ?? '',
      practitioner: PractitionerProfile.fromJson(map),
    );
  }

  @override
  Future<AuthResult> login(String login, String password) async {
    final decoded = await _request(
      'POST',
      '/api/login',
      auth: false,
      body: {'login': login, 'password': password},
    );
    final map = _asMap(decoded);
    final profile = map['practitioner'];
    return (
      token: map['token'] as String? ?? '',
      practitioner: PractitionerProfile.fromJson(
        profile is Map<String, dynamic>
            ? profile
            : Map<String, dynamic>.from(profile as Map),
      ),
    );
  }

  @override
  Future<PractitionerProfile> getMe() async =>
      PractitionerProfile.fromJson(_asMap(await _request('GET', '/api/me')));

  @override
  Future<PractitionerProfile> updateMe({
    String? practiceName,
    String? practitionerName,
    String? accent,
    String? bookingLink,
  }) async =>
      PractitionerProfile.fromJson(_asMap(await _request(
        'PUT',
        '/api/me',
        body: {
          if (practiceName != null) 'practiceName': practiceName,
          if (practitionerName != null) 'practitionerName': practitionerName,
          if (accent != null) 'accent': accent,
          if (bookingLink != null) 'bookingLink': bookingLink,
        },
      )));

  @override
  Future<List<ClientSummary>> listClients() async {
    final decoded = await _request('GET', '/api/me/clients');
    return (decoded as List<dynamic>)
        .map((dynamic e) =>
            ClientSummary.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<ClientDetail> createClient(String firstName) async =>
      ClientDetail.fromJson(_asMap(await _request(
        'POST',
        '/api/me/clients',
        body: {'firstName': firstName},
      )));

  @override
  Future<ClientDetail> getClient(String clientId) async =>
      ClientDetail.fromJson(
          _asMap(await _request('GET', '/api/me/clients/$clientId')));

  @override
  Future<void> updatePlan(String clientId, Map<String, dynamic> plan) async {
    await _request(
      'PUT',
      '/api/me/clients/$clientId/plan',
      body: {'plan': plan},
    );
  }

  @override
  Future<void> deleteClient(String clientId) async {
    await _request('DELETE', '/api/me/clients/$clientId');
  }

  Future<dynamic> _request(
    String method,
    String path, {
    bool auth = true,
    Map<String, dynamic>? body,
  }) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('${_config.base}$path');
      final request = await client.openUrl(method, uri);
      request.headers.contentType = ContentType.json;
      if (auth && token != null && token!.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer $token');
      }
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      final dynamic decoded = text.isEmpty ? null : jsonDecode(text);
      if (response.statusCode >= 400) {
        final map = decoded is Map ? decoded : const {};
        throw ApiException(
          response.statusCode,
          map['errorCode'] as String? ?? 'error_server',
          map['message'] as String?,
        );
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on SocketException {
      throw const ApiException(
          0, 'error_network', 'Could not reach the server.');
    } on HttpException {
      throw const ApiException(
          0, 'error_network', 'Could not reach the server.');
    } on FormatException {
      throw const ApiException(
          0, 'error_server', 'Unexpected server response.');
    } finally {
      client.close(force: true);
    }
  }

  Map<String, dynamic> _asMap(dynamic decoded) =>
      decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
}

/// Where the practitioner token persists on device.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// In-memory store, for tests.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._token]);

  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

/// shared_preferences-backed store: the token survives app restarts and
/// is the practitioner's only credential (contract v2 auth model).
class SharedPreferencesTokenStore implements TokenStore {
  const SharedPreferencesTokenStore();

  static const String key = 'estiseries_practitioner_token';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String token) async =>
      (await SharedPreferences.getInstance()).setString(key, token);

  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(key);
}
