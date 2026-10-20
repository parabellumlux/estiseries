import 'package:flutter_test/flutter_test.dart';
import 'package:skinseries/models.dart';

void main() {
  group('Offering JSON', () {
    test('full offering round-trips', () {
      const offering = Offering(
        id: 'off-1',
        kind: 'service',
        name: 'RF Microneedling',
        price: 350,
        unit: 'per session',
        durationMin: 60,
        description: 'Full-face RF treatment',
        active: true,
        createdAt: '2026-10-20T00:00:00.000Z',
      );

      final decoded = Offering.fromJson(offering.toJson());

      expect(decoded.id, 'off-1');
      expect(decoded.kind, 'service');
      expect(decoded.isService, isTrue);
      expect(decoded.isProduct, isFalse);
      expect(decoded.name, 'RF Microneedling');
      expect(decoded.price, 350);
      expect(decoded.unit, 'per session');
      expect(decoded.durationMin, 60);
      expect(decoded.description, 'Full-face RF treatment');
      expect(decoded.active, isTrue);
      expect(decoded.createdAt, '2026-10-20T00:00:00.000Z');
    });

    test('minimal product offering round-trips without optional fields', () {
      const offering = Offering(
        id: 'off-2',
        kind: 'product',
        name: 'Hydration Boost Serum',
        price: 64,
        active: false,
        createdAt: '2026-10-20T00:00:00.000Z',
      );

      final json = offering.toJson();
      expect(json.containsKey('unit'), isFalse);
      expect(json.containsKey('durationMin'), isFalse);
      expect(json.containsKey('description'), isFalse);

      final decoded = Offering.fromJson(json);
      expect(decoded.isProduct, isTrue);
      expect(decoded.unit, isNull);
      expect(decoded.durationMin, isNull);
      expect(decoded.active, isFalse);
    });

    test('missing fields default tolerantly', () {
      final decoded = Offering.fromJson(const {'name': 'Botox® Cosmetic'});
      expect(decoded.kind, 'service');
      expect(decoded.price, 0);
      expect(decoded.active, isTrue);
    });
  });

  group('ClientPlan service', () {
    const planWithoutService = ClientPlan(
      seriesName: 'Calm + Hydrate Renewal Series',
      sessions: 6,
      focus: [],
      regimenAm: '',
      regimenPm: '',
      products: [],
    );

    test('absent service parses as null and is not serialized', () {
      final decoded = ClientPlan.fromJson(planWithoutService.toJson());
      expect(decoded.service, isNull);
      expect(planWithoutService.toJson().containsKey('service'), isFalse);
    });

    test('service round-trips with name, price and unit', () {
      const plan = ClientPlan(
        seriesName: 'Calm + Hydrate Renewal Series',
        sessions: 6,
        focus: [],
        regimenAm: '',
        regimenPm: '',
        products: [],
        service: PlanService(
          name: 'RF Microneedling',
          price: 350,
          unit: 'per session',
        ),
      );

      final json = plan.toJson();
      expect(json['service'], {
        'name': 'RF Microneedling',
        'price': 350.0,
        'unit': 'per session',
      });

      final decoded = ClientPlan.fromJson(json);
      expect(decoded.service, isNotNull);
      expect(decoded.service!.name, 'RF Microneedling');
      expect(decoded.service!.price, 350);
      expect(decoded.service!.unit, 'per session');
    });

    test('service without unit round-trips', () {
      const service = PlanService(name: 'Signature Glow Facial', price: 120);
      final decoded = PlanService.fromJson(service.toJson());
      expect(decoded.name, 'Signature Glow Facial');
      expect(decoded.price, 120);
      expect(decoded.unit, isNull);
      expect(service.toJson().containsKey('unit'), isFalse);
    });

    test('non-map service values parse as null', () {
      expect(PlanService.tryParse(null), isNull);
      expect(PlanService.tryParse('RF Microneedling'), isNull);
      expect(PlanService.tryParse(42), isNull);
    });
  });

  group('PractitionerProfile logoUrl', () {
    test('parses logoUrl; absent stays null', () {
      final withLogo = PractitionerProfile.fromJson(const {
        'id': 'p1',
        'practiceName': 'Luna Glow Skin Studio',
        'practitionerName': 'Ava Luna',
        'accentColor': '#B0714F',
        'bookingLink': '',
        'logoUrl': '/api/practitioners/p1/logo',
      });
      expect(withLogo.logoUrl, '/api/practitioners/p1/logo');

      final without = PractitionerProfile.fromJson(const {
        'id': 'p1',
        'practiceName': 'Luna Glow Skin Studio',
        'practitionerName': 'Ava Luna',
        'accentColor': '#B0714F',
        'bookingLink': '',
      });
      expect(without.logoUrl, isNull);
    });
  });
}
