import 'package:skinseries/models.dart';
import 'package:skinseries/services/api_client.dart';

/// In-memory [EstiSeriesApi] for widget tests — no network, no plugins.
class FakeApi implements EstiSeriesApi {
  FakeApi({
    PractitionerProfile? signedInProfile,
    List<ClientSummary>? clients,
    Map<String, ClientDetail>? details,
  })  : _profile = signedInProfile ??
            const PractitionerProfile(
              id: 'prac-1',
              practiceName: 'Test Glow Studio',
              practitionerName: 'Test Practitioner',
              accent: '#B0714F',
              bookingLink: 'https://example.com/book',
              createdAt: '2026-10-01T00:00:00.000Z',
              clientCount: 1,
            ),
        _clients = clients ?? const [],
        _details = details ?? {};

  final PractitionerProfile _profile;
  List<ClientSummary> _clients;
  final Map<String, ClientDetail> _details;

  Map<String, dynamic>? lastSavedPlan;
  String? lastSavedPlanClientId;
  String? lastLogin;
  String? createdFirstName;

  @override
  String? token;

  @override
  Future<AuthResult> createPractitioner({
    required String practiceName,
    required String practitionerName,
    String? accent,
    String? bookingLink,
  }) async {
    token = 'token-created';
    return (
      token: 'token-created',
      practitioner: PractitionerProfile(
        id: 'prac-new',
        practiceName: practiceName,
        practitionerName: practitionerName,
        accent: accent ?? '#B0714F',
        bookingLink: bookingLink ?? '',
      ),
    );
  }

  @override
  Future<AuthResult> login(String login, String password) async {
    if (login == 'demo@estiseries.app' && password == 'GlowDemo2026') {
      lastLogin = login;
      token = 'token-demo';
      return (token: 'token-demo', practitioner: _profile);
    }
    throw const ApiException(401, 'error_unauthorized');
  }

  @override
  Future<PractitionerProfile> getMe() async {
    if (token == null) {
      throw const ApiException(401, 'error_unauthorized');
    }
    return _profile;
  }

  @override
  Future<PractitionerProfile> updateMe({
    String? practiceName,
    String? practitionerName,
    String? accent,
    String? bookingLink,
  }) async =>
      _profile.copyWith(
        practiceName: practiceName,
        practitionerName: practitionerName,
        accent: accent,
        bookingLink: bookingLink,
      );

  @override
  Future<List<ClientSummary>> listClients() async => _clients;

  @override
  Future<ClientDetail> createClient(String firstName) async {
    createdFirstName = firstName;
    final detail = ClientDetail(
      id: 'client-$firstName',
      firstName: firstName,
      createdAt: '2026-10-19T00:00:00.000Z',
      token: 'tok-$firstName',
      link: '/?c=tok-$firstName',
      plan: null,
      scans: const [],
    );
    _details[detail.id] = detail;
    _clients = [
      ..._clients,
      ClientSummary(
        id: detail.id,
        firstName: firstName,
        createdAt: detail.createdAt,
        token: detail.token,
        link: detail.link,
        scanCount: 0,
        latestOverall: null,
        latestScanAt: null,
        plan: null,
      ),
    ];
    return detail;
  }

  @override
  Future<ClientDetail> getClient(String clientId) async {
    final detail = _details[clientId];
    if (detail == null) {
      throw const ApiException(404, 'error_client_not_found');
    }
    return detail;
  }

  @override
  Future<void> updatePlan(String clientId, Map<String, dynamic> plan) async {
    lastSavedPlanClientId = clientId;
    lastSavedPlan = plan;
  }

  @override
  Future<void> deleteClient(String clientId) async {
    _details.remove(clientId);
    _clients = _clients.where((c) => c.id != clientId).toList();
  }
}

/// A scan record in contract-v2 shape, for tests.
SkinScan fakeScan(
  String label,
  String timestamp,
  int overall,
  Map<String, int> scores,
) =>
    SkinScan.fromJson(<String, dynamic>{
      'taskId': 'task-$label',
      'label': label,
      'timestamp': timestamp,
      'result': <String, dynamic>{
        'overall': overall,
        'skinAge': 44,
        'skinType': 'Combination',
        'scores': scores,
      },
    });
