import 'package:flutter/material.dart';

import '../models.dart';
import '../services/demo_repository.dart';

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
  AppState(this._repository)
      : practice = _repository.practice,
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
