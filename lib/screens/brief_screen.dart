import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../util/score_bands.dart';
import 'screen_scaffold.dart';

const String kDisclaimer =
    'Cosmetic skin analysis for consultation and progress tracking. '
    'This is not a medical diagnosis.';

/// Pre-visit brief: latest scan turned into a consult brief.
class BriefScreen extends StatelessWidget {
  const BriefScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = state.client;
    final baseline = client.baselineScan;
    final latest = state.displayLatestScan;
    final focus = topFocusConcerns(latest);
    final gains = biggestGains(baseline, latest);
    final points = _talkingPoints(
      baseline: baseline,
      latest: latest,
      focus: focus,
      labelOf: state.labelFor,
    );

    return ScreenScaffold(
      title: 'Pre-visit brief',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(client.name, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(client.seriesName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Session ${latest.sessionNumber} of ${client.totalSessions} · '
              'last scan ${_formatDate(latest.dateTime)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed:
                      state.fetchInFlight ? null : state.fetchLatestScan,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: Text(
                    state.fetchInFlight ? 'Fetching…' : 'Fetch latest scan',
                  ),
                ),
                const SizedBox(width: 12),
                if (state.fetchedResult != null)
                  const Chip(
                    label: Text('From service'),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                  ),
              ],
            ),
            if (state.fetchMessage != null) ...[
              const SizedBox(height: 8),
              Text(state.fetchMessage!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Overall',
                    value: '${latest.result.overall}',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'Skin age',
                    value: '${latest.result.skinAge}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Focus areas', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    for (final entry in focus)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(state.labelFor(entry.key)),
                        subtitle: Text(bandLabel(entry.score)),
                        trailing: Text(
                          '${entry.score}',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Biggest gains since baseline',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (gains.isEmpty)
                      Text('No gains recorded yet.',
                          style: theme.textTheme.bodyMedium),
                    for (final gain in gains)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(child: Text(state.labelFor(gain.key))),
                            Chip(
                              label: Text('+${gain.delta}'),
                              backgroundColor:
                                  const Color(0xFF7D8C74).withOpacity(0.18),
                              side: BorderSide.none,
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Talking points', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    for (var i = 0; i < points.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: const Color(0xFFB0714F),
                              child: Text(
                                '${i + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Text(points[i])),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              kDisclaimer,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.headlineMedium),
          ],
        ),
      ),
    );
  }
}

/// Three plain-language sentences generated from the scan data.
List<String> _talkingPoints({
  required SkinScan baseline,
  required SkinScan latest,
  required List<({String key, int score})> focus,
  required String Function(String) labelOf,
}) {
  final gains = biggestGains(baseline, latest);
  final deltas = scoreDeltas(baseline, latest);
  final points = <String>[];

  if (gains.isEmpty) {
    points.add('Every scored area is holding at or above its baseline.');
  } else {
    final top = gains.first;
    points.add(
      '${labelOf(top.key)} is the biggest gain since baseline — up '
      '${top.delta} points to ${latest.result.scores[top.key]}.',
    );
  }

  final ranked = deltas.entries.toList()
    ..sort((a, b) {
      final byDelta = a.value.compareTo(b.value);
      return byDelta != 0 ? byDelta : a.key.compareTo(b.key);
    });
  final flat = ranked.first;
  if (flat.value < 0) {
    points.add(
      '${labelOf(flat.key)} is the honest flat area — down '
      '${flat.value.abs()} points since baseline, so name it plainly.',
    );
  } else if (flat.value == 0) {
    points.add(
      '${labelOf(flat.key)} is unchanged since baseline — a steady area '
      'to mention honestly.',
    );
  } else {
    points.add(
      'Nothing has slipped since baseline — every area sits at or above '
      'where it started.',
    );
  }

  final names = focus.map((entry) => labelOf(entry.key)).toList();
  points.add(
    '${_joinNames(names)} ${names.length == 1 ? 'is' : 'are'} where to '
    'spend time first — ${names.length == 1 ? 'it is' : 'they are'} what '
    "the plan's focus notes and AM/PM regimen point at.",
  );
  return points;
}

String _joinNames(List<String> names) {
  if (names.length <= 1) return names.join('');
  if (names.length == 2) return '${names.first} and ${names.last}';
  return '${names.sublist(0, names.length - 1).join(', ')}, and ${names.last}';
}

String _formatDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
