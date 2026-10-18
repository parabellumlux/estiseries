import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models.dart';

/// Loads and parses the seeded demo data once.
class DemoRepository {
  /// Asset path declared in `pubspec.yaml`.
  static const String assetPath = 'assets/demo/demo_data.json';

  Practice practice = _placeholderPractice;
  List<Product> products = const [];
  List<SeriesTemplate> seriesTemplates = const [];
  List<ClientProfile> clients = const [];

  /// Concern key -> display label, in seeded order.
  Map<String, String> concernLabels = const {};

  bool _loaded = false;
  bool get isLoaded => _loaded;

  /// Loads the demo asset and parses it.
  Future<void> load() async {
    final raw = await rootBundle.loadString(assetPath);
    loadFromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Parses an already-decoded demo data document.
  void loadFromJson(Map<String, dynamic> json) {
    practice = Practice.fromJson(json['practice'] as Map<String, dynamic>);
    products = (json['products'] as List<dynamic>? ?? const [])
        .map((dynamic e) => Product.fromJson(e as Map<String, dynamic>))
        .toList();
    seriesTemplates = (json['seriesTemplates'] as List<dynamic>? ?? const [])
        .map((dynamic e) => SeriesTemplate.fromJson(e as Map<String, dynamic>))
        .toList();
    clients = (json['clients'] as List<dynamic>? ?? const [])
        .map((dynamic e) => ClientProfile.fromJson(e as Map<String, dynamic>))
        .toList();
    concernLabels = {
      for (final item in json['concerns'] as List<dynamic>? ?? const [])
        (item as Map<String, dynamic>)['key'] as String:
            item['label'] as String,
    };
    _loaded = true;
  }

  /// The seeded demo client.
  ClientProfile get demoClient => clients.first;

  SeriesTemplate templateById(String id) => seriesTemplates.firstWhere(
        (template) => template.id == id,
        orElse: () => seriesTemplates.first,
      );

  static const Practice _placeholderPractice = Practice(
    id: '',
    name: '',
    practitioner: '',
    bookingUrl: '',
    scanUrl: '',
    tagline: '',
    accent: '#B0714F',
  );
}
