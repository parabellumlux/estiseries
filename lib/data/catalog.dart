import '../models.dart';

/// Built-in Plan Builder catalog: concern labels, retail products, and
/// series templates. These are generic product data (not client data);
/// everything about a specific client comes from the backend.
const Map<String, String> kConcernLabels = {
  'wrinkle': 'Wrinkles',
  'pore': 'Pores',
  'texture': 'Texture',
  'acne': 'Acne',
  'oiliness': 'Oiliness',
  'radiance': 'Radiance',
  'eyeBag': 'Eye bags',
  'ageSpot': 'Age spots',
  'darkCircle': 'Dark circles',
  'droopyUpperEyelid': 'Droopy upper eyelids',
  'droopyLowerEyelid': 'Droopy lower eyelids',
  'firmness': 'Firmness',
  'moisture': 'Moisture',
  'redness': 'Redness',
  'tearTrough': 'Tear trough',
};

const List<Product> kProducts = [
  Product(id: 'p1', name: 'Gentle Renewal Cleanser', price: 38),
  Product(id: 'p2', name: 'Hydration Boost Serum', price: 64),
  Product(id: 'p3', name: 'Calm Moisture Cream', price: 52),
  Product(id: 'p4', name: 'Mineral SPF 50', price: 34),
];

const List<SeriesTemplate> kSeriesTemplates = [
  SeriesTemplate(
    id: 't1',
    name: 'Calm + Hydrate Renewal Series',
    description:
        'A six-session series for dry, reactive skin: hydration first, '
        'then calm, then glow.',
    sessions: 6,
    defaultFocus: ['moisture', 'redness', 'radiance'],
  ),
  SeriesTemplate(
    id: 't2',
    name: 'Clarifying Series',
    description:
        'A four-session series focused on breakouts, oil balance, and texture.',
    sessions: 4,
    defaultFocus: ['acne', 'oiliness', 'texture'],
  ),
  SeriesTemplate(
    id: 't3',
    name: 'Glow Facial Series',
    description:
        'A three-session refresh for dull skin ahead of an event or season '
        'change.',
    sessions: 3,
    defaultFocus: ['radiance', 'texture', 'darkCircle'],
  ),
  SeriesTemplate(
    id: 't4',
    name: 'Custom Series',
    description: "A series built from scratch around this client's scan.",
    sessions: 6,
    defaultFocus: [],
  ),
];

SeriesTemplate templateById(String id) => kSeriesTemplates.firstWhere(
      (template) => template.id == id,
      orElse: () => kSeriesTemplates.first,
    );

SeriesTemplate? templateByName(String name) {
  for (final template in kSeriesTemplates) {
    if (template.name == name) return template;
  }
  return null;
}
