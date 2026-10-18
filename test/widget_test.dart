import 'package:flutter_test/flutter_test.dart';

import 'package:skinseries/main.dart';
import 'package:skinseries/services/demo_repository.dart';
import 'package:skinseries/state/app_state.dart';

Future<AppState> _loadDemoState() async {
  final repository = DemoRepository();
  await repository.load();
  return AppState(repository);
}

void main() {
  testWidgets('boots on Setup with demo badge and client scan link',
      (WidgetTester tester) async {
    final state = (await tester.runAsync(_loadDemoState))!;
    await tester.pumpWidget(SkinSeriesApp(state: state));
    await tester.pumpAndSettle();

    expect(find.text('Your practice'), findsOneWidget);
    expect(find.text('Demo mode'), findsOneWidget);
    expect(find.text('Luna Glow Skin Studio'), findsOneWidget);
    expect(
      find.text('https://scan.skinseries.app/s/lunaglow'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Text or email this link — clients scan from home before their '
        'visit. No app to install.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('bottom nav reaches Brief and Plan', (WidgetTester tester) async {
    final state = (await tester.runAsync(_loadDemoState))!;
    await tester.pumpWidget(SkinSeriesApp(state: state));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Brief'));
    await tester.pumpAndSettle();

    expect(find.text('Pre-visit brief'), findsOneWidget);
    expect(find.text('Maya R.'), findsOneWidget);
    expect(
      find.text('Session 6 of 6 · last scan Oct 5, 2026'),
      findsOneWidget,
    );
    expect(find.text('74'), findsOneWidget);
    expect(find.text('44'), findsOneWidget);
    expect(
      find.textContaining(
        'Cosmetic skin analysis for consultation and progress tracking. '
        'This is not a medical diagnosis.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();

    expect(find.text('Plan builder'), findsOneWidget);
    expect(find.text('Share plan to client view'), findsOneWidget);

    await tester.ensureVisible(find.text('Share plan to client view'));
    await tester.tap(find.text('Share plan to client view'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Plan shared — Maya will see it in her series timeline',
      ),
      findsOneWidget,
    );
    expect(find.text('Client preview'), findsOneWidget);
  });
}
