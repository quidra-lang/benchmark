import 'combat.dart';

class Point {
  final int x;
  final int y;
  const Point(this.x, this.y);
  @override
  bool operator ==(Object other) => other is Point && x == other.x && y == other.y;
  @override
  int get hashCode => Object.hash(x, y);
}

class MonsterType {
  final int index;
  final String name;
  final String symbol;
  final int minDepth;
  final int maxDepth;
  final int weight;
  final Dice hp;
  final int toHit;
  final int defense;
  final Dice damage;
  final int speed;
  final int xp;
  final bool erratic;
  final bool stationary;
  final bool regenerates;
  final bool poisonous;
  MonsterType(List<String> tokens, this.index)
      : name = tokens[0], symbol = tokens[1], minDepth = int.parse(tokens[2]), maxDepth = int.parse(tokens[3]),
        weight = int.parse(tokens[4]), hp = parseDice(tokens[5]), toHit = int.parse(tokens[6]), defense = int.parse(tokens[7]),
        damage = parseDice(tokens[8]), speed = int.parse(tokens[9]), xp = int.parse(tokens[10]),
        erratic = tokens[11].contains('E'), stationary = tokens[11].contains('S'), regenerates = tokens[11].contains('R'), poisonous = tokens[11].contains('P');
}

class ItemType {
  final String category;
  final String name;
  final int minDepth;
  final int maxDepth;
  final int weight;
  Dice? dice;
  var toHit = 0, armor = 0, poisonTurns = 0, nutrition = 0;
  var effect = '';
  ItemType(this.category, this.name, [this.minDepth = 0, this.maxDepth = 0, this.weight = 0]);
}

ItemType parseItemType(List<String> tokens) {
  final kind = ItemType(tokens[0], tokens[1], int.parse(tokens[2]), int.parse(tokens[3]), int.parse(tokens[4]));
  final args = tokens.sublist(5);
  switch (kind.category) {
    case 'weapon':
      kind.dice = parseDice(args[0]);
      kind.toHit = int.parse(args[1]);
    case 'armor':
      kind.armor = int.parse(args[0]);
    case 'potion':
      kind.effect = args[0];
      if (kind.effect == 'heal') {
        kind.dice = parseDice(args[1]);
      } else if (kind.effect == 'poison') {
        kind.poisonTurns = int.parse(args[1]);
      }
    case 'scroll':
      kind.effect = args[0];
    case 'food':
      kind.nutrition = int.parse(args[0]);
    case 'gold':
      kind.dice = parseDice(args[0]);
  }
  return kind;
}

class Monster {
  final int id;
  final MonsterType kind;
  Point position;
  int hp;
  final int maxHP;
  bool asleep;
  var energy = 0;
  var wasVisible = false;
  Monster(this.id, this.kind, this.position, this.hp, this.asleep) : maxHP = hp;
}

class Item {
  final ItemType kind;
  final Point position;
  final int amount;
  var bonus = 0;
  Item(this.kind, this.position, [this.amount = 0]);
  String get symbol => switch (kind.category) {'weapon' => ')', 'armor' => '[', 'potion' => '!', 'scroll' => '?', 'food' => '%', 'gold' => r'$', 'amulet' => '"', _ => throw StateError('Unknown item class')};
  String get displayName {
    final name = kind.name.replaceAll('_', ' ');
    if (kind.category == 'weapon' || kind.category == 'armor') {
      return '+$bonus $name';
    }
    return kind.category == 'gold' ? '$amount gold' : name;
  }
  String get referenceName => kind.category == 'gold' ? displayName : 'the $displayName';
}
