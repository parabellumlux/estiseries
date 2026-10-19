import 'package:flutter/material.dart';

import 'screens/brief_screen.dart';
import 'screens/plan_screen.dart';
import 'screens/setup_screen.dart';
import 'services/demo_repository.dart';
import 'services/skin_analysis_service.dart';
import 'state/app_state.dart';

const Color kCream = Color(0xFFFAF6F1);
const Color kTerracotta = Color(0xFFB0714F);
const Color kSage = Color(0xFF7D8C74);
const Color kInk = Color(0xFF2E2620);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = DemoRepository();
  await repository.load();
  // Service selection follows AppConfig: demo (seeded, local) by default;
  // live (backend proxy) when built with --dart-define=SKINSERIES_LIVE=true.
  final config = AppConfig.fromEnvironment();
  final SkinAnalysisService analysisService =
      config.mode == BackendMode.live
          ? LiveSkinAnalysisService(config: config)
          : DemoSkinAnalysisService(repository.demoClient.scans);
  runApp(
    SkinSeriesApp(
      state: AppState(
        repository,
        config: config,
        analysisService: analysisService,
      ),
    ),
  );
}

class SkinSeriesApp extends StatelessWidget {
  const SkinSeriesApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => MaterialApp(
        title: 'SkinSeries',
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
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
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

/// Bottom-nav shell: exactly three screens (Setup / Brief / Plan).
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.state});

  final AppState state;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          SetupScreen(state: widget.state),
          BriefScreen(state: widget.state),
          PlanScreen(state: widget.state),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (index) => setState(() => _index = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Setup',
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
