import 'combat.dart';
import 'grid_map.dart';
import 'pathing.dart';

class EnemyType {
  final String name;
  final String symbol;
  final String movement;
  final int hp;
  final int armor;
  final int speed;
  final int bounty;
  final int lives;
  final int regen;
  final EnemyType? splitInto;
  final int splitCount;
  int spawned = 0;
  int kills = 0;
  int leaks = 0;
  int damage = 0;
  EnemyType(List<String> fields, Map<String, EnemyType> known) : name = fields[1], symbol = fields[2], movement = fields[3],
      hp = int.parse(fields[4]), armor = int.parse(fields[5]), speed = int.parse(fields[6]), bounty = int.parse(fields[7]),
      lives = int.parse(fields[8]), regen = int.parse(fields[9]), splitInto = known[fields[10]], splitCount = int.parse(fields[11]);
}
class Group {
  final EnemyType kind;
  final int spawn;
  final int count;
  final int delay;
  final int interval;
  final int multiplier;
  Group(List<String> fields, Map<String, EnemyType> known) : kind = known[fields[1]]!, spawn = int.parse(fields[2]),
      count = int.parse(fields[3]), delay = int.parse(fields[4]), interval = int.parse(fields[5]), multiplier = int.parse(fields[6]);
  int spawnTick(int start, int index) => start + delay + index * interval;
}
class Wave {
  final int reward;
  final List<Group> groups = [];
  Wave(this.reward);
  int get enemyCount => groups.fold(0, (total, group) => total + group.count);
}
(List<EnemyType>, List<Wave>) parseWaves(List<String> lines) {
  final types = <String, EnemyType>{};
  final waves = <Wave>[];
  for (final line in lines) {
    final fields = line.split(' ');
    switch (fields[0]) {
      case 'enemy':
        final kind = EnemyType(fields, types);
        types[kind.name] = kind;
        break;
      case 'wave':
        waves.add(Wave(int.parse(fields[1])));
        break;
      case 'group':
        waves.last.groups.add(Group(fields, types));
        break;
    }
  }
  return (types.values.toList(), waves);
}
class Enemy {
  final int number;
  final EnemyType kind;
  final int multiplier;
  final int maxHP;
  int hp;
  final Effect slow = Effect();
  final Effect burn = Effect();
  bool alive = true;
  Point cell = (0, 0);
  Point nextCell = (0, 0);
  int progress = 0;
  Point point = (0, 0);
  Enemy(this.number, this.kind, this.multiplier) : maxHP = kind.hp * multiplier ~/ 100, hp = kind.hp * multiplier ~/ 100;
  bool get flying => kind.movement == 'air';
  Point get position => flying ? point :
      (100 * cell.$1 + (nextCell.$1 - cell.$1) * progress, 100 * cell.$2 + (nextCell.$2 - cell.$2) * progress);
  Point get occupiedCell => flying ? ((point.$1 + 50) ~/ 100, (point.$2 + 50) ~/ 100) : progress < 50 ? cell : nextCell;
  int remaining(DistanceField field) => flying ? integerSqrt(squaredDistance(point, cellCenter(field.exit))) :
      100 * field.at(nextCell) + 100 - progress;
  int get slowedSpeed => slow.active ? kind.speed * (100 - slow.strength) ~/ 100 : kind.speed;
  Enemy split(int number) {
    final child = Enemy(number, kind.splitInto!, multiplier);
    child.cell = cell;
    child.nextCell = nextCell;
    child.progress = progress;
    child.point = point;
    return child;
  }
}
