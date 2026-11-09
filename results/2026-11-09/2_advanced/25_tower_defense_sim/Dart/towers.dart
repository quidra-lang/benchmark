import 'grid_map.dart';
import 'pathing.dart';
import 'enemies.dart';
import 'combat.dart';

const targetModes = ['FIRST', 'LAST', 'STRONGEST', 'WEAKEST', 'CLOSEST'];
class Level {
  final int cost;
  final int range;
  final int power;
  final int interval;
  final int shotSpeed;
  final int splash;
  final int slowRate;
  final int slowTime;
  final int burnAmount;
  final int burnTime;
  Level(List<String> fields) : cost = int.parse(fields[1]), range = int.parse(fields[2]),
      power = int.parse(fields[3]), interval = int.parse(fields[4]), shotSpeed = int.parse(fields[5]),
      splash = int.parse(fields[6]), slowRate = int.parse(fields[7]), slowTime = int.parse(fields[8]),
      burnAmount = int.parse(fields[9]), burnTime = int.parse(fields[10]);
}
class TowerType {
  final String name;
  final String symbol;
  final String targets;
  final List<Level> levels;
  TowerType(this.name, this.symbol, this.targets, this.levels);
}
List<TowerType> parseTowerTypes(List<String> lines) {
  final types = <TowerType>[];
  var index = 0;
  while (index < lines.length) {
    final fields = lines[index].split(' ');
    final count = int.parse(fields[4]);
    final levels = [for (var i = 0; i < count; i++) Level(lines[index + 1 + i].split(' '))];
    types.add(TowerType(fields[1], fields[2], fields[3], levels));
    index += count + 1;
  }
  return types;
}
bool canAim(String targets, Enemy enemy) => targets == 'both' || targets == enemy.kind.movement;
class Tower {
  final int number;
  final TowerType kind;
  final Point cell;
  int level = 1;
  String mode = 'FIRST';
  int ready;
  int investment;
  final int built;
  int? sold;
  int shots = 0;
  int hits = 0;
  int fizzles = 0;
  int kills = 0;
  int damage = 0;
  Tower(this.number, this.kind, this.cell, this.built) : ready = built, investment = kind.levels[0].cost;
  Level get stats => kind.levels[level - 1];
  Point get center => cellCenter(cell);
  bool get standing => sold == null;
  bool inRange(Point point) => squaredDistance(center, point) <= stats.range * stats.range;
  int targetKey(Enemy enemy, DistanceField field) => switch (mode) {
    'FIRST' => enemy.remaining(field), 'LAST' => -enemy.remaining(field),
    'STRONGEST' => -enemy.hp, 'WEAKEST' => enemy.hp, _ => squaredDistance(center, enemy.position)
  };
  Enemy? selectTarget(List<Enemy> enemies, DistanceField field) {
    Enemy? best;
    var bestKey = 0;
    for (final enemy in enemies) {
      if (!canAim(kind.targets, enemy) || !inRange(enemy.position)) continue;
      final key = targetKey(enemy, field);
      if (best == null || key < bestKey) {
        best = enemy;
        bestKey = key;
      }
    }
    return best;
  }
}
