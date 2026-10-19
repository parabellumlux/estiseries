import 'package:flutter/material.dart';

import '../data/catalog.dart';
import '../models.dart';
import '../services/api_client.dart';

/// The editable plan draft the Plan screen writes into.
class PlanDraft {
  PlanDraft({
    required this.templateId,
    required this.seriesName,
    required this.sessions,
    required this.focus,
    required this.notes,
    required this.regimenAm,
    required this.regimenPm,
    required this.productIds,
  });

  String templateId;
  String seriesName;
  int sessions;

  /// Selected concern keys, in selection order.
  final List<String> focus;

  /// Concern key -> optional focus note.
  final Map<String, String> notes;

  String regimenAm;
  String regimenPm;
  final Set<String> productIds;
}

/// Single `ChangeNotifier` holding the signed-in practitioner, their
/// clients, the selected client, and the editable plan draft. All client
/// data comes from the live backend via [EstiSeriesApi]; the practitioner
/// token persists on device via [TokenStore].
class AppState extends ChangeNotifier {
  AppState({
    required this.api,
    required this.tokenStore,
    this.config = const AppConfig(),
  }) : draft = _defaultDraft();

  final EstiSeriesApi api;
  final TokenStore tokenStore;
  final AppConfig config;

  // ---- Built-in catalog ------------------------------------------------------

  List<SeriesTemplate> get templates => kSeriesTemplates;
  List<Product> get products => kProducts;
  Map<String, String> get concernLabels => kConcernLabels;
  String labelFor(String concernKey) => concernLabels[concernKey] ?? concernKey;

  // ---- Auth / profile --------------------------------------------------------

  bool bootstrapped = false;
  bool busy = false;
  PractitionerProfile? profile;
  String? authMessage;
  String? profileMessage;

  bool get isAuthenticated => profile != null;

  Color get accentColor => _hexToColor(profile?.accent ?? '#B0714F');

