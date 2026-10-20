/// Data models for the EstiSeries practitioner app.
///
/// `fromJson` factories match API contract v2 (`docs/api-contract-v2.md`).
library;

/// The signed-in practitioner and their practice (GET /api/me shape).
class PractitionerProfile {
  const PractitionerProfile({
    required this.id,
    required this.practiceName,
    required this.practitionerName,
    required this.accent,
    required this.bookingLink,
    this.logoUrl,
    this.createdAt = '',
    this.clientCount,
  });

  factory PractitionerProfile.fromJson(Map<String, dynamic> json) =>
      PractitionerProfile(
        id: json['id'] as String? ?? '',
        practiceName: json['practiceName'] as String? ?? '',
        practitionerName: json['practitionerName'] as String? ?? '',
        accent: json['accent'] as String? ?? '#B0714F',
        bookingLink: json['bookingLink'] as String? ?? '',
        logoUrl: json['logoUrl'] as String?,
        createdAt: json['createdAt'] as String? ?? '',
        clientCount: (json['clientCount'] as num?)?.toInt(),
      );

  final String id;
  final String practiceName;
  final String practitionerName;

  /// Hex color string, e.g. `#B0714F`.
  final String accent;
  final String bookingLink;

  /// Path of the practice logo on the backend
  /// (`/api/practitioners/<id>/logo`), or null when none is uploaded.
  final String? logoUrl;
  final String createdAt;
  final int? clientCount;

  PractitionerProfile copyWith({
    String? practiceName,
    String? practitionerName,
    String? accent,
    String? bookingLink,
    String? logoUrl,
  }) =>
      PractitionerProfile(
        id: id,
        practiceName: practiceName ?? this.practiceName,
        practitionerName: practitionerName ?? this.practitionerName,
        accent: accent ?? this.accent,
        bookingLink: bookingLink ?? this.bookingLink,
        logoUrl: logoUrl ?? this.logoUrl,
        createdAt: createdAt,
        clientCount: clientCount,
      );
}

/// A product embedded in a saved plan: `{name, price}` per contract v2.
class PlanProduct {
  const PlanProduct({required this.name, required this.price});

  factory PlanProduct.fromJson(Map<String, dynamic> json) => PlanProduct(
        name: json['name'] as String? ?? '',
        price: (json['price'] as num? ?? 0).toDouble(),
      );

  final String name;
  final double price;

  Map<String, dynamic> toJson() => {'name': name, 'price': price};
}

/// A focus concern plus its optional per-concern note.
class FocusNote {
  const FocusNote({required this.concern, required this.note});

  factory FocusNote.fromJson(Map<String, dynamic> json) => FocusNote(
        concern: json['concern'] as String? ?? '',
        note: json['note'] as String? ?? '',
      );

  final String concern;
  final String note;

  Map<String, dynamic> toJson() => {'concern': concern, 'note': note};
}

/// The series' headline treatment embedded in a saved plan:
/// `{name, price, unit?}` (contract v2.1) — a snapshot of one of the
/// practitioner's services, copied when the plan is saved.
class PlanService {
  const PlanService({required this.name, required this.price, this.unit});

  factory PlanService.fromJson(Map<String, dynamic> json) => PlanService(
        name: json['name'] as String? ?? '',
        price: (json['price'] as num? ?? 0).toDouble(),
        unit: json['unit'] as String?,
      );

  static PlanService? tryParse(Object? value) {
    if (value is Map<String, dynamic>) return PlanService.fromJson(value);
    if (value is Map) {
      return PlanService.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  final String name;
  final double price;

  /// Free-text price unit, e.g. `per session`.
  final String? unit;

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
        if (unit != null) 'unit': unit,
      };
}

/// The plan shared to a client's series timeline (contract v2 shape).
class ClientPlan {
  const ClientPlan({
    required this.seriesName,
    required this.sessions,
    required this.focus,
    required this.regimenAm,
    required this.regimenPm,
    required this.products,
    this.legacyProductIds = const [],
    this.service,
  });

