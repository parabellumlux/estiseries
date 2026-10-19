import 'package:flutter/material.dart';

import '../services/skin_analysis_service.dart';

/// Mode chip shown in the AppBar of every screen: "Demo mode" in the
/// default build, "Live mode" when built with
/// `--dart-define=SKINSERIES_LIVE=true` (see [AppConfig.liveBuild]).
class DemoModeBadge extends StatelessWidget {
  const DemoModeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(right: 8),
      child: Chip(
        label: Text(AppConfig.liveBuild ? 'Live mode' : 'Demo mode'),
        avatar: Icon(Icons.circle, size: 10, color: Color(0xFF7D8C74)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Shared scaffold: title AppBar + mode badge, cream body from the caller.
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({
    super.key,
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: const [DemoModeBadge()],
      ),
      body: child,
    );
  }
}
