import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:skinseries/main.dart';
import 'package:skinseries/models.dart';
import 'package:skinseries/services/api_client.dart';
import 'package:skinseries/state/app_state.dart';

import 'fake_api.dart';

const _scoresA = {'moisture': 42, 'redness': 58, 'radiance': 52};
const _scoresB = {'moisture': 63, 'redness': 74, 'radiance': 70};
const _scoresP = {'moisture': 95, 'redness': 90, 'radiance': 91};

ClientDetail _mayaWithPending() => ClientDetail(
      id: 'client-1',
      firstName: 'Maya',
      createdAt: '2026-07-01T00:00:00.000Z',
      token: 'tok-maya',
      link: '/?c=tok-maya',
      plan: null,
      scans: [
        fakeScan('Baseline', '2026-07-13T00:00:00.000Z', 61, _scoresA),
        fakeScan('Scan 2', '2026-10-05T00:00:00.000Z', 74, _scoresB),
        fakeScan('Session 7', '2026-10-21T00:00:00.000Z', 88, _scoresP,
            status: 'pending'),
      ],
    );

FakeApi _fakeFor(ClientDetail detail, {int pendingCount = 0}) {
  final accepted = detail.acceptedScans;
  return FakeApi(
    clients: [
      ClientSummary(
        id: detail.id,
        firstName: detail.firstName,
        createdAt: detail.createdAt,
        token: detail.token,
        link: detail.link,
        scanCount: accepted.length,
        latestOverall: accepted.isEmpty ? null : accepted.last.result.overall,
        latestScanAt: accepted.isEmpty ? null : accepted.last.timestamp,
        plan: detail.plan,
        pendingCount: pendingCount,
      ),
    ],
    details: {detail.id: detail},
  );
}

Future<AppState> _signedInState(FakeApi api) async {
  api.token = 'token-demo';
  final state = AppState(api: api, tokenStore: MemoryTokenStore('token-demo'));
  await state.bootstrap();
  return state;
}

void main() {
  group('models (v2.3 queue)', () {
    test('scan status parses; missing status means accepted', () {
      final pending = fakeScan('P', '2026-10-21T00:00:00.000Z', 50, _scoresA,
          status: 'pending');
      expect(pending.isPending, isTrue);
      final legacy = SkinScan.fromJson(<String, dynamic>{
        'taskId': 't-legacy',
        'label': 'Old',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'result': <String, dynamic>{
          'overall': 55,
          'skinAge': 40,
          'skinType': 'Dry',
          'scores': _scoresA,
        },
      });
      expect(legacy.isPending, isFalse);
      expect(legacy.status, 'accepted');
    });

    test('detail splits accepted/pending; trend ends exclude pending', () {
      final detail = _mayaWithPending();
      expect(detail.acceptedScans.length, 2);
      expect(detail.pendingScans.length, 1);
      expect(detail.baselineScan!.result.overall, 61);
      // The pending scan has the highest overall (88) but is NOT latest.
      expect(detail.latestScan!.result.overall, 74);
    });

    test('summary parses pendingCount and defaults it to 0', () {
      final withCount = ClientSummary.fromJson(<String, dynamic>{
        'id': 'c1',
        'firstName': 'Maya',
        'pendingCount': 3,
      });
      expect(withCount.pendingCount, 3);
      final without = ClientSummary.fromJson(<String, dynamic>{
        'id': 'c1',
        'firstName': 'Maya',
      });
      expect(without.pendingCount, 0);
    });
  });

  testWidgets('brief shows the pending section; math stays accepted-only',
      (WidgetTester tester) async {
    final api = _fakeFor(_mayaWithPending(), pendingCount: 1);
    final state = await _signedInState(api);
    await tester.pumpWidget(SkinSeriesApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Brief'));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for your review (1)'), findsOneWidget);
    expect(find.text('Session 7'), findsOneWidget);
    // Header counts accepted scans only, and the Overall stat is the
    // latest ACCEPTED scan (74) — not the pending 88.
    expect(find.textContaining('2 scans ·'), findsOneWidget);
    expect(find.text('74'), findsWidgets);
  });

  testWidgets('accept is one tap and moves the scan into the series',
      (WidgetTester tester) async {
    final api = _fakeFor(_mayaWithPending(), pendingCount: 1);
    final state = await _signedInState(api);
    await tester.pumpWidget(SkinSeriesApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Brief'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Accept'));
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    expect(api.lastAcceptedTaskId, 'task-Session 7');
    expect(find.text('Waiting for your review (1)'), findsNothing);
    expect(find.textContaining('3 scans ·'), findsOneWidget);
    // Now the accepted 88 is the latest scan in the brief.
    expect(state.selectedDetail!.acceptedScans.length, 3);
    expect(state.selectedDetail!.latestScan!.result.overall, 88);
    expect(state.clients.first.pendingCount, 0);
    expect(state.clients.first.scanCount, 3);
  });

  testWidgets('discard confirms, then removes the scan entirely',
      (WidgetTester tester) async {
    final api = _fakeFor(_mayaWithPending(), pendingCount: 1);
    final state = await _signedInState(api);
    await tester.pumpWidget(SkinSeriesApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Brief'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(OutlinedButton, 'Discard'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Discard this scan?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Discard scan'));
    await tester.pumpAndSettle();

    expect(api.lastDiscardedTaskId, 'task-Session 7');
    expect(find.text('Waiting for your review (1)'), findsNothing);
    expect(state.selectedDetail!.scans.length, 2);
    expect(
      state.selectedDetail!.scans.any((s) => s.taskId == 'task-Session 7'),
      isFalse,
    );
  });

  testWidgets('clients list shows a pending badge',
      (WidgetTester tester) async {
    final api = _fakeFor(_mayaWithPending(), pendingCount: 1);
    final state = await _signedInState(api);
    await tester.pumpWidget(SkinSeriesApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clients'));
    await tester.pumpAndSettle();

    expect(find.text('1 pending'), findsOneWidget);
    expect(find.text('2 scans'), findsOneWidget);
  });

  testWidgets('a first scan that is still pending waits in the brief',
      (WidgetTester tester) async {
    final detail = ClientDetail(
      id: 'client-9',
      firstName: 'June',
      createdAt: '2026-10-20T00:00:00.000Z',
      token: 'tok-june',
      link: '/?c=tok-june',
      plan: null,
      scans: [
        fakeScan('Baseline', '2026-10-21T00:00:00.000Z', 66, _scoresB,
            status: 'pending'),
      ],
    );
    final api = _fakeFor(detail, pendingCount: 1);
    final state = await _signedInState(api);
    await tester.pumpWidget(SkinSeriesApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Brief'));
    await tester.pumpAndSettle();

    expect(find.text('No scans yet'), findsOneWidget);
    expect(find.text('Waiting for your review (1)'), findsOneWidget);

    await tester.ensureVisible(find.text('Accept'));
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();

    // Accepted: the brief now builds from that first scan.
    expect(find.text('Waiting for your review (1)'), findsNothing);
    expect(find.text('No scans yet'), findsNothing);
    expect(find.textContaining('1 scan ·'), findsOneWidget);
  });
}
