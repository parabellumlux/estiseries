import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:skinseries/main.dart';
import 'package:skinseries/models.dart';
import 'package:skinseries/services/api_client.dart';
import 'package:skinseries/state/app_state.dart';

import 'fake_api.dart';

ClientDetail _mayaDetail() => ClientDetail(
      id: 'client-1',
      firstName: 'Maya',
      createdAt: '2026-07-01T00:00:00.000Z',
      token: 'tok-maya',
      link: '/?c=tok-maya',
      plan: ClientPlan.fromJson(<String, dynamic>{
        'seriesName': 'Calm + Hydrate Renewal Series',
        'sessions': 6,
        'focus': [
          {'concern': 'moisture', 'note': 'Serum morning and night.'},
        ],
        'regimen': {'am': 'Cleanse - serum - SPF', 'pm': 'Cleanse - cream'},
        'products': [
          {'name': 'Hydration Boost Serum', 'price': 64},
        ],
      }),
      scans: [
        fakeScan('Baseline', '2026-07-13T00:00:00.000Z', 61, {
          'moisture': 42,
          'redness': 58,
          'radiance': 52,
        }),
        fakeScan('Scan 2', '2026-10-05T00:00:00.000Z', 74, {
          'moisture': 63,
          'redness': 74,
          'radiance': 70,
        }),
      ],
    );

FakeApi _fakeWithMaya() {
  final detail = _mayaDetail();
  return FakeApi(
    clients: [
      ClientSummary(
        id: detail.id,
        firstName: detail.firstName,
        createdAt: detail.createdAt,
        token: detail.token,
        link: detail.link,
        scanCount: 2,
        latestOverall: 74,
        latestScanAt: '2026-10-05T00:00:00.000Z',
        plan: detail.plan,
      ),
    ],
    details: {detail.id: detail},
  );
}

Future<AppState> _signedOutState() async {
  final state = AppState(
    api: _fakeWithMaya(),
    tokenStore: MemoryTokenStore(),
  );
  await state.bootstrap();
  return state;
}

Future<AppState> _signedInState(FakeApi api) async {
  final store = MemoryTokenStore('token-demo');
  api.token = 'token-demo';
  final state = AppState(api: api, tokenStore: store);
  await state.bootstrap();
  return state;
}

void main() {
  testWidgets('signed out: Setup shows create practice and sign in',
      (WidgetTester tester) async {
    final state = await _signedOutState();
    await tester.pumpWidget(SkinSeriesApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Your practice'), findsOneWidget);
    expect(find.text('Create my practice'), findsWidgets);
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Demo mode'), findsNothing);
    expect(find.textContaining('GlowDemo2026'), findsOneWidget);
  });

  testWidgets('sign in with the demo judge account loads the profile',
      (WidgetTester tester) async {
    final api = _fakeWithMaya();
    final state = AppState(api: api, tokenStore: MemoryTokenStore());
    await state.bootstrap();
    await tester.pumpWidget(SkinSeriesApp(state: state));
    await tester.pumpAndSettle();

    final loginField = find.widgetWithText(TextField, 'Email / login');
    await tester.ensureVisible(loginField);
    await tester.enterText(loginField, 'demo@estiseries.app');
    await tester.enterText(
      find.widgetWithText(TextField, 'Password'),
      'GlowDemo2026',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(api.lastLogin, 'demo@estiseries.app');
    expect(find.text('Save profile'), findsOneWidget);
    expect(find.text('Test Glow Studio'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
  });

  testWidgets('clients list, detail link, brief and plan save',
      (WidgetTester tester) async {
    final api = _fakeWithMaya();
    final state = await _signedInState(api);
    await tester.pumpWidget(SkinSeriesApp(state: state));
    await tester.pumpAndSettle();

    // Clients tab: Maya listed with scan count + latest overall.
    await tester.tap(find.text('Clients'));
    await tester.pumpAndSettle();
    expect(find.text('Maya'), findsWidgets);
    expect(find.text('2 scans'), findsOneWidget);

    // Detail: personal link, QR, plan summary, scan history.
    await tester.tap(find.text('Maya').first);
    await tester.pumpAndSettle();
    expect(
      find.text('https://estiseries.ignisalgos.com/?c=tok-maya'),
      findsOneWidget,
    );
    expect(find.text('Her plan'), findsOneWidget);
    expect(find.text('Baseline'), findsOneWidget);
    expect(find.text('Scan 2'), findsOneWidget);

    // Brief: driven by the selected client's stored scans.
    await tester.tap(find.text('Brief'));
    await tester.pumpAndSettle();
    expect(find.text('Pre-visit brief'), findsOneWidget);
    expect(find.text('74'), findsWidgets);
    expect(
      find.text(
        'Cosmetic skin analysis for consultation and progress tracking. '
        'This is not a medical diagnosis.',
      ),
      findsOneWidget,
    );

    // Plan: loads Maya's saved plan and saves via the API.
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(find.text('Plan for Maya'), findsOneWidget);
    expect(find.text('Hydration Boost Serum'), findsOneWidget);

    await tester.ensureVisible(find.text('Save plan'));
    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();

    expect(api.lastSavedPlanClientId, 'client-1');
    expect(api.lastSavedPlan?['seriesName'], 'Calm + Hydrate Renewal Series');
    expect(api.lastSavedPlan?['products'], [
      {'name': 'Hydration Boost Serum', 'price': 64.0},
    ]);
    expect(find.text('Client preview'), findsOneWidget);
  });

  testWidgets('brief empty state points at the client link',
      (WidgetTester tester) async {
    const detail = ClientDetail(
      id: 'client-2',
      firstName: 'June',
      createdAt: '2026-10-01T00:00:00.000Z',
      token: 'tok-june',
      link: '/?c=tok-june',
      plan: null,
      scans: [],
    );
    final api = FakeApi(
      clients: [
        ClientSummary(
          id: detail.id,
          firstName: 'June',
          createdAt: detail.createdAt,
          token: detail.token,
          link: detail.link,
          scanCount: 0,
          latestOverall: null,
          latestScanAt: null,
          plan: null,
        ),
      ],
      details: {detail.id: detail},
    );
    final state = await _signedInState(api);
    await tester.pumpWidget(SkinSeriesApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Brief'));
    await tester.pumpAndSettle();

    expect(find.text('No scans yet'), findsOneWidget);
    expect(find.text('View her scan link'), findsOneWidget);

    await tester.tap(find.text('View her scan link'));
    await tester.pumpAndSettle();
    expect(
      find.text('https://estiseries.ignisalgos.com/?c=tok-june'),
      findsOneWidget,
    );
  });
}
