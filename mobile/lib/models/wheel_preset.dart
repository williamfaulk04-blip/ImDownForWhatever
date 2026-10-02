class WheelPresetCategory {
  const WheelPresetCategory(this.name, this.activities);

  final String name;
  final List<String> activities;
}

class WheelPreset {
  const WheelPreset({
    required this.name,
    required this.description,
    required this.categories,
  });

  final String name;
  final String description;
  final List<WheelPresetCategory> categories;
}

const wheelPresets = <WheelPreset>[
  WheelPreset(
    name: 'Food & drinks',
    description: 'Easy ideas for meals, snacks, and treats.',
    categories: [
      WheelPresetCategory('Eat out', ['Tacos', 'Pizza', 'Sushi', 'Burgers']),
      WheelPresetCategory('At home', [
        'Cook together',
        'Order takeout',
        'Try a new recipe',
      ]),
      WheelPresetCategory('Treats', ['Ice cream', 'Boba', 'Bakery']),
    ],
  ),
  WheelPreset(
    name: 'Game night',
    description: 'Mix of video games, board games, and party games.',
    categories: [
      WheelPresetCategory('Video games', [
        'Mario Kart',
        'Jackbox',
        'Co-op adventure',
      ]),
      WheelPresetCategory('Board games', ['Catan', 'Uno', 'Chess']),
      WheelPresetCategory('Party games', ['Charades', 'Trivia', 'Pictionary']),
    ],
  ),
  WheelPreset(
    name: 'Out & about',
    description: 'Fresh air, local spots, and things to do nearby.',
    categories: [
      WheelPresetCategory('Outdoors', ['Walk', 'Picnic', 'Hike']),
      WheelPresetCategory('Local spots', [
        'Coffee shop',
        'Bookstore',
        'Farmers market',
      ]),
      WheelPresetCategory('Events', ['Live music', 'Comedy show', 'Museum']),
    ],
  ),
];
