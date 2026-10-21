import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models.dart';
import '../state/app_state.dart';
import 'screen_scaffold.dart';

/// Clients tab: the practitioner's own client list, add-client, and the
/// per-client detail (personal link + QR, plan summary, scan history).
class ClientsScreen extends StatelessWidget {
  const ClientsScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    if (!state.isAuthenticated) {
      return const ScreenScaffold(
        title: 'Clients',
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Create your practice or sign in on the Setup tab first — '
              'your clients will appear here.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final detail = state.selectedDetail;
    if (state.clientDetailOpen && detail != null) {
      return _ClientDetailView(state: state, detail: detail);
    }
    return ScreenScaffold(
      title: 'Clients',
      child: _ClientListView(state: state),
    );
  }
}

class _ClientListView extends StatefulWidget {
  const _ClientListView({required this.state});

  final AppState state;

  @override
  State<_ClientListView> createState() => _ClientListViewState();
}

class _ClientListViewState extends State<_ClientListView> {
  final _firstName = TextEditingController();

  @override
  void dispose() {
    _firstName.dispose();
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add client', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _firstName,
                    decoration: const InputDecoration(
                      labelText: 'First name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _add,
                    child: const Text('Add client'),
                  ),
                  if (state.clientsMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(state.clientsMessage!,
                        style: theme.textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (state.clients.isEmpty)
            Text(
              'No clients yet. Add your first client above — she gets a '
              'personal scan link of her own.',
              style: theme.textTheme.bodyMedium,
            ),
          for (final client in state.clients)
            Card(
              child: ListTile(
                title: Text(client.firstName),
                subtitle: Text(
                  client.scanCount == 1
                      ? '1 scan'
                      : '${client.scanCount} scans',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (client.pendingCount > 0)
                      Chip(
                        avatar: const Icon(Icons.hourglass_top, size: 14),
                        label: Text('${client.pendingCount} pending'),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                      ),
                    if (client.latestOverall != null)
                      Chip(
                        label: Text('${client.latestOverall}'),
                        visualDensity: VisualDensity.compact,
                        side: BorderSide.none,
                      ),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () => state.selectClient(client.id, openDetail: true),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final name = _firstName.text.trim();
    if (name.isEmpty) return;
    final ok = await widget.state.addClient(name);
    if (!mounted) return;
    if (ok) {
      _firstName.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$name added — her scan link is ready.')),
      );
    }
  }
}

class _ClientDetailView extends StatelessWidget {
  const _ClientDetailView({required this.state, required this.detail});

  final AppState state;
  final ClientDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = state.clientLinkFor(link: detail.link, token: detail.token);
    final plan = detail.plan;
    return ScreenScaffold(
      title: detail.firstName,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: state.closeClientDetail,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const Text('Back to clients'),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Her personal scan link',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Center(
                      child: QrImageView(
                        data: link,
                        version: QrVersions.auto,
                        size: 168,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      link,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Text or email this link — she scans from home before '
                      'her visit. No app to install. Her scans arrive here '
                      'for your review, then join her series timeline.',
                      style: theme.textTheme.bodySmall,
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
                    Text('Her plan', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (plan == null)
                      Text('No plan yet.', style: theme.textTheme.bodyMedium)
                    else ...[
                      Text(plan.seriesName, style: theme.textTheme.titleSmall),
                      Text('${plan.sessions} sessions',
                          style: theme.textTheme.bodySmall),
                      if (plan.focus.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final focus in plan.focus)
                              Chip(
                                label: Text(state.labelFor(focus.concern)),
                                visualDensity: VisualDensity.compact,
                                side: BorderSide.none,
                              ),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => state.goToTab(3),
                      child: const Text('Build her plan'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Scan history', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            if (detail.scans.isEmpty)
              Text(
                'No scans yet — they appear here as soon as she completes '
                'one from her link.',
                style: theme.textTheme.bodyMedium,
              ),
            for (final scan in detail.scans)
              Card(
                child: ListTile(
                  title: Text(scan.label),
                  subtitle: Text(
                    scan.isPending
                        ? '${_formatDate(scan.dateTime)} · Pending review — '
                            'accept it in her Brief'
                        : _formatDate(scan.dateTime),
                  ),
                  trailing: Text(
                    '${scan.result.overall}',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => _confirmDelete(context),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Delete client'),
            ),
            const SizedBox(height: 8),
            Text(
              'Deleting a client removes her plan and scan history, as '
              'promised in the client consent flow.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete client?'),
        content: Text(
          'Delete ${detail.firstName} and her scan history? This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep client'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete client'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final ok = await state.deleteClient(detail.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '${detail.firstName} deleted.' : 'Could not delete that client.',
        ),
      ),
    );
  }
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
