import 'dart:io';
import 'dart:math' as math;
import 'grid_map.dart';
import 'pathing.dart';
import 'towers.dart';
import 'enemies.dart';
import 'combat.dart';

const incomeFields = ['bounty', 'reward', 'interest', 'early', 'refund'];
const waveColumns = 'wave,start,end,status,spawned,peak,kills,leaks,lives_lost,bounty,reward,interest,gold,lives';
List<String> readLines(String name) => File('input/$name').readAsLinesSync();
void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
String oneDecimal(int numerator, int denominator) {
  if (denominator == 0) return '-';
  final rounded = (20 * numerator + denominator) ~/ (2 * denominator);
  return '${rounded ~/ 10}.${rounded % 10}';
}
String digit(int count) => count == 0 ? '.' : count <= 9 ? '$count' : '*';
List<String> ruled(List<List<String>> rows) => [
  '  ${List.generate(rows[0].length, (x) => '${x % 10}').join()}',
  for (var y = 0; y < rows.length; y++) '${y % 10} ${rows[y].join()}'
];
class Params {
  late final int gold;
  late final int lives;
  late final int interestRate;
  late final int interestCap;
  late final int sellRate;
  late final int start;
  late final int interval;
  late final int early;
  late final Set<int> snapshots;
  Params(List<String> lines) {
    final fields = lines.map((line) => line.split(' ')).toList();
    gold = int.parse(fields[0][1]);
    lives = int.parse(fields[1][1]);
    interestRate = int.parse(fields[2][1]);
    interestCap = int.parse(fields[2][2]);
    sellRate = int.parse(fields[3][1]);
    start = int.parse(fields[4][1]);
    interval = int.parse(fields[4][2]);
    early = int.parse(fields[5][1]);
    snapshots = fields[6].skip(1).map(int.parse).toSet();
  }
}
class Action {
  late final int tick;
  late final String command;
  late final List<String> arguments;
  Action(String line) {
    final fields = line.split(' ');
    tick = int.parse(fields[0]);
    command = fields[1];
    arguments = fields.sublist(2);
  }
}
class WaveRecord {
  final int number;
  final Wave plan;
  final int start;
  int end = 0;
  String status = '';
  final List<int> released;
  int spawned = 0;
  int peak = 0;
  int kills = 0;
  int leaks = 0;
  int livesLost = 0;
  int bounty = 0;
  int reward = 0;
  int interest = 0;
  int gold = 0;
  int lives = 0;
  final Map<int, int> towerDamage = {};
  WaveRecord(this.number, this.plan, this.start) : released = List.filled(plan.groups.length, 0);
  bool get allReleased => [for (var i = 0; i < released.length; i++) released[i] == plan.groups[i].count].every((value) => value);
  void close(String result, int tick, int finalGold, int finalLives) {
    status = result;
    end = tick;
    gold = finalGold;
    lives = finalLives;
  }
  String csvRow(int towerCount) => [number, start, end, status, spawned, peak, kills, leaks, livesLost, bounty,
    reward, interest, gold, lives, for (var number = 1; number <= towerCount; number++) towerDamage[number] ?? 0].join(',');
}
class Game {
  final GridMap grid;
  final Map<String, TowerType> towerTypes;
  final List<EnemyType> enemyTypes;
  final List<Wave> waves;
  final Params params;
  final Point exitCenter;
  int tick = 0;
  int gold;
  int lives;
  final List<Tower> towers = [];
  final List<Enemy> enemies = [];
  final List<Enemy> allEnemies = [];
  List<Projectile> projectiles = [];
  int projectileCount = 0;
  final List<WaveRecord> records = [];
  WaveRecord? active;
  int? nextStart;
  String? outcome;
  DistanceField field;
  final List<int> killCounts;
  final Map<String, int> income = {for (final name in incomeFields) name: 0};
  int spent = 0;
  int done = 0;
  int refused = 0;
  final List<String> events = [];
  final List<String> snapshots = [];
  Game(this.grid, List<TowerType> kinds, this.enemyTypes, this.waves, this.params) :
      towerTypes = {for (final kind in kinds) kind.name: kind}, exitCenter = cellCenter(grid.exit),
      gold = params.gold, lives = params.lives, nextStart = params.start,
      field = DistanceField(grid, {}), killCounts = List.filled(grid.width * grid.height, 0);
  void record(String body) => events.add('$tick $body');
  void run(List<Action> actions) {
    var index = 0;
    while (true) {
      tick++;
      while (index < actions.length && actions[index].tick == tick) { perform(actions[index++]); }
      spawnEnemies();
      moveEnemies();
      if (outcome != null) break;
      fireTowers();
      moveProjectiles();
      checkWaveEnd();
      if (params.snapshots.contains(tick)) snapshots.addAll(block('SNAPSHOT'));
      if (outcome != null) break;
    }
    snapshots.addAll(finalBlock());
  }
  List<Tower> get standingTowers => towers.where((tower) => tower.standing).toList();
  Set<Point> get towerCells => {for (final tower in standingTowers) tower.cell};
  Tower? towerAt(Point cell) {
    for (final tower in towers) { if (tower.standing && tower.cell == cell) return tower; }
    return null;
  }
  Tower? standingTower(String text) {
    final number = int.parse(text);
    return number >= 1 && number <= towers.length && towers[number - 1].standing ? towers[number - 1] : null;
  }
  List<Enemy> get groundEnemies => enemies.where((enemy) => !enemy.flying).toList();
  void perform(Action action) {
    final succeeded = switch (action.command) {
      'BUILD' => build(action.arguments), 'UPGRADE' => upgrade(action.arguments), 'SELL' => sell(action.arguments),
      'TARGET' => setTarget(action.arguments), _ => callWave()
    };
    if (succeeded) {
      done++;
    } else {
      refused++;
    }
  }
  String? buildRefusal(String name, Point cell) {
    final kind = towerTypes[name];
    if (kind == null) return 'type';
    if (!grid.inside(cell)) return 'bounds';
    if (!grid.buildable(cell)) return 'terrain';
    if (towerAt(cell) != null) return 'tower';
    if (gold < kind.levels[0].cost) return 'gold';
    final walkers = groundEnemies;
    if (walkers.any((enemy) => enemy.cell == cell || enemy.nextCell == cell)) return 'enemy';
    final trial = DistanceField(grid, towerCells..add(cell));
    if (grid.spawns.any((spawn) => trial.at(spawn) < 0) || walkers.any((enemy) => trial.at(enemy.nextCell) < 0)) return 'blocked';
    return null;
  }
  bool build(List<String> arguments) {
    final name = arguments[0];
    final cell = (int.parse(arguments[1]), int.parse(arguments[2]));
    final reason = buildRefusal(name, cell);
    if (reason != null) {
      record('BUILD_REFUSED $name ${arguments[1]} ${arguments[2]} $reason');
      return false;
    }
    final kind = towerTypes[name]!;
    final cost = kind.levels[0].cost;
    final tower = Tower(towers.length + 1, kind, cell, tick);
    towers.add(tower);
    gold -= cost;
    spent += cost;
    record('BUILD T${tower.number} $name ${cell.$1} ${cell.$2} cost $cost gold $gold');
    updateField();
    return true;
  }
  bool upgrade(List<String> arguments) {
    final tower = standingTower(arguments[0]);
    final String reason;
    if (tower == null) {
      reason = 'notower';
    } else if (tower.level == tower.kind.levels.length) {
      reason = 'maxlevel';
    } else if (gold < tower.kind.levels[tower.level].cost) {
      reason = 'gold';
    } else {
      final cost = tower.kind.levels[tower.level].cost;
      gold -= cost;
      spent += cost;
      tower.level++;
      tower.investment += cost;
      record('UPGRADE T${tower.number} level ${tower.level} cost $cost gold $gold');
      return true;
    }
    record('UPGRADE_REFUSED T${arguments[0]} $reason');
    return false;
  }
  bool sell(List<String> arguments) {
    final tower = standingTower(arguments[0]);
    if (tower == null) {
      record('SELL_REFUSED T${arguments[0]} notower');
      return false;
    }
    final rate = tick == tower.built ? 100 : params.sellRate;
    final refund = tower.investment * rate ~/ 100;
    tower.sold = tick;
    gold += refund;
    income['refund'] = income['refund']! + refund;
    record('SELL T${tower.number} refund $refund gold $gold');
    updateField();
    return true;
  }
  bool setTarget(List<String> arguments) {
    final tower = standingTower(arguments[0]);
    final String reason;
    if (tower == null) {
      reason = 'notower';
    } else if (!targetModes.contains(arguments[1])) {
      reason = 'mode';
    } else {
      tower.mode = arguments[1];
      record('TARGET T${tower.number} ${tower.mode}');
      return true;
    }
    record('TARGET_REFUSED T${arguments[0]} $reason');
    return false;
  }
  bool callWave() {
    if (active != null) {
      record('CALL_REFUSED active');
      return false;
    }
    final bonus = (nextStart! - tick) * params.early;
    gold += bonus;
    income['early'] = income['early']! + bonus;
    nextStart = tick;
    record('CALL ${records.length + 1} bonus $bonus gold $gold');
    return true;
  }
  void updateField() {
    final before = field;
    field = DistanceField(grid, towerCells);
    for (var i = 0; i < grid.spawns.length; i++) {
      final old = before.at(grid.spawns[i]);
      final current = field.at(grid.spawns[i]);
      if (old != current) record('REPATH ${i + 1} $old $current');
    }
  }
  void startWave() {
    final plan = waves[records.length];
    final wave = WaveRecord(records.length + 1, plan, tick);
    records.add(wave);
    active = wave;
    nextStart = null;
    record('WAVE_START ${wave.number} enemies ${plan.enemyCount}');
  }
  void addEnemy(Enemy enemy) {
    enemies.add(enemy);
    allEnemies.add(enemy);
    active!.spawned++;
    enemy.kind.spawned++;
  }
  void removeEnemy(Enemy enemy) {
    enemy.alive = false;
    enemies.remove(enemy);
  }
  void spawnEnemies() {
    if (tick == nextStart) startWave();
    final wave = active;
    if (wave == null) return;
    for (var i = 0; i < wave.plan.groups.length; i++) {
      final group = wave.plan.groups[i];
      final released = wave.released[i];
      if (released == group.count || group.spawnTick(wave.start, released) != tick) continue;
      wave.released[i]++;
      final spawn = grid.spawns[group.spawn - 1];
      final enemy = Enemy(allEnemies.length + 1, group.kind, group.multiplier);
      if (enemy.flying) {
        enemy.point = cellCenter(spawn);
      } else {
        enemy.cell = spawn;
        enemy.nextCell = field.nextCell(spawn);
      }
      addEnemy(enemy);
      record('SPAWN E${enemy.number} ${enemy.kind.name} ${group.spawn} hp ${enemy.hp}');
    }
    wave.peak = math.max(wave.peak, enemies.length);
  }
  void moveEnemies() {
    for (final enemy in List<Enemy>.of(enemies)) {
      moveEnemy(enemy);
      if (outcome != null) return;
    }
  }
  void moveEnemy(Enemy enemy) {
    if (enemy.burn.active) {
      final source = towers[enemy.burn.source! - 1];
      final damage = math.min(enemy.hp, enemy.burn.strength);
      enemy.hp -= damage;
      credit(source, enemy, damage);
      enemy.burn.advanceTime();
      if (enemy.hp == 0) {
        kill(enemy, source);
        return;
      }
    }
    enemy.hp = math.min(enemy.hp + enemy.kind.regen, enemy.maxHP);
    final speed = enemy.slowedSpeed;
    if (enemy.slow.active) enemy.slow.advanceTime();
    final bool arrived;
    if (enemy.flying) {
      final (point, reached) = advance(enemy.point, exitCenter, speed);
      enemy.point = point;
      arrived = reached;
    } else {
      arrived = walk(enemy, speed);
    }
    if (arrived) leak(enemy);
  }
  bool walk(Enemy enemy, int speed) {
    if (grid.isWater(enemy.occupiedCell)) speed ~/= 2;
    while (speed > 0) {
      final rest = 100 - enemy.progress;
      if (speed < rest) {
        enemy.progress += speed;
        speed = 0;
      } else {
        speed -= rest;
        enemy.cell = enemy.nextCell;
        enemy.progress = 0;
        if (enemy.cell == grid.exit) return true;
        enemy.nextCell = field.nextCell(enemy.cell);
      }
    }
    return false;
  }
  void leak(Enemy enemy) {
    removeEnemy(enemy);
    final lost = math.min(lives, enemy.kind.lives);
    lives -= lost;
    final wave = active!;
    wave.leaks++;
    wave.livesLost += lost;
    enemy.kind.leaks++;
    record('LEAK E${enemy.number} ${enemy.kind.name} lives $lives');
    if (lives == 0) {
      record('DEFEAT');
      outcome = 'defeat';
      wave.close('lost', tick, gold, lives);
      active = null;
    }
  }
  void fireTowers() {
    for (final tower in standingTowers) {
      if (tick < tower.ready) continue;
      final target = tower.selectTarget(enemies, field);
      if (target != null) fire(tower, target);
    }
  }
  void fire(Tower tower, Enemy target) {
    final stats = tower.stats;
    projectiles.add(Projectile(++projectileCount, tower.number, target.number, tower.center, target.position,
        tower.kind.targets, stats.power, stats.shotSpeed, stats.splash, stats.slowRate, stats.slowTime, stats.burnAmount, stats.burnTime));
    tower.shots++;
    tower.ready = tick + stats.interval;
    record('SHOT T${tower.number} E${target.number}');
  }
  void moveProjectiles() {
    final flying = <Projectile>[];
    for (final projectile in projectiles) {
      final target = allEnemies[projectile.target - 1];
      if (target.alive) projectile.aim = target.position;
      if (projectile.fly()) {
        impact(projectile);
      } else {
        flying.add(projectile);
      }
    }
    projectiles = flying;
  }
  void impact(Projectile projectile) {
    final tower = towers[projectile.tower - 1];
    final target = allEnemies[projectile.target - 1];
    final victims = projectile.splash == 0 ? <Enemy>[if (target.alive) target] : [
      for (final enemy in enemies)
        if (canAim(projectile.targets, enemy) && squaredDistance(enemy.position, projectile.aim) <= projectile.splash * projectile.splash) enemy
    ];
    if (victims.isEmpty) tower.fizzles++;
    for (final enemy in victims) {
      tower.hits++;
      final damage = damageDealt(enemy.hp, projectile.power, enemy.kind.armor);
      enemy.hp -= damage;
      credit(tower, enemy, damage);
      if (enemy.hp == 0) {
        kill(enemy, tower);
        continue;
      }
      if (projectile.slowRate > 0) enemy.slow.receive(projectile.slowRate, projectile.slowTime);
      if (projectile.burnAmount > 0) enemy.burn.receive(projectile.burnAmount, projectile.burnTime, tower.number);
    }
  }
  void credit(Tower tower, Enemy enemy, int damage) {
    tower.damage += damage;
    enemy.kind.damage += damage;
    active!.towerDamage.update(tower.number, (value) => value + damage, ifAbsent: () => damage);
  }
  void kill(Enemy enemy, Tower tower) {
    removeEnemy(enemy);
    final cell = enemy.occupiedCell;
    killCounts[cell.$2 * grid.width + cell.$1]++;
    final wave = active!;
    final bounty = enemy.kind.bounty;
    tower.kills++;
    wave.kills++;
    enemy.kind.kills++;
    gold += bounty;
    wave.bounty += bounty;
    income['bounty'] = income['bounty']! + bounty;
    record('KILL E${enemy.number} ${enemy.kind.name} T${tower.number} bounty $bounty gold $gold');
    for (var i = 0; i < enemy.kind.splitCount; i++) {
      final child = enemy.split(allEnemies.length + 1);
      addEnemy(child);
      record('SPAWN E${child.number} ${child.kind.name} E${enemy.number} hp ${child.hp}');
    }
  }
  void checkWaveEnd() {
    final wave = active;
    if (wave == null || enemies.isNotEmpty || !wave.allReleased) return;
    final reward = wave.plan.reward;
    gold += reward;
    final interest = math.min(params.interestCap, gold * params.interestRate ~/ 100);
    gold += interest;
    wave.reward = reward;
    wave.interest = interest;
    income['reward'] = income['reward']! + reward;
    income['interest'] = income['interest']! + interest;
    active = null;
    record('WAVE_END ${wave.number} reward $reward interest $interest gold $gold');
    if (wave.number == waves.length) {
      record('VICTORY');
      outcome = 'victory';
    } else {
      nextStart = tick + params.interval;
    }
    wave.close('cleared', tick, gold, lives);
  }
  List<List<String>> mapPicture() {
    final rows = grid.rows.map((row) => row.split('')).toList();
    for (final spawn in grid.spawns) {
      for (final cell in field.path(spawn)) {
        if (['.', '~'].contains(grid.terrain(cell))) rows[cell.$2][cell.$1] = '+';
      }
    }
    for (final tower in standingTowers) { rows[tower.cell.$2][tower.cell.$1] = tower.kind.symbol; }
    final occupants = <Point, List<Enemy>>{};
    for (final enemy in enemies) { occupants.putIfAbsent(enemy.occupiedCell, () => []).add(enemy); }
    for (final entry in occupants.entries) { rows[entry.key.$2][entry.key.$1] = entry.value.length == 1 ? entry.value[0].kind.symbol : '*'; }
    return rows;
  }
  List<List<String>> flowPicture() => [for (var y = 0; y < grid.height; y++) [
    for (var x = 0; x < grid.width; x++) flowSymbol((x, y))
  ]];
  String flowSymbol(Point cell) {
    final terrain = grid.terrain(cell);
    final tower = towerAt(cell);
    if (terrain == '#' || terrain == 'E') return terrain;
    if (tower != null) return tower.kind.symbol;
    return field.at(cell) < 0 ? '?' : '^>v<'[field.direction(cell)];
  }
  List<List<String>> coveragePicture() {
    final standing = standingTowers;
    return [for (var y = 0; y < grid.height; y++) [for (var x = 0; x < grid.width; x++)
      grid.isRock((x, y)) ? '#' : towerAt((x, y))?.kind.symbol ?? digit(standing.where((tower) => tower.inRange(cellCenter((x, y)))).length)
    ]];
  }
  List<List<String>> killsPicture() => [for (var y = 0; y < grid.height; y++) [for (var x = 0; x < grid.width; x++)
    killCounts[y * grid.width + x] > 0 ? digit(killCounts[y * grid.width + x]) : grid.isRock((x, y)) ? '#' : '.'
  ]];
  List<String> block(String label) {
    final next = active == null && outcome == null ? '$nextStart' : '-';
    final lines = <String>['$label $tick wave ${records.length} next $next gold $gold lives $lives', ...ruled(mapPicture())];
    for (var i = 0; i < grid.spawns.length; i++) { lines.add('PATH ${i + 1} length ${field.at(grid.spawns[i])}'); }
    for (final tower in standingTowers) {
      lines.add('T${tower.number} ${tower.kind.name} ${tower.cell.$1} ${tower.cell.$2} level ${tower.level} mode ${tower.mode} ready ${tower.ready}');
    }
    for (final enemy in enemies) {
      final point = enemy.position;
      lines.add('E${enemy.number} ${enemy.kind.name} ${point.$1} ${point.$2} hp ${enemy.hp}/${enemy.maxHP} slow ${enemy.slow.strength} ${enemy.slow.remaining} burn ${enemy.burn.strength} ${enemy.burn.remaining}');
    }
    for (final projectile in projectiles) { lines.add('P${projectile.number} T${projectile.tower} E${projectile.target} ${projectile.position.$1} ${projectile.position.$2}'); }
    return lines;
  }
  List<String> finalBlock() => [...block('FINAL'), 'FLOW', ...ruled(flowPicture()), 'COVERAGE', ...ruled(coveragePicture()), 'KILLS', ...ruled(killsPicture())];
  List<String> waveLines() => [waveColumns + towers.map((tower) => ',T${tower.number}').join(), ...records.map((wave) => wave.csvRow(towers.length))];
  String mvpLine() {
    Tower? best;
    for (final tower in towers) { if (best == null || tower.damage > best.damage) best = tower; }
    return best == null ? 'mvp -' : 'mvp T${best.number} damage ${best.damage}';
  }
  String towerLine(Tower tower, int totalDamage) {
    final state = tower.standing ? 'active' : 'sold ${tower.sold}';
    return 'TOWER T${tower.number} ${tower.kind.name} ${tower.cell.$1} ${tower.cell.$2} level ${tower.level} mode ${tower.mode} $state shots ${tower.shots} hits ${tower.hits} fizzles ${tower.fizzles} kills ${tower.kills} damage ${tower.damage} per_shot ${oneDecimal(tower.damage, tower.shots)} share ${oneDecimal(100 * tower.damage, totalDamage)} invested ${tower.investment}';
  }
  List<String> summaryLines(int actionCount) {
    final cleared = records.where((wave) => wave.status == 'cleared').toList();
    final perfect = cleared.where((wave) => wave.leaks == 0).length;
    final spawned = enemyTypes.fold(0, (total, kind) => total + kind.spawned);
    final killed = enemyTypes.fold(0, (total, kind) => total + kind.kills);
    final leaked = enemyTypes.fold(0, (total, kind) => total + kind.leaks);
    final totalDamage = towers.fold(0, (total, tower) => total + tower.damage);
    final score = 10 * killed + 100 * lives + 50 * perfect + gold;
    return [
      'outcome $outcome', 'ticks $tick', 'waves ${cleared.length}/${waves.length} perfect $perfect', 'lives $lives/${params.lives}', 'gold $gold',
      'enemies spawned $spawned killed $killed leaked $leaked', 'income ${incomeFields.map((name) => '$name ${income[name]}').join(' ')}',
      'spent $spent', 'damage $totalDamage', 'actions total $actionCount done $done refused $refused unused ${actionCount - done - refused}',
      'score $score', mvpLine(),
      for (final kind in enemyTypes) 'ENEMY ${kind.name} spawned ${kind.spawned} killed ${kind.kills} leaked ${kind.leaks} damage ${kind.damage}',
      for (final tower in towers) towerLine(tower, totalDamage)
    ];
  }
}
void main() {
  final grid = readMap();
  final towerTypes = parseTowerTypes(readLines('towers.txt'));
  final (enemyTypes, waves) = parseWaves(readLines('waves.txt'));
  final actions = readLines('actions.txt').map(Action.new).toList();
  final game = Game(grid, towerTypes, enemyTypes, waves, Params(readLines('params.txt')));
  game.run(actions);
  Directory('output').createSync(recursive: true);
  writeLines('events.txt', game.events);
  writeLines('waves.csv', game.waveLines());
  writeLines('snapshots.txt', game.snapshots);
  writeLines('summary.txt', game.summaryLines(actions.length));
}