  /// Restores the persisted token (if any) and loads profile + clients.
  /// A 401 means the saved token is stale: it is cleared and the app
  /// returns to the create / sign-in state with a plain message.
  Future<void> bootstrap() async {
    try {
      final stored = await tokenStore.read();
      if (stored == null || stored.isEmpty) return;
      api.token = stored;
      profile = await api.getMe();
      await _fetchClients();
      if (selectedClientId == null && clients.isNotEmpty) {
        await selectClient(clients.first.id);
      }
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await tokenStore.clear();
        api.token = null;
        profile = null;
        authMessage =
            'Your saved sign-in has expired. Create your practice or sign in again.';
      } else {
        authMessage =
            'Could not reach the server to restore your sign-in. Check your connection and reopen the app.';
      }
    } catch (_) {
      authMessage =
          'Could not restore your sign-in. Check your connection and reopen the app.';
    } finally {
      bootstrapped = true;
      notifyListeners();
    }
  }

  Future<bool> createPractice({
    required String practiceName,
    required String practitionerName,
    required String bookingLink,
    required String accent,
  }) async {
    busy = true;
    authMessage = null;
    notifyListeners();
    try {
      final result = await api.createPractitioner(
        practiceName: practiceName,
        practitionerName: practitionerName,
        accent: accent,
        bookingLink: bookingLink,
      );
      await _adoptSession(result);
      return true;
    } on ApiException catch (e) {
      authMessage =
          e.message ?? 'Could not create your practice (${e.errorCode}).';
      return false;
    } catch (_) {
      authMessage = 'Could not reach the server. Try again.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<bool> signIn(String login, String password) async {
    busy = true;
    authMessage = null;
    notifyListeners();
    try {
      final result = await api.login(login, password);
      await _adoptSession(result);
      return true;
    } on ApiException catch (e) {
      authMessage = e.isUnauthorized
          ? 'That login and password did not match. Check them and try again.'
          : e.message ?? 'Sign-in failed (${e.errorCode}).';
      return false;
    } catch (_) {
      authMessage = 'Could not reach the server. Try again.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> _adoptSession(AuthResult result) async {
    api.token = result.token;
    await tokenStore.write(result.token);
    profile = result.practitioner;
    clients = [];
    selectedClientId = null;
    selectedDetail = null;
    sharedPlan = null;
    await _fetchClients();
    if (clients.isNotEmpty) {
      await selectClient(clients.first.id);
    }
  }

  Future<void> signOut() async {
    await tokenStore.clear();
    api.token = null;
    profile = null;
    clients = [];
    selectedClientId = null;
    selectedDetail = null;
    sharedPlan = null;
    clientDetailOpen = false;
    authMessage = null;
    profileMessage = null;
    draft = _defaultDraft();
    draftVersion++;
    tabIndex = 0;
    notifyListeners();
  }

  Future<bool> saveProfile({
    required String practiceName,
    required String practitionerName,
    required String bookingLink,
  }) async {
    try {
      profile = await api.updateMe(
        practiceName: practiceName,
        practitionerName: practitionerName,
        bookingLink: bookingLink,
      );
      profileMessage = 'Profile saved.';
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _expireSession();
      profileMessage = e.message ?? 'Could not save your profile.';
      notifyListeners();
      return false;
    }
  }

  /// Recolors the app primary from one of the three swatches and saves it.
  Future<void> setAccent(String hex) async {
    final current = profile;
    if (current == null) return;
    profile = current.copyWith(accent: hex);
    notifyListeners();
    try {
      profile = await api.updateMe(accent: hex);
      notifyListeners();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _expireSession();
      } else {
        profileMessage = 'Accent could not be saved.';
        notifyListeners();
      }
    }
  }

  Future<void> _expireSession() async {
    await tokenStore.clear();
    api.token = null;
    profile = null;
    clients = [];
    selectedClientId = null;
    selectedDetail = null;
    authMessage =
        'Your saved sign-in has expired. Create your practice or sign in again.';
    notifyListeners();
  }

  // ---- Navigation --------------------------------------------------------------

  /// Bottom-nav index: 0 Setup, 1 Clients, 2 Brief, 3 Plan.
  int tabIndex = 0;

  void goToTab(int index) {
    tabIndex = index;
    notifyListeners();
  }

  // ---- Clients -----------------------------------------------------------------

  List<ClientSummary> clients = [];
  String? selectedClientId;
  ClientDetail? selectedDetail;
  bool detailLoading = false;
  bool clientDetailOpen = false;
  String? clientsMessage;

  ClientSummary? get selectedSummary {
    for (final client in clients) {
      if (client.id == selectedClientId) return client;
    }
    return null;
  }

  String clientLinkFor({required String link, required String token}) =>
      config.clientUrl(link: link, token: token);

  Future<void> refreshClients() async {
    try {
      await _fetchClients();
      if (selectedClientId != null &&
          clients.every((c) => c.id != selectedClientId)) {
        selectedClientId = null;
        selectedDetail = null;
        if (clients.isNotEmpty) await selectClient(clients.first.id);
      }
      notifyListeners();
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _expireSession();
    }
  }

  Future<void> _fetchClients() async {
    clients = await api.listClients();
  }

  Future<void> selectClient(String clientId, {bool openDetail = false}) async {
    selectedClientId = clientId;
    if (openDetail) clientDetailOpen = true;
    notifyListeners();
    await _loadSelectedDetail();
  }

  void openSelectedClientDetail() {
    if (selectedClientId == null) return;
    clientDetailOpen = true;
    tabIndex = 1;
    notifyListeners();
  }

  void closeClientDetail() {
    clientDetailOpen = false;
    notifyListeners();
  }

  Future<void> refreshSelectedClient() async => _loadSelectedDetail();

  Future<void> _loadSelectedDetail() async {
    final id = selectedClientId;
    if (id == null) return;
    detailLoading = true;
    notifyListeners();
    try {
      selectedDetail = await api.getClient(id);
      _loadDraftFromPlan(selectedDetail!.plan);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _expireSession();
        return;
      }
      clientsMessage = e.message ?? 'Could not load that client.';
    } finally {
      detailLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addClient(String firstName) async {
    try {
      final detail = await api.createClient(firstName.trim());
      await _fetchClients();
      await selectClient(detail.id);
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _expireSession();
      clientsMessage = e.message ?? 'Could not add that client.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteClient(String clientId) async {
    try {
      await api.deleteClient(clientId);
      final wasSelected = clientId == selectedClientId;
      clients = clients.where((c) => c.id != clientId).toList();
      clientDetailOpen = false;
      if (wasSelected) {
        selectedClientId = null;
        selectedDetail = null;
        sharedPlan = null;
        if (clients.isNotEmpty) {
          await selectClient(clients.first.id);
        } else {
          draft = _defaultDraft();
          draftVersion++;
        }
      }
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _expireSession();
      clientsMessage = e.message ?? 'Could not delete that client.';
      notifyListeners();
      return false;
    }
  }

  // ---- Plan draft ---------------------------------------------------------------

  PlanDraft draft;

  /// Bumped whenever the draft is reloaded from a client's saved plan, so
  /// the Plan screen can resync its text controllers.
  int draftVersion = 0;

  /// Snapshot of the plan once it has been saved to the backend.
  ClientPlan? sharedPlan;
  String? planMessage;

  static PlanDraft _defaultDraft() {
    final template = kSeriesTemplates.first;
    return PlanDraft(
      templateId: template.id,
      seriesName: template.name,
      sessions: template.sessions,
      focus: [...template.defaultFocus],
      notes: {},
      regimenAm: '',
      regimenPm: '',
      productIds: {},
    );
  }

  void _loadDraftFromPlan(ClientPlan? plan) {
    if (plan == null) {
      draft = _defaultDraft();
    } else {
      final template = templateByName(plan.seriesName) ?? kSeriesTemplates.last;
      final productIds = <String>{...plan.legacyProductIds};
      for (final product in plan.products) {
        for (final catalogProduct in kProducts) {
          if (catalogProduct.name == product.name) {
            productIds.add(catalogProduct.id);
          }
        }
      }
      draft = PlanDraft(
        templateId: template.id,
        seriesName: plan.seriesName.isEmpty ? template.name : plan.seriesName,
        sessions: plan.sessions.clamp(1, 12),
        focus: plan.focus.map((f) => f.concern).toList(),
        notes: {for (final f in plan.focus) f.concern: f.note},
        regimenAm: plan.regimenAm,
        regimenPm: plan.regimenPm,
        productIds: productIds,
      );
    }
    sharedPlan = null;
    planMessage = null;
    draftVersion++;
  }

  void selectTemplate(String templateId) {
    final template = templateById(templateId);
    draft.templateId = template.id;
    draft.seriesName = template.name;
    draft.sessions = template.sessions.clamp(1, 12);
    draft.focus
      ..clear()
      ..addAll(template.defaultFocus);
    notifyListeners();
  }

  void setSessions(int sessions) {
    draft.sessions = sessions.clamp(1, 12);
    notifyListeners();
  }

  void toggleFocus(String concern) {
    if (draft.focus.contains(concern)) {
      draft.focus.remove(concern);
    } else {
      draft.focus.add(concern);
    }
    notifyListeners();
  }

  void setFocusNote(String concern, String note) {
    draft.notes[concern] = note;
  }

  void setRegimen({String? am, String? pm}) {
    if (am != null) draft.regimenAm = am;
    if (pm != null) draft.regimenPm = pm;
  }

  void toggleProduct(String productId) {
    if (!draft.productIds.remove(productId)) {
      draft.productIds.add(productId);
    }
    notifyListeners();
  }

  Map<String, dynamic> buildPlanJson() => {
        'seriesName': draft.seriesName,
        'sessions': draft.sessions,
        'focus': [
          for (final concern in draft.focus)
            {'concern': concern, 'note': draft.notes[concern] ?? ''},
        ],
        'regimen': {'am': draft.regimenAm, 'pm': draft.regimenPm},
        'products': [
          for (final product in kProducts)
            if (draft.productIds.contains(product.id))
              {'name': product.name, 'price': product.price},
        ],
      };

  /// Saves the draft to the selected client via
  /// PUT /api/me/clients/:id/plan.
  Future<bool> savePlan() async {
    final id = selectedClientId;
    if (id == null) {
      planMessage = 'Choose a client first.';
      notifyListeners();
      return false;
    }
    try {
      final planJson = buildPlanJson();
      await api.updatePlan(id, planJson);
      sharedPlan = ClientPlan.fromJson(planJson);
      planMessage = 'Plan saved.';
      await _fetchClients();
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _expireSession();
      planMessage = e.message ?? 'Could not save the plan.';
      notifyListeners();
      return false;
    }
  }

  static Color _hexToColor(String hex) {
    final value = hex.replaceFirst('#', '');
    final buffer = StringBuffer();
    if (value.length == 6) buffer.write('ff');
    buffer.write(value);
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
