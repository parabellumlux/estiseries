import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import '../util/score_bands.dart';
import 'screen_scaffold.dart';

const String kDisclaimer =
    'Cosmetic skin analysis for consultation and progress tracking. '
    'This is not a medical diagnosis.';

/// Pre-visit brief for the SELECTED client, fed by her real stored scans
/// (GET /api/me/clients/:id via AppState).
class BriefScreen extends StatelessWidget {
  const BriefScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = state.selectedDetail;

    if (!state.isAuthenticated || state.selectedClientId == null) {
      return ScreenScaffold(
        title: 'Pre-visit brief',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No client selected yet. Add a client on the Clients '
                  'tab and her pre-visit brief will appear here.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => state.goToTab(1),
                  child: const Text('Go to Clients'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (detail == null || state.detailLoading) {
      return const ScreenScaffold(
        title: 'Pre-visit brief',
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (detail.scans.isEmpty) {
      return ScreenScaffold(
        title: 'Pre-visit brief',
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(detail.firstName, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('No scans yet', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(
                        '${detail.firstName} has not scanned yet. Share her '
                        'personal scan link so she can scan from home before '
                        'her visit — her brief will build itself from that '
                        'first scan.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: state.openSelectedClientDetail,
                        child: const Text('View her scan link'),
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

    final baseline = detail.baselineScan!;
    final latest = detail.latestScan!;
    final focus = topFocusConcerns(latest);
    final gains = biggestGains(baseline, latest);
    final points = _talkingPoints(
      baseline: baseline,
      latest: latest,
      focus: focus,
      labelOf: state.labelFor,
    );
    final plan = detail.plan;

    return ScreenScaffold(
      title: 'Pre-visit brief',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(detail.firstName, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              plan?.seriesName ?? 'No series plan yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '${detail.scans.length} scan${detail.scans.length == 1 ? '' : 's'} · '
              'last scan ${_formatDate(latest.dateTime)}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: state.refreshSelectedClient,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh scans'),
            ),
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
                    Text('Biggest gains since first scan',
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
                              backgroundColor: state.accentColor,
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
    points.add('Every scored area is holding at or above its first scan.');
  } else {
    final top = gains.first;
    points.add(
      '${labelOf(top.key)} is the biggest gain since her first scan — up '
      '${top.delta} points to ${latest.result.scores[top.key]}.',
    );
  }

  final ranked = deltas.entries.toList()
    ..sort((a, b) {
      final byDelta = a.value.compareTo(b.value);
      return byDelta != 0 ? byDelta : a.key.compareTo(b.key);
    });
  if (ranked.isNotEmpty) {
    final flat = ranked.first;
    if (flat.value < 0) {
      points.add(
        '${labelOf(flat.key)} is the honest flat area — down '
        '${flat.value.abs()} points since her first scan, so name it plainly.',
      );
    } else if (flat.value == 0) {
      points.add(
        '${labelOf(flat.key)} is unchanged since her first scan — a steady '
        'area to mention honestly.',
      );
    } else {
      points.add(
        'Nothing has slipped since her first scan — every area sits at or '
        'above where it started.',
      );
    }
  }

  final names = focus.map((entry) => labelOf(entry.key)).toList();
  if (names.isNotEmpty) {
    points.add(
      '${_joinNames(names)} ${names.length == 1 ? 'is' : 'are'} where to '
      'spend time first — ${names.length == 1 ? 'it is' : 'they are'} what '
      "the plan's focus notes and AM/PM regimen point at.",
    );
  }
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
