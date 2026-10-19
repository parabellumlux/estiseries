import 'package:flutter/material.dart';

import '../models.dart';
import '../services/demo_repository.dart';
import '../services/skin_analysis_service.dart';

/// The editable plan draft the Plan screen writes into.
class PlanDraft {
  PlanDraft({
    required this.templateId,
    required this.sessions,
    required this.focus,
    required this.notes,
    required this.regimenAm,
    required this.regimenPm,
    required this.productIds,
  });

  String templateId;
  int sessions;

  /// Selected concern keys, in selection order.
  final List<String> focus;

  /// Concern key -> optional focus note.
  final Map<String, String> notes;

  String regimenAm;
  String regimenPm;
  final Set<String> productIds;
}

/// Single `ChangeNotifier` holding practice fields, the demo client, and the
/// editable plan draft. Setup and Plan screens read/write it so edits flow
/// between screens.
class AppState extends ChangeNotifier {
  AppState(
    this._repository, {
    AppConfig? config,
    SkinAnalysisService? analysisService,
  })  : config = config ?? const AppConfig(),
        analysisService = analysisService ??
            DemoSkinAnalysisService(_repository.demoClient.scans),
        practice = _repository.practice,
        client = _repository.demoClient {
    final seeded = client.plan;
    draft = PlanDraft(
      templateId: client.seriesTemplateId,
      sessions: seeded.sessions,
      focus: seeded.focus.map((f) => f.concern).toList(),
      notes: {for (final f in seeded.focus) f.concern: f.note},
      regimenAm: seeded.regimenAm,
      regimenPm: seeded.regimenPm,
      productIds: seeded.productIds.toSet(),
    );
  }

  final DemoRepository _repository;

  /// Build-time backend configuration (demo by default; live when the app
  /// is built with `--dart-define=SKINSERIES_LIVE=true`).
  final AppConfig config;

  /// The analysis service behind the shared interface — demo (seeded,
  /// local) or live (backend proxy), chosen in `main()`.
  final SkinAnalysisService analysisService;

  Practice practice;
  final ClientProfile client;
  late final PlanDraft draft;

  /// Snapshot of the plan once "Share plan to client view" is tapped.
  ClientPlan? sharedPlan;

  List<SeriesTemplate> get templates => _repository.seriesTemplates;
  List<Product> get products => _repository.products;
  Map<String, String> get concernLabels => _repository.concernLabels;

  /// Accent as a color, parsed from [Practice.accent] hex.
  Color get accentColor => _hexToColor(practice.accent);

  /// Display label for a concern key.
  String labelFor(String concernKey) => concernLabels[concernKey] ?? concernKey;

  // ---- Setup ---------------------------------------------------------------

  void updatePractice({
    String? name,
    String? practitioner,
    String? bookingUrl,
  }) {
    practice = practice.copyWith(
      name: name,
      practitioner: practitioner,
      bookingUrl: bookingUrl,
    );
    notifyListeners();
  }

  /// Recolors the app primary from one of the three swatches.
  void setAccent(String hex) {
    practice = practice.copyWith(accent: hex);
    notifyListeners();
  }

  // ---- Plan draft ----------------------------------------------------------

  /// Selecting a template sets session count + default focus.
  void selectTemplate(String templateId) {
    final template = _repository.templateById(templateId);
    draft.templateId = template.id;
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
    notifyListeners();
  }

  void setRegimen({String? am, String? pm}) {
    if (am != null) draft.regimenAm = am;
    if (pm != null) draft.regimenPm = pm;
    notifyListeners();
  }

  void toggleProduct(String productId) {
    if (!draft.productIds.remove(productId)) {
      draft.productIds.add(productId);
    }
    notifyListeners();
  }

  // ---- Scan fetch ------------------------------------------------------------

  /// The most recent result pulled through [analysisService], if any.
  ScanResult? fetchedResult;

  /// Outcome line for the last fetch (success note or the service's own
  /// error message), shown under the Brief screen's fetch button.
  String? fetchMessage;

  bool fetchInFlight = false;

  /// The scan the Brief screen should present: the seeded latest scan, with
  /// its result replaced once a fresher one has been fetched.
  SkinScan get displayLatestScan {
    final base = client.latestScan;
    final fetched = fetchedResult;
    if (fetched == null) return base;
    return SkinScan(
      id: base.id,
      label: base.label,
      date: base.date,
      stage: base.stage,
      sessionNumber: base.sessionNumber,
      result: fetched,
    );
  }

  /// Pulls the latest stage's result through the configured service.
  ///
  /// Demo service: returns the seeded result locally. Live service: asks the
  /// backend — a demo-mode backend returns the seeded result over HTTP; a
  /// live-mode backend refuses a photo-less request and its message is
  /// shown verbatim. Failures land in [fetchMessage], never in fake data.
  Future<void> fetchLatestScan() async {
    if (fetchInFlight) return;
    fetchInFlight = true;
    fetchMessage = null;
    notifyListeners();
    try {
      fetchedResult =
          await analysisService.analyze(stage: client.latestScan.stage);
      fetchMessage = config.mode == BackendMode.live
          ? 'Updated from the backend just now.'
          : 'Demo service — seeded result, no network call.';
    } on ScanException catch (e) {
      fetchMessage = e.message ?? 'Scan failed (${e.errorCode}).';
    } catch (_) {
      fetchMessage = 'Could not reach the analysis service.';
    } finally {
      fetchInFlight = false;
      notifyListeners();
    }
  }

  // ---- Share ---------------------------------------------------------------

  /// Copies the draft into [sharedPlan] for the client preview.
  void sharePlan() {
    final template = _repository.templateById(draft.templateId);
    sharedPlan = ClientPlan(
      seriesName: template.name,
      sessions: draft.sessions,
      focus: [
        for (final concern in draft.focus)
          FocusNote(concern: concern, note: draft.notes[concern] ?? ''),
      ],
      productIds: draft.productIds.toList(),
      regimenAm: draft.regimenAm,
      regimenPm: draft.regimenPm,
    );
    notifyListeners();
  }

  static Color _hexToColor(String hex) {
    final value = hex.replaceFirst('#', '');
    final buffer = StringBuffer();
    if (value.length == 6) buffer.write('ff');
    buffer.write(value);
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
