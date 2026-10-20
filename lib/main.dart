import 'package:flutter/material.dart';

import 'screens/brief_screen.dart';
import 'screens/clients_screen.dart';
import 'screens/plan_screen.dart';
import 'screens/setup_screen.dart';
import 'services/api_client.dart';
import 'state/app_state.dart';

const Color kCream = Color(0xFFFAF6F1);
const Color kTerracotta = Color(0xFFB0714F);
const Color kSage = Color(0xFF7D8C74);
const Color kInk = Color(0xFF2E2620);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final state = AppState(
    api: HttpApiClient(config: config),
    tokenStore: const SharedPreferencesTokenStore(),
    config: config,
  );
  // Restores the persisted practitioner token (if any) and loads the
  // profile + clients from the live backend. The Setup screen shows a
  // loading state until bootstrapping settles.
  state.bootstrap();
  runApp(SkinSeriesApp(state: state));
}

class SkinSeriesApp extends StatelessWidget {
  const SkinSeriesApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'EstiSeries',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(state.accentColor),
        home: HomeShell(state: state),
      ),
    );
  }
}

ThemeData _buildTheme(Color accent) {
  final scheme = ColorScheme.fromSeed(seedColor: accent).copyWith(
    primary: accent,
    onPrimary: Colors.white,
    secondary: kSage,
    onSecondary: Colors.white,
    surface: kCream,
    onSurface: kInk,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Colors.white,
    surfaceContainer: Colors.white,
    surfaceContainerHigh: const Color(0xFFF3ECE3),
    surfaceContainerHighest: const Color(0xFFEFE7DC),
    onSurfaceVariant: const Color(0xFF5C5248),
    outline: const Color(0xFFC9BEB1),
  );
  final textTheme = ThemeData.light().textTheme;
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    textTheme: textTheme.copyWith(
      // UI/UX audit F1: bodySmall carries real content (brief disclaimers,
      // plan notes, status messages) — floor it at 13.5sp, not the 12sp
      // M3 default, for the practitioner audience.
      bodySmall: textTheme.bodySmall?.copyWith(fontSize: 13.5),
    ),
    scaffoldBackgroundColor: kCream,
    appBarTheme: const AppBarTheme(
      backgroundColor: kCream,
      foregroundColor: kInk,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: accent.withOpacity(0.16),
      labelTextStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: const CardTheme(
      color: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(color: Color(0xFFE8DFD4)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: kInk,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
    dividerTheme: const DividerThemeData(color: Color(0xFFE8DFD4)),
  );
}

/// Bottom-nav shell: Setup / Clients / Brief / Plan. The selected tab
/// lives in [AppState] so screens can send the practitioner across tabs
/// (e.g. "Build her plan", the no-scans link panel).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: state.tabIndex,
        children: [
          SetupScreen(state: state),
          ClientsScreen(state: state),
          BriefScreen(state: state),
          PlanScreen(state: state),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: state.tabIndex,
        onDestinationSelected: state.goToTab,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Setup',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Clients',
          ),
          NavigationDestination(
            icon: Icon(Icons.summarize_outlined),
            selectedIcon: Icon(Icons.summarize),
            label: 'Brief',
          ),
          NavigationDestination(
            icon: Icon(Icons.playlist_add_check_outlined),
            selectedIcon: Icon(Icons.playlist_add_check),
            label: 'Plan',
          ),
        ],
      ),
    );
  }
}
