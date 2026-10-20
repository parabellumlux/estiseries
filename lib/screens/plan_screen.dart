import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import 'screen_scaffold.dart';

/// Plan builder for the SELECTED client: template, sessions, focus notes,
/// regimen, products. Saving PUTs the plan to the backend, with products
/// embedded as `{name, price}` (contract v2).
class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key, required this.state});

  final AppState state;

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  late final TextEditingController _regimenAm;
  late final TextEditingController _regimenPm;
  final Map<String, TextEditingController> _noteControllers = {};
  int _seenDraftVersion = -1;

  @override
  void initState() {
    super.initState();
    _regimenAm = TextEditingController(text: widget.state.draft.regimenAm);
    _regimenPm = TextEditingController(text: widget.state.draft.regimenPm);
    _seenDraftVersion = widget.state.draftVersion;
    widget.state.addListener(_syncFromDraft);
  }

  @override
  void dispose() {
    widget.state.removeListener(_syncFromDraft);
    _regimenAm.dispose();
    _regimenPm.dispose();
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  /// When the selected client changes, AppState reloads the draft from
  /// that client's saved plan and bumps draftVersion — resync the fields.
  void _syncFromDraft() {
    if (!mounted || widget.state.draftVersion == _seenDraftVersion) return;
    _seenDraftVersion = widget.state.draftVersion;
    _regimenAm.text = widget.state.draft.regimenAm;
    _regimenPm.text = widget.state.draft.regimenPm;
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    _noteControllers.clear();
    setState(() {});
  }

  TextEditingController _noteFor(String concern) =>
      _noteControllers.putIfAbsent(
        concern,
        () => TextEditingController(text: widget.state.draft.notes[concern]),
      );

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);

    if (!state.isAuthenticated || state.selectedClientId == null) {
      return ScreenScaffold(
        title: 'Plan builder',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No client selected yet. Add or choose a client on the '
                  'Clients tab and build her plan here.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => state.goToTab(1),
                  child: const Text('Go to Clients'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final draft = state.draft;
    final template =
        state.templates.firstWhere((t) => t.id == draft.templateId);
    final clientName =
        state.selectedDetail?.firstName ?? state.selectedSummary?.firstName ?? '';
    final currentService = draft.service;
    final serviceOnMenu = currentService != null &&
        state.activeServices.any((s) => s.name == currentService.name);

    return ScreenScaffold(
      title: 'Plan builder',
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Plan for $clientName',
              style: theme.textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Series template', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: draft.templateId,
                      decoration:
                          const InputDecoration(border: OutlineInputBorder()),
                      items: [
                        for (final item in state.templates)
                          DropdownMenuItem(
                            value: item.id,
                            child: Text(item.name),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) state.selectTemplate(value);
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(template.description,
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sessions', style: theme.textTheme.titleMedium),
                          Text('1–12 sessions',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fewer sessions',
                      onPressed: draft.sessions > 1
                          ? () => state.setSessions(draft.sessions - 1)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('${draft.sessions}',
                        style: theme.textTheme.titleLarge),
                    IconButton(
                      tooltip: 'More sessions',
                      onPressed: draft.sessions < 12
                          ? () => state.setSessions(draft.sessions + 1)
                          : null,
                      icon: const Icon(Icons.add_circle_outline),
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
                    Text('Focus concerns', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final concern in state.concernLabels.keys)
                          ChoiceChip(
                            label: Text(state.labelFor(concern)),
                            selected: draft.focus.contains(concern),
                            onSelected: (_) => state.toggleFocus(concern),
                          ),
                      ],
                    ),
                    for (final concern in draft.focus) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _noteFor(concern),
                        minLines: 1,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: '${state.labelFor(concern)} note',
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            state.setFocusNote(concern, value),
                      ),
                    ],
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
                    Text('Home regimen', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _regimenAm,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Morning (AM)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => state.setRegimen(am: value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _regimenPm,
                      minLines: 1,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Evening (PM)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => state.setRegimen(pm: value),
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
                    Text('Series treatment (optional)',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: currentService?.name,
                      decoration:
                          const InputDecoration(border: OutlineInputBorder()),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('None'),
                        ),
                        for (final service in state.activeServices)
                          DropdownMenuItem<String>(
                            value: service.name,
                            child: Text(
                              '${service.name} — ${_price(service.price)}'
                              '${service.unit == null ? '' : ' ${service.unit}'}',
                            ),
                          ),
                        if (currentService != null && !serviceOnMenu)
                          DropdownMenuItem<String>(
                            value: currentService.name,
                            child: Text(
                              '${currentService.name} — '
                              '${_price(currentService.price)}'
                              '${currentService.unit == null ? '' : ' ${currentService.unit}'}'
                              ' (not on your menu)',
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          state.setDraftService(null);
                          return;
                        }
                        for (final service in state.activeServices) {
                          if (service.name == value) {
                            state.setDraftService(PlanService(
                              name: service.name,
                              price: service.price,
                              unit: service.unit,
                            ));
                            return;
                          }
                        }
                      },
                    ),
                    if (state.activeServices.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Add your services in Setup to offer one here.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
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
                    Text('Retail products', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final product in state.planProducts)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(product.name),
                        secondary: Text(_price(product.price)),
                        value: draft.productIds.contains(product.id),
                        onChanged: (_) => state.toggleProduct(product.id),
                      ),
                    if (state.activeProducts.isEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        'These are starter products — add your own in Setup.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: theme.textTheme.titleMedium),
                        Text(
                          _price(_total(state.planProducts, draft.productIds)),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => _save(context),
              child: const Text('Save plan'),
            ),
            if (state.planMessage != null) ...[
              const SizedBox(height: 8),
              Text(state.planMessage!, style: theme.textTheme.bodySmall),
            ],
            if (state.sharedPlan != null) ...[
              const SizedBox(height: 16),
              _ClientPreviewCard(
                plan: state.sharedPlan!,
                labelOf: state.labelFor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    final state = widget.state;
    final ok = await state.savePlan();
    if (!context.mounted) return;
    final name =
        state.selectedDetail?.firstName ?? state.selectedSummary?.firstName ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Plan saved — $name will see it in her series timeline'
              : 'Could not save the plan.',
        ),
      ),
    );
  }
}

class _ClientPreviewCard extends StatelessWidget {
  const _ClientPreviewCard({required this.plan, required this.labelOf});

  final ClientPlan plan;
  final String Function(String) labelOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ExpansionTile(
        initiallyExpanded: true,
        title: Text('Client preview', style: theme.textTheme.titleMedium),
        children: [
          _row('Series', plan.seriesName),
          if (plan.service != null)
            _row(
              'Series treatment',
              '${plan.service!.name} — ${_price(plan.service!.price)}'
              '${plan.service!.unit == null ? '' : ' ${plan.service!.unit}'}',
            ),
          _row('Sessions', '${plan.sessions}'),
          for (final focus in plan.focus)
            _row(
              labelOf(focus.concern),
              focus.note.isEmpty ? 'No note' : focus.note,
            ),
          _row('AM', plan.regimenAm.isEmpty ? '—' : plan.regimenAm),
          _row('PM', plan.regimenPm.isEmpty ? '—' : plan.regimenPm),
          _row('Products', _productSummary()),
        ],
      ),
    );
  }

  static Widget _row(String label, String value) {
    return ListTile(
      dense: true,
      title: Text(label),
      subtitle: Text(value),
    );
  }

  String _productSummary() {
    if (plan.products.isEmpty) return 'None';
    final names = plan.products.map((product) => product.name).join(', ');
    final total =
        plan.products.fold<double>(0, (sum, product) => sum + product.price);
    return '$names · ${_price(total)}';
  }
}

String _price(double amount) => '\$${amount.toStringAsFixed(2)}';

double _total(List<Product> products, Set<String> selectedIds) => products
    .where((product) => selectedIds.contains(product.id))
    .fold(0, (sum, product) => sum + product.price);
