import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';
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
          _LogoSection(state: state),
          const SizedBox(height: 24),
          _OfferingsSection(state: state),
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

/// "$350", "$12 per unit", "$120 · 60 min" — the price label used in the
/// offerings list.
String _offeringPriceLabel(Offering offering) {
  final price = offering.price == offering.price.roundToDouble()
      ? '\$${offering.price.toStringAsFixed(0)}'
      : '\$${offering.price.toStringAsFixed(2)}';
  var label = price;
  if (offering.unit != null && offering.unit!.isNotEmpty) {
    label += ' ${offering.unit}';
  }
  if (offering.durationMin != null) label += ' · ${offering.durationMin} min';
  return label;
}

String _priceText(double price) => price == price.roundToDouble()
    ? price.toStringAsFixed(0)
    : price.toStringAsFixed(2);

/// Practice logo: shown to clients in the header of their series page.
class _LogoSection extends StatelessWidget {
  const _LogoSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logoUrl = state.profile!.logoUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Practice logo', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        if (logoUrl != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.network(
              state.config.base + logoUrl,
              height: 72,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const SizedBox(
                height: 72,
                child: Center(child: Text('Logo could not be loaded')),
              ),
            ),
          )
        else
          Container(
            height: 72,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                'No logo yet — your practice initials are shown instead',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _pickAndUpload(context),
              icon: const Icon(Icons.upload_outlined, size: 18),
              label: Text(logoUrl != null ? 'Change logo' : 'Upload logo'),
            ),
            if (logoUrl != null)
              TextButton(
                onPressed: () => state.removeLogo(),
                child: const Text('Remove logo'),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickAndUpload(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final ok = await state.uploadLogo(bytes, picked.mimeType ?? 'image/jpeg');
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok ? 'Logo saved.' : 'Could not save your logo.'),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not read that image.')),
      );
    }
  }
}

/// Services & products: the practitioner's own menu, with prices.
class _OfferingsSection extends StatelessWidget {
  const _OfferingsSection({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offerings = state.offerings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Services & products', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (offerings.isEmpty)
          Text(
            'Add the services and products your spa offers — Botox, RF '
            'microneedling, facials, retail products — with your prices. '
            'Clients see them on their series page, and your products '
            'appear in the Plan Builder.',
            style: theme.textTheme.bodySmall,
          )
        else
          for (final offering in offerings)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                offering.name,
                style: offering.active
                    ? null
                    : TextStyle(color: theme.disabledColor),
              ),
              subtitle: Text(
                '${offering.isService ? 'Service' : 'Product'} · '
                '${_offeringPriceLabel(offering)}'
                '${offering.active ? '' : ' · Inactive'}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete ${offering.name}',
                onPressed: () => _confirmDelete(context, offering),
              ),
              onTap: () => _openEditor(context, existing: offering),
            ),
        if (state.offeringsMessage != null) ...[
          const SizedBox(height: 8),
          Text(state.offeringsMessage!, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => _openEditor(context, kind: 'service'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add service'),
            ),
            OutlinedButton.icon(
              onPressed: () => _openEditor(context, kind: 'product'),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add product'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    Offering? existing,
    String kind = 'service',
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => _OfferingEditor(
        state: state,
        existing: existing,
        initialKind: existing?.kind ?? kind,
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Offering offering,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this item?'),
        content: Text('${offering.name} will be removed from your menu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.deleteOffering(offering.id);
  }
}

/// Add/edit dialog for one offering.
class _OfferingEditor extends StatefulWidget {
  const _OfferingEditor({
    required this.state,
    required this.initialKind,
    this.existing,
  });

  final AppState state;
  final Offering? existing;
  final String initialKind;

  @override
  State<_OfferingEditor> createState() => _OfferingEditorState();
}

class _OfferingEditorState extends State<_OfferingEditor> {
  late String _kind;
  late bool _active;
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _unit;
  late final TextEditingController _duration;
  late final TextEditingController _description;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _kind = existing?.kind ?? widget.initialKind;
    _active = existing?.active ?? true;
    _name = TextEditingController(text: existing?.name ?? '');
    _price = TextEditingController(
      text: existing == null ? '' : _priceText(existing.price),
    );
    _unit = TextEditingController(text: existing?.unit ?? '');
    _duration = TextEditingController(
      text: existing?.durationMin?.toString() ?? '',
    );
    _description = TextEditingController(text: existing?.description ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _unit.dispose();
    _duration.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNew = widget.existing == null;
    return AlertDialog(
      title: Text(isNew ? 'Add to your menu' : 'Edit item'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              value: _kind,
              decoration: const InputDecoration(
                labelText: 'Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'service', child: Text('Service')),
                DropdownMenuItem(value: 'product', child: Text('Product')),
              ],
              onChanged: (value) =>
                  setState(() => _kind = value ?? _kind),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'RF Microneedling',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              decoration: const InputDecoration(
                labelText: 'Price',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unit,
              decoration: const InputDecoration(
                labelText: 'Unit (optional)',
                hintText: 'per session, per unit…',
                border: OutlineInputBorder(),
              ),
            ),
            if (_kind == 'service') ...[
              const SizedBox(height: 12),
              TextField(
                controller: _duration,
                decoration: const InputDecoration(
                  labelText: 'Duration (minutes, optional)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _description,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: const Text('Clients can see active items'),
              value: _active,
              onChanged: (value) => setState(() => _active = value),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(
                _error!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!isNew)
          TextButton(
            onPressed: _saving ? null : _delete,
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.replaceAll('\$', '').trim());
    if (name.isEmpty) {
      setState(() => _error = 'Give it a name.');
      return;
    }
    if (price == null || price < 0 || price > 100000) {
      setState(() => _error = 'Enter a price between \$0 and \$100,000.');
      return;
    }
    int? durationMin;
    if (_kind == 'service' && _duration.text.trim().isNotEmpty) {
      durationMin = int.tryParse(_duration.text.trim());
      if (durationMin == null || durationMin < 0 || durationMin > 1440) {
        setState(() => _error = 'Duration must be 0–1440 minutes.');
        return;
      }
    }
    final unit = _unit.text.trim();
    final description = _description.text.trim();
    final offering = Offering(
      id: widget.existing?.id ?? '',
      kind: _kind,
      name: name,
      price: price,
      unit: unit.isEmpty ? null : unit,
      durationMin: durationMin,
      description: description.isEmpty ? null : description,
      active: _active,
      createdAt: widget.existing?.createdAt ?? '',
    );
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = widget.existing == null
        ? await widget.state.createOffering(offering)
        : await widget.state.updateOffering(offering);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = widget.state.offeringsMessage ?? 'Could not save that item.';
      });
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this item?'),
        content: Text('${existing.name} will be removed from your menu.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await widget.state.deleteOffering(existing.id);
    if (!mounted) return;
    Navigator.pop(context);
  }
}
