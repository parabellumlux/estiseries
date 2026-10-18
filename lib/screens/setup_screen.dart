import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../state/app_state.dart';
import 'screen_scaffold.dart';

/// The three accent swatches offered on Setup.
const List<({String name, String hex})> kAccentSwatches = [
  (name: 'Terracotta', hex: '#B0714F'),
  (name: 'Sage', hex: '#7D8C74'),
  (name: 'Plum', hex: '#7A5478'),
];

/// Setup: practice details, accent color, client scan link + QR.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.state});

  final AppState state;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _practiceName;
  late final TextEditingController _practitionerName;
  late final TextEditingController _bookingUrl;

  @override
  void initState() {
    super.initState();
    _practiceName = TextEditingController(text: widget.state.practice.name);
    _practitionerName =
        TextEditingController(text: widget.state.practice.practitioner);
    _bookingUrl = TextEditingController(text: widget.state.practice.bookingUrl);
  }

  @override
  void dispose() {
    _practiceName.dispose();
    _practitionerName.dispose();
    _bookingUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);

    return ScreenScaffold(
      title: 'Your practice',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Practice details', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            TextField(
              controller: _practiceName,
              decoration: const InputDecoration(
                labelText: 'Practice name',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => state.updatePractice(name: value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _practitionerName,
              decoration: const InputDecoration(
                labelText: 'Practitioner name',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => state.updatePractice(practitioner: value),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bookingUrl,
              decoration: const InputDecoration(
                labelText: 'Booking link',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.url,
              onChanged: (value) => state.updatePractice(bookingUrl: value),
            ),
            const SizedBox(height: 24),
            Text('Accent color', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final swatch in kAccentSwatches)
                  ChoiceChip(
                    label: Text(swatch.name),
                    avatar: CircleAvatar(
                      backgroundColor: Color(
                        int.parse('FF${swatch.hex.substring(1)}', radix: 16),
                      ),
                    ),
                    selected: state.practice.accent.toUpperCase() ==
                        swatch.hex.toUpperCase(),
                    onSelected: (_) => state.setAccent(swatch.hex),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _ScanLinkCard(state: state),
          ],
        ),
      ),
    );
  }
}

class _ScanLinkCard extends StatelessWidget {
  const _ScanLinkCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scanUrl = state.practice.scanUrl;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Client scan link', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Center(
              child: QrImageView(
                data: scanUrl,
                version: QrVersions.auto,
                size: 168,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              scanUrl,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Text or email this link — clients scan from home before their '
              'visit. No app to install.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
