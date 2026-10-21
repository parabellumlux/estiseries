import 'dart:typed_data';

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
    this.service,
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

  /// The series' headline treatment snapshot (contract v2.1), chosen in
  /// the Plan Builder from the practitioner's active services.
  PlanService? service;
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
      await _fetchOfferings();
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
    String? email,
    String? password,
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
        email: email,
        password: password,
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

  /// Token fallback sign-in: a practitioner whose only credential is her
  /// device token (legacy accounts) can paste it on a new device. The
  /// token is validated by loading the profile with it.
  Future<bool> signInWithToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      authMessage = 'Paste your sign-in token first.';
      notifyListeners();
      return false;
    }
    busy = true;
    authMessage = null;
    notifyListeners();
    try {
      api.token = trimmed;
      final me = await api.getMe();
      await _adoptSession((token: trimmed, practitioner: me));
      return true;
    } on ApiException catch (e) {
      api.token = null;
      authMessage = e.isUnauthorized
          ? 'That token did not match an account. Check it and try again.'
          : e.message ?? 'Sign-in failed (${e.errorCode}).';
      return false;
    } catch (_) {
      api.token = null;
      authMessage = 'Could not reach the server. Try again.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ---- Account & recovery (v2.2) --------------------------------------------

  String? accountMessage;

  /// Adds (or changes) the signed-in practitioner's email + password via
  /// POST /api/me/account. The new email starts unverified; a verification
  /// email is sent by the backend.
  Future<bool> addAccount(String email, String password) async {
    try {
      profile = await api.setAccount(email: email, password: password);
      accountMessage =
          'Account saved. Check $email for a verification link — verifying enables account recovery.';
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _expireSession();
      accountMessage = e.message ?? 'Could not save your account.';
      notifyListeners();
      return false;
    }
  }

  /// Asks the backend for a fresh verification email for the profile's
  /// (unverified) address.
  Future<void> resendVerificationEmail() async {
    final email = profile?.email;
    if (email == null) return;
    try {
      await api.resendVerification(email);
      accountMessage = 'Verification email sent to $email.';
    } catch (_) {
      accountMessage = 'Could not send the verification email just now.';
    }
    notifyListeners();
  }

  /// Starts email-based recovery. The backend answers the same way
  /// whether or not the address owns an account, and so does this copy.
  Future<String> requestPasswordReset(String email) async {
    try {
      await api.forgotPassword(email.trim());
      return 'If that email has an account, a reset link is on its way. The link lasts 1 hour.';
    } on ApiException catch (e) {
      return e.message ?? 'Could not send the reset email just now.';
    } catch (_) {
      return 'Could not reach the server. Try again.';
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
    await _fetchOfferings();
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
    offerings = [];
    offeringsMessage = null;
    accountMessage = null;
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

  // ---- Offerings + logo (contract v2.1) -------------------------------------

  List<Offering> offerings = [];
  String? offeringsMessage;

  List<Offering> get activeOfferings =>
      offerings.where((o) => o.active).toList();

  List<Offering> get activeServices =>
      activeOfferings.where((o) => o.isService).toList();

  List<Offering> get activeProducts =>
      activeOfferings.where((o) => o.isProduct).toList();

  /// The products the Plan Builder offers: the practitioner's own active
  /// products when she has any, else the built-in starter catalog.
  List<Product> get planProducts => activeProducts.isNotEmpty
      ? [
          for (final o in activeProducts)
            Product(id: o.id, name: o.name, price: o.price),
        ]
      : products;

  Future<void> _fetchOfferings() async {
    try {
      offerings = await api.getOfferings();
    } on ApiException catch (e) {
      if (e.isUnauthorized) rethrow;
      offeringsMessage =
          e.message ?? 'Could not load your services and products.';
    }
  }

  Future<void> refreshOfferings() async {
    try {
      await _fetchOfferings();
    } on ApiException {
      await _expireSession();
      return;
    }
    notifyListeners();
  }

  Future<bool> createOffering(Offering offering) => _mutateOffering(
        () => api.createOffering(offering),
        'Could not add that item.',
      );

  Future<bool> updateOffering(Offering offering) => _mutateOffering(
        () => api.updateOffering(offering),
        'Could not save that item.',
      );

  Future<bool> _mutateOffering(
    Future<Offering> Function() action,
    String fallback,
  ) async {
    try {
      await action();
      await _fetchOfferings();
      offeringsMessage = null;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _expireSession();
      offeringsMessage = e.message ?? fallback;
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteOffering(String offeringId) async {
    try {
      await api.deleteOffering(offeringId);
      offerings = offerings.where((o) => o.id != offeringId).toList();
      offeringsMessage = null;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _expireSession();
      offeringsMessage = e.message ?? 'Could not delete that item.';
      notifyListeners();
      return false;
    }
  }

  Future<bool> uploadLogo(Uint8List bytes, String contentType) async {
    try {
      profile = await api.uploadLogo(bytes, contentType);
      profileMessage = 'Logo saved.';
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _expireSession();
      profileMessage = e.message ?? 'Could not save your logo.';
      notifyListeners();
      return false;
    }
  }

  Future<void> removeLogo() async {
    try {
      profile = await api.deleteLogo();
      profileMessage = 'Logo removed.';
      notifyListeners();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _expireSession();
      } else {
        profileMessage = e.message ?? 'Could not remove your logo.';
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
    offerings = [];
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

  // ---- Scan review queue (contract v2.3) ------------------------------------

  String? reviewMessage;

  /// Accepts one pending scan of the selected client into her official
  /// series (one tap from the Brief's pending section), then reloads the
  /// client so brief math, counts and the list badge all recompute.
  Future<bool> acceptPendingScan(String taskId) async {
    final id = selectedClientId;
    if (id == null) return false;
    try {
      await api.acceptScan(id, taskId);
      reviewMessage = null;
      await _fetchClients();
      await _loadSelectedDetail();
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _expireSession();
      reviewMessage = e.message ?? 'Could not accept that scan.';
      notifyListeners();
      return false;
    }
  }

  /// Discards one pending scan of the selected client — its record is
  /// deleted entirely — then reloads like [acceptPendingScan].
  Future<bool> discardPendingScan(String taskId) async {
    final id = selectedClientId;
    if (id == null) return false;
    try {
      await api.discardScan(id, taskId);
      reviewMessage = null;
      await _fetchClients();
      await _loadSelectedDetail();
      return true;
    } on ApiException catch (e) {
      if (e.isUnauthorized) await _expireSession();
      reviewMessage = e.message ?? 'Could not discard that scan.';
      notifyListeners();
      return false;
    }
  }

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
        for (final choice in [...planProducts, ...kProducts]) {
          if (choice.name == product.name) {
            productIds.add(choice.id);
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
        service: plan.service,
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

  void setDraftService(PlanService? service) {
    draft.service = service;
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
          for (final product in planProducts)
            if (draft.productIds.contains(product.id))
              {'name': product.name, 'price': product.price},
        ],
        if (draft.service != null) 'service': draft.service!.toJson(),
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
