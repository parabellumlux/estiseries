/// Data models for the practitioner app.
///
/// `fromJson` factories match `assets/demo/demo_data.json` exactly.
library;

/// The practice using the app (name, practitioner, links, accent color).
class Practice {
  const Practice({
    required this.id,
    required this.name,
    required this.practitioner,
    required this.bookingUrl,
    required this.scanUrl,
    required this.tagline,
    required this.accent,
  });

  factory Practice.fromJson(Map<String, dynamic> json) => Practice(
        id: json['id'] as String,
        name: json['name'] as String,
        practitioner: json['practitioner'] as String,
        bookingUrl: json['bookingUrl'] as String,
        scanUrl: json['scanUrl'] as String,
        tagline: json['tagline'] as String? ?? '',
        accent: json['accent'] as String? ?? '#B0714F',
      );

  final String id;
  final String name;
  final String practitioner;
  final String bookingUrl;
  final String scanUrl;
  final String tagline;

  /// Hex color string, e.g. `#B0714F`.
  final String accent;

  Practice copyWith({
    String? name,
    String? practitioner,
    String? bookingUrl,
    String? accent,
  }) =>
      Practice(
        id: id,
        name: name ?? this.name,
        practitioner: practitioner ?? this.practitioner,
        bookingUrl: bookingUrl ?? this.bookingUrl,
        scanUrl: scanUrl,
        tagline: tagline,
        accent: accent ?? this.accent,
      );
}

/// A retail product that can be attached to a plan.
class Product {
  const Product({
    required this.id,
    required this.name,
    required this.price,
  });

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: json['id'] as String,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
      );

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

  factory SeriesTemplate.fromJson(Map<String, dynamic> json) => SeriesTemplate(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String? ?? '',
        sessions: json['sessions'] as int? ?? 1,
        defaultFocus: (json['defaultFocus'] as List<dynamic>? ?? const [])
            .map((dynamic e) => e as String)
            .toList(),
      );

  final String id;
  final String name;
  final String description;
  final int sessions;
  final List<String> defaultFocus;
}

/// The scored result of one skin analysis scan (SPEC data contract).
class ScanResult {
  const ScanResult({
    required this.overall,
    required this.skinAge,
    required this.skinType,
    required this.scores,
  });

  factory ScanResult.fromJson(Map<String, dynamic> json) => ScanResult(
        overall: json['overall'] as int,
        skinAge: json['skinAge'] as int,
        skinType: json['skinType'] as String? ?? '',
        scores: (json['scores'] as Map<String, dynamic>).map(
            (String key, dynamic value) =>
                MapEntry<String, int>(key, value as int)),
      );

  final int overall;
  final int skinAge;
  final String skinType;

  /// 15 scored concerns, higher = healthier (1–100).
  final Map<String, int> scores;
}

/// One scan in a client's series (seeded scans carry the full result flat).
class SkinScan {
  const SkinScan({
    required this.id,
    required this.label,
    required this.date,
    required this.stage,
    required this.sessionNumber,
    required this.result,
  });

  factory SkinScan.fromJson(Map<String, dynamic> json) => SkinScan(
        id: json['id'] as String,
        label: json['label'] as String,
        date: json['date'] as String,
        stage: json['stage'] as String,
        sessionNumber: json['sessionNumber'] as int,
        result: ScanResult.fromJson(json),
      );

  final String id;
  final String label;
  final String date;
  final String stage;
  final int sessionNumber;
  final ScanResult result;

  /// [date] parsed without timezone shifting (dates are calendar days).
  DateTime get dateTime => DateTime.parse(date);
}

/// A focus concern plus its optional per-concern note.
class FocusNote {
  const FocusNote({
    required this.concern,
    required this.note,
  });

  factory FocusNote.fromJson(Map<String, dynamic> json) => FocusNote(
        concern: json['concern'] as String,
        note: json['note'] as String? ?? '',
      );

  final String concern;
  final String note;
}

/// The plan shared to the client's series timeline.
class ClientPlan {
  const ClientPlan({
    required this.seriesName,
    required this.sessions,
    required this.focus,
    required this.productIds,
    required this.regimenAm,
    required this.regimenPm,
  });

  factory ClientPlan.fromJson(Map<String, dynamic> json) {
    final regimen = json['regimen'] as Map<String, dynamic>? ?? const {};
    return ClientPlan(
      seriesName: json['seriesName'] as String? ?? '',
      sessions: json['sessions'] as int? ?? 1,
      focus: (json['focus'] as List<dynamic>? ?? const [])
          .map((dynamic e) => FocusNote.fromJson(e as Map<String, dynamic>))
          .toList(),
      productIds: (json['productIds'] as List<dynamic>? ?? const [])
          .map((dynamic e) => e as String)
          .toList(),
      regimenAm: regimen['am'] as String? ?? '',
      regimenPm: regimen['pm'] as String? ?? '',
    );
  }

  final String seriesName;
  final int sessions;
  final List<FocusNote> focus;
  final List<String> productIds;
  final String regimenAm;
  final String regimenPm;
}

/// A client of the demo practice, with their scans and current plan.
class ClientProfile {
  const ClientProfile({
    required this.id,
    required this.name,
    required this.seriesName,
    required this.seriesTemplateId,
    required this.totalSessions,
    required this.scans,
    required this.plan,
  });

  factory ClientProfile.fromJson(Map<String, dynamic> json) => ClientProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        seriesName: json['seriesName'] as String? ?? '',
        seriesTemplateId: json['seriesTemplateId'] as String? ?? '',
        totalSessions: json['totalSessions'] as int? ?? 1,
        scans: (json['scans'] as List<dynamic>? ?? const [])
            .map((dynamic e) => SkinScan.fromJson(e as Map<String, dynamic>))
            .toList(),
        plan: ClientPlan.fromJson(json['plan'] as Map<String, dynamic>),
      );

  final String id;
  final String name;
  final String seriesName;
  final String seriesTemplateId;
  final int totalSessions;
  final List<SkinScan> scans;
  final ClientPlan plan;

  SkinScan get baselineScan => scans.first;
  SkinScan get latestScan => scans.last;

  /// First name for friendly copy, e.g. `Maya R.` -> `Maya`.
  String get firstName {
    final parts = name.split(RegExp(r'\s+'));
    return parts.isEmpty ? name : parts.first;
  }
}
