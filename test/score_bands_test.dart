import 'package:flutter_test/flutter_test.dart';

import 'package:skinseries/models.dart';
import 'package:skinseries/util/score_bands.dart';

SkinScan _scan(String label, Map<String, int> scores) => SkinScan.fromJson(
      <String, dynamic>{
        'taskId': 'task-$label',
        'label': label,
        'timestamp': '2026-07-13T00:00:00.000Z',
        'result': <String, dynamic>{
          'overall': 61,
          'skinAge': 47,
          'skinType': 'Combination',
          'scores': scores,
        },
      },
    );

void main() {
  group('bandLabel', () {
    test('maps scores to the SPEC bands at every boundary', () {
      expect(bandLabel(100), 'Strong');
      expect(bandLabel(80), 'Strong');
      expect(bandLabel(79), 'Good');
      expect(bandLabel(65), 'Good');
      expect(bandLabel(64), 'Fair — worth focus');
      expect(bandLabel(50), 'Fair — worth focus');
      expect(bandLabel(49), 'A top focus area');
      expect(bandLabel(1), 'A top focus area');
    });
  });

  group('topFocusConcerns', () {
    test('returns the three lowest scores of a scan, lowest first', () {
      final scan = _scan('Session 6', <String, int>{
        'wrinkle': 65,
        'pore': 66,
        'texture': 69,
        'acne': 71,
        'oiliness': 70,
        'radiance': 70,
        'eyeBag': 60,
        'ageSpot': 69,
        'darkCircle': 62,
        'droopyUpperEyelid': 77,
        'droopyLowerEyelid': 79,
        'firmness': 69,
        'moisture': 63,
        'redness': 74,
        'tearTrough': 67,
      });

      final focus = topFocusConcerns(scan);

      expect(focus, hasLength(3));
      expect(focus.map((entry) => entry.key).toList(),
          ['eyeBag', 'darkCircle', 'moisture']);
      expect(focus.map((entry) => entry.score).toList(), [60, 62, 63]);
    });
  });

  group('biggestGains / scoreDeltas', () {
    test('ranks positive deltas against the first scan and keeps negatives out',
        () {
      final baseline = _scan('Baseline', <String, int>{
        'moisture': 40,
        'redness': 60,
        'radiance': 55,
        'ageSpot': 70,
      });
      final latest = _scan('Scan 3', <String, int>{
        'moisture': 61,
        'redness': 66,
        'radiance': 73,
        'ageSpot': 68,
      });

      final deltas = scoreDeltas(baseline, latest);
      expect(deltas, <String, int>{
        'moisture': 21,
        'redness': 6,
        'radiance': 18,
        'ageSpot': -2,
      });

      final gains = biggestGains(baseline, latest);
      expect(gains.map((entry) => entry.key).toList(),
          ['moisture', 'radiance', 'redness']);
      expect(gains.map((entry) => entry.delta).toList(), [21, 18, 6]);
      expect(gains.any((entry) => entry.key == 'ageSpot'), isFalse);
    });
  });

  group('ClientPlan (contract v2)', () {
    test('round-trips with products embedded as {name, price}', () {
      final plan = ClientPlan.fromJson(<String, dynamic>{
        'seriesName': 'Calm + Hydrate Renewal Series',
        'sessions': 6,
        'focus': [
          {'concern': 'moisture', 'note': 'Serum AM + PM'},
        ],
        'regimen': {'am': 'Cleanse, serum', 'pm': 'Cleanse, cream'},
        'products': [
          {'name': 'Hydration Boost Serum', 'price': 64},
        ],
      });

      expect(plan.products.single.name, 'Hydration Boost Serum');
      expect(plan.products.single.price, 64.0);
      final json = plan.toJson();
      expect(json['products'], [
        {'name': 'Hydration Boost Serum', 'price': 64.0},
      ]);
      expect(json['regimen'], {'am': 'Cleanse, serum', 'pm': 'Cleanse, cream'});
    });
  });
}