  factory ClientPlan.fromJson(Map<String, dynamic> json) {
    final regimen = json['regimen'] as Map<String, dynamic>? ?? const {};
    return ClientPlan(
      seriesName: json['seriesName'] as String? ?? '',
      sessions: (json['sessions'] as num?)?.toInt() ?? 1,
      focus: (json['focus'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FocusNote.fromJson)
          .toList(),
      regimenAm: regimen['am'] as String? ?? '',
      regimenPm: regimen['pm'] as String? ?? '',
      products: (json['products'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PlanProduct.fromJson)
          .toList(),
      legacyProductIds: (json['productIds'] as List<dynamic>? ?? const [])
          .map((dynamic e) => e as String)
          .toList(),
      service: PlanService.tryParse(json['service']),
    );
  }

  static ClientPlan? tryParse(Object? value) {
    if (value is Map<String, dynamic>) return ClientPlan.fromJson(value);
    if (value is Map) {
      return ClientPlan.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  final String seriesName;
  final int sessions;
  final List<FocusNote> focus;
  final String regimenAm;
  final String regimenPm;
  final List<PlanProduct> products;

  /// Product ids from pre-v2 plans, kept only so old plans still load.
  final List<String> legacyProductIds;

  /// The series' headline treatment, when the practitioner picked one.
  final PlanService? service;

  Map<String, dynamic> toJson() => {
        'seriesName': seriesName,
        'sessions': sessions,
        'focus': focus.map((f) => f.toJson()).toList(),
        'regimen': {'am': regimenAm, 'pm': regimenPm},
        'products': products.map((p) => p.toJson()).toList(),
        if (service != null) 'service': service!.toJson(),
      };
}

/// The scored result of one skin analysis scan.
class ScanResult {
  const ScanResult({
    required this.overall,
    required this.skinAge,
    required this.skinType,
    required this.scores,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) => ScanResult(
        overall: (json['overall'] as num? ?? 0).toInt(),
        skinAge: (json['skinAge'] as num? ?? 0).toInt(),
        skinType: json['skinType'] as String? ?? '',
        scores: (json['scores'] as Map<String, dynamic>? ?? const {}).map(
          (String key, dynamic value) =>
              MapEntry<String, int>(key, (value as num).toInt()),
        ),
      );

  final int overall;
  final int skinAge;
  final String skinType;

  /// 15 scored concerns, higher = healthier (0–100).
  final Map<String, int> scores;
}

/// One scan record on a client's series: `{taskId, label, timestamp, result}`.
class SkinScan {
  const SkinScan({
    required this.taskId,
    required this.label,
    required this.timestamp,
    required this.result,
  });

  factory SkinScan.fromJson(Map<String, dynamic> json) {
    final nested = json['result'];
    return SkinScan(
      taskId: json['taskId'] as String? ?? json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? json['date'] as String? ?? '',
      result: nested is Map<String, dynamic>
          ? ScanResult.fromJson(nested)
          : ScanResult.fromJson(json),
    );
  }

  final String taskId;
  final String label;
  final String timestamp;
  final ScanResult result;

  /// [timestamp] parsed for display; unparseable values fall back to epoch.
  DateTime get dateTime => DateTime.tryParse(timestamp) ?? DateTime(1970);
}

/// One row of GET /api/me/clients.
class ClientSummary {
  const ClientSummary({
    required this.id,
    required this.firstName,
    required this.createdAt,
    required this.token,
    required this.link,
    required this.scanCount,
    required this.latestOverall,
    required this.latestScanAt,
    required this.plan,
  });

  factory ClientSummary.fromJson(Map<String, dynamic> json) => ClientSummary(
        id: json['id'] as String? ?? '',
        firstName: json['firstName'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
        token: json['token'] as String? ?? '',
        link: json['link'] as String? ?? '',
        scanCount: (json['scanCount'] as num?)?.toInt() ?? 0,
        latestOverall: (json['latestOverall'] as num?)?.toInt(),
        latestScanAt: json['latestScanAt'] as String?,
        plan: ClientPlan.tryParse(json['plan']),
      );

  final String id;
  final String firstName;
  final String createdAt;
  final String token;
  final String link;
  final int scanCount;
  final int? latestOverall;
  final String? latestScanAt;
  final ClientPlan? plan;
}

/// Full client record: GET /api/me/clients/:id (plan + scan history).
class ClientDetail {
  const ClientDetail({
    required this.id,
    required this.firstName,
    required this.createdAt,
    required this.token,
    required this.link,
    required this.plan,
    required this.scans,
  });

  factory ClientDetail.fromJson(Map<String, dynamic> json) => ClientDetail(
        id: json['id'] as String? ?? '',
        firstName: json['firstName'] as String? ?? '',
        createdAt: json['createdAt'] as String? ?? '',
        token: json['token'] as String? ?? '',
        link: json['link'] as String? ?? '',
        plan: ClientPlan.tryParse(json['plan']),
        scans: (json['scans'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(SkinScan.fromJson)
            .toList(),
      );

  final String id;
  final String firstName;
  final String createdAt;
  final String token;
  final String link;
  final ClientPlan? plan;
  final List<SkinScan> scans;

  SkinScan? get baselineScan => scans.isEmpty ? null : scans.first;
  SkinScan? get latestScan => scans.isEmpty ? null : scans.last;
}

/// One of the practitioner's own services or retail products
/// (contract v2.1): configured in Setup with her prices, and shown to
/// clients on their series page.
class Offering {
  const Offering({
    required this.id,
    required this.kind,
    required this.name,
    required this.price,
    this.unit,
    this.durationMin,
    this.description,
    required this.active,
    required this.createdAt,
  });

  factory Offering.fromJson(Map<String, dynamic> json) => Offering(
        id: json['id'] as String? ?? '',
        kind: json['kind'] as String? ?? 'service',
        name: json['name'] as String? ?? '',
        price: (json['price'] as num? ?? 0).toDouble(),
        unit: json['unit'] as String?,
        durationMin: (json['durationMin'] as num?)?.toInt(),
        description: json['description'] as String?,
        active: json['active'] as bool? ?? true,
        createdAt: json['createdAt'] as String? ?? '',
      );

  final String id;

  /// `service` or `product`.
  final String kind;
  final String name;
  final double price;

  /// Free-text price unit, e.g. `per unit`, `per session`.
  final String? unit;
  final int? durationMin;
  final String? description;
  final bool active;
  final String createdAt;

  bool get isService => kind == 'service';
  bool get isProduct => kind == 'product';

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'name': name,
        'price': price,
        if (unit != null) 'unit': unit,
        if (durationMin != null) 'durationMin': durationMin,
        if (description != null) 'description': description,
        'active': active,
        'createdAt': createdAt,
      };

  Offering copyWith({
    String? kind,
    String? name,
    double? price,
    String? unit,
    int? durationMin,
    String? description,
    bool? active,
  }) =>
      Offering(
        id: id,
        kind: kind ?? this.kind,
        name: name ?? this.name,
        price: price ?? this.price,
        unit: unit ?? this.unit,
        durationMin: durationMin ?? this.durationMin,
        description: description ?? this.description,
        active: active ?? this.active,
        createdAt: createdAt,
      );
}

/// A retail product in the built-in catalog (Plan Builder multi-select).
class Product {
  const Product({required this.id, required this.name, required this.price});

  final String id;
  final String name;
  final double price;
}

/// A named series template the practitioner can start a plan from.
class SeriesTemplate {
  const SeriesTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.sessions,
    required this.defaultFocus,
  });

  final String id;
  final String name;
  final String description;
  final int sessions;
  final List<String> defaultFocus;
}
