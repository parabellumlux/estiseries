import 'package:flutter/material.dart';

import '../state/app_state.dart';
import 'screen_scaffold.dart';

/// The three accent swatches offered on Setup.
const List<({String name, String hex})> kAccentSwatches = [
  (name: 'Terracotta', hex: '#B0714F'),
  (name: 'Sage', hex: '#7D8C74'),
  (name: 'Plum', hex: '#7A5478'),
];

Color _swatchColor(String hex) =>
    Color(int.parse('FF${hex.substring(1)}', radix: 16));

/// Setup: create a practice / sign in when signed out; the loaded
/// practitioner profile (editable, saved via PUT /api/me) when signed in.
class SetupScreen extends StatelessWidget {
  const SetupScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (!state.bootstrapped) {
      return const ScreenScaffold(
        title: 'Your practice',
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final profile = state.profile;
    if (profile == null) {
      return ScreenScaffold(
        title: 'Your practice',
        child: _AuthForms(state: state),
      );
    }
    return ScreenScaffold(
      title: 'Your practice',
      child: _ProfileForm(
        key: ValueKey(profile.id),
        state: state,
      ),
    );
  }
}

class _AuthForms extends StatefulWidget {
  const _AuthForms({required this.state});

  final AppState state;

  @override
  State<_AuthForms> createState() => _AuthFormsState();
}

class _AuthFormsState extends State<_AuthForms> {
  final _practiceName = TextEditingController();
  final _practitionerName = TextEditingController();
  final _bookingLink = TextEditingController();
  final _login = TextEditingController();
  final _password = TextEditingController();
  String _accent = '#B0714F';

  @override
  void dispose() {
    _practiceName.dispose();
    _practitionerName.dispose();
    _bookingLink.dispose();
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (state.authMessage != null) ...[
            Text(
              state.authMessage!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 16),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Create my practice',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _practiceName,
                    decoration: const InputDecoration(
                      labelText: 'Practice name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _practitionerName,
                    decoration: const InputDecoration(
                      labelText: 'Practitioner name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _bookingLink,
                    decoration: const InputDecoration(
                      labelText: 'Booking link',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                  const SizedBox(height: 16),
                  Text('Accent color', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final swatch in kAccentSwatches)
                        ChoiceChip(
                          label: Text(swatch.name),
                          avatar: CircleAvatar(
                            backgroundColor: _swatchColor(swatch.hex),
                          ),
                          selected: _accent == swatch.hex,
                          onSelected: (_) =>
                              setState(() => _accent = swatch.hex),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: state.busy ? null : _create,
                    child: const Text('Create my practice'),
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
                  Text('Sign in', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _login,
                    decoration: const InputDecoration(
                      labelText: 'Email / login',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    decoration: const InputDecoration(
                      labelText: 'Password',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: state.busy ? null : _signIn,
                    child: const Text('Sign in'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Judges: sign in with demo@estiseries.app / GlowDemo2026',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (state.busy) ...[
            const SizedBox(height: 16),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  Future<void> _create() async {
    final ok = await widget.state.createPractice(
      practiceName: _practiceName.text.trim(),
      practitionerName: _practitionerName.text.trim(),
      bookingLink: _bookingLink.text.trim(),
      accent: _accent,
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Practice created — you are signed in.')),
      );
    }
  }

  Future<void> _signIn() async {
    final ok = await widget.state.signIn(
      _login.text.trim(),
      _password.text,
    );
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Signed in.')),
      );
    }
  }
}

class _ProfileForm extends StatefulWidget {
  const _ProfileForm({super.key, required this.state});

  final AppState state;

  @override
  State<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends State<_ProfileForm> {
  late final TextEditingController _practiceName;
  late final TextEditingController _practitionerName;
  late final TextEditingController _bookingLink;

  @override
  void initState() {
    super.initState();
    final profile = widget.state.profile!;
    _practiceName = TextEditingController(text: profile.practiceName);
    _practitionerName = TextEditingController(text: profile.practitionerName);
    _bookingLink = TextEditingController(text: profile.bookingLink);
  }

  @override
  void dispose() {
    _practiceName.dispose();
    _practitionerName.dispose();
    _bookingLink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final profile = state.profile!;
    final theme = Theme.of(context);
    return SingleChildScrollView(
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
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _practitionerName,
            decoration: const InputDecoration(
              labelText: 'Practitioner name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bookingLink,
            decoration: const InputDecoration(
              labelText: 'Booking link',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _save,
            child: const Text('Save profile'),
          ),
          if (state.profileMessage != null) ...[
            const SizedBox(height: 8),
            Text(state.profileMessage!, style: theme.textTheme.bodySmall),
          ],
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
                    backgroundColor: _swatchColor(swatch.hex),
                  ),
                  selected:
                      profile.accent.toUpperCase() == swatch.hex.toUpperCase(),
                  onSelected: (_) => state.setAccent(swatch.hex),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Each client gets her own scan link',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    'Open the Clients tab to add a client and share her '
                    'personal link and QR code.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => state.goToTab(1),
                    child: const Text('Go to Clients'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => state.signOut(),
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final ok = await widget.state.saveProfile(
      practiceName: _practiceName.text.trim(),
      practitionerName: _practitionerName.text.trim(),
      bookingLink: _bookingLink.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Profile saved.' : 'Could not save your profile.'),
      ),
    );
  }
}
