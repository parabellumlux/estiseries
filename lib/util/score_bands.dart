import '../models.dart';

/// Plain-language band for a 1–100 concern score (per SPEC).
///
/// >=80 "Strong" · 65–79 "Good" · 50–64 "Fair — worth focus" ·
/// <50 "A top focus area".
String bandLabel(int score) {
  if (score >= 80) return 'Strong';
  if (score >= 65) return 'Good';
  if (score >= 50) return 'Fair — worth focus';
  return 'A top focus area';
}

/// The 3 lowest scored concerns of [scan], lowest first.
List<({String key, int score})> topFocusConcerns(SkinScan scan) {
  final ranked = scan.result.scores.entries
      .map((entry) => (key: entry.key, score: entry.value))
      .toList()
    ..sort((a, b) {
      final byScore = a.score.compareTo(b.score);
      return byScore != 0 ? byScore : a.key.compareTo(b.key);
    });
  return ranked.take(3).toList();
}

/// Per-concern delta of [latest] vs [baseline] (positive = higher score).
Map<String, int> scoreDeltas(SkinScan baseline, SkinScan latest) {
  final deltas = <String, int>{};
  for (final entry in latest.result.scores.entries) {
    final base = baseline.result.scores[entry.key];
    if (base != null) {
      deltas[entry.key] = entry.value - base;
    }
  }
  return deltas;
}

/// The top 3 positive deltas of [latest] vs [baseline], biggest first.
List<({String key, int delta})> biggestGains(
    SkinScan baseline, SkinScan latest) {
  final gains = scoreDeltas(baseline, latest)
      .entries
      .where((entry) => entry.value > 0)
      .map((entry) => (key: entry.key, delta: entry.value))
      .toList()
    ..sort((a, b) {
      final byDelta = b.delta.compareTo(a.delta);
      return byDelta != 0 ? byDelta : a.key.compareTo(b.key);
    });
  return gains.take(3).toList();
}
