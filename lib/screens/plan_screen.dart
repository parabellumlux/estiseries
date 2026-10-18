import 'package:flutter/material.dart';

import '../models.dart';
import '../state/app_state.dart';
import 'screen_scaffold.dart';

/// Plan builder: template, sessions, focus notes, regimen, products, share.
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

  @override
  void initState() {
    super.initState();
    _regimenAm = TextEditingController(text: widget.state.draft.regimenAm);
    _regimenPm = TextEditingController(text: widget.state.draft.regimenPm);
  }

  @override
  void dispose() {
    _regimenAm.dispose();
    _regimenPm.dispose();
    for (final controller in _noteControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _noteFor(String concern) =>
      _noteControllers.putIfAbsent(
        concern,
        () => TextEditingController(text: widget.state.draft.notes[concern]),
      );

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final draft = state.draft;
    final theme = Theme.of(context);
    final template =
        state.templates.firstWhere((t) => t.id == draft.templateId);

    return ScreenScaffold(
      title: 'Plan builder',
      child: SingleChildScrollView(
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
                    Text('Retail products', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final product in state.products)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(product.name),
                        secondary: Text(_price(product.price)),
                        value: draft.productIds.contains(product.id),
                        onChanged: (_) => state.toggleProduct(product.id),
                      ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total', style: theme.textTheme.titleMedium),
                        Text(
                          _price(_total(state.products, draft.productIds)),
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
              onPressed: () => _share(context),
              child: const Text('Share plan to client view'),
            ),
            if (state.sharedPlan != null) ...[
              const SizedBox(height: 16),
              _ClientPreviewCard(
                plan: state.sharedPlan!,
                products: state.products,
                labelOf: state.labelFor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _share(BuildContext context) {
    final state = widget.state;
    state.sharePlan();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Plan shared — ${state.client.firstName} will see it in her '
          'series timeline',
        ),
      ),
    );
  }
}

class _ClientPreviewCard extends StatelessWidget {
  const _ClientPreviewCard({
    required this.plan,
    required this.products,
    required this.labelOf,
  });

  final ClientPlan plan;
  final List<Product> products;
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
    final selected =
        products.where((product) => plan.productIds.contains(product.id));
    if (selected.isEmpty) return 'None';
    final names = selected.map((product) => product.name).join(', ');
    final total =
        selected.fold<double>(0, (sum, product) => sum + product.price);
    return '$names · ${_price(total)}';
  }
}

String _price(double amount) => '\$${amount.toStringAsFixed(2)}';

double _total(List<Product> products, Set<String> selectedIds) => products
    .where((product) => selectedIds.contains(product.id))
    .fold(0, (sum, product) => sum + product.price);
