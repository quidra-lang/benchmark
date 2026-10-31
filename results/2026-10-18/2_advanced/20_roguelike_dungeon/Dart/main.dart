import 'dart:io';
import 'dart:math' as math;
import 'minstd.dart';
import 'combat.dart';
import 'entities.dart';
import 'dungeon_gen.dart';
import 'fov.dart';

List<List<String>> readRows(String name) => File('input/$name').readAsLinesSync().map((line) => line.split(' ')).toList();
String dec1(int a, int b) {
  if (b == 0) {
    return '-';
  }
  final z = (20 * a + b) ~/ (2 * b);
  return '${z ~/ 10}.${z % 10}';
}
(int, int) exploration(Level level) {
  var explored = 0, total = 0;
  for (var y = 0; y < level.height; y++) {
    for (var x = 0; x < level.width; x++) {
      if (level.terrain[y][x] != ' ') {
        total++;
        if (level.memory[y][x] != ' ') {
          explored++;
        }
      }
    }
  }
  return (explored, total);
}

class Config {
  late final int generationSeed, gameSeed, width, height, minSize, maxSplit, roomMin, roomMax, levels;
  late final int monsterBase, monsterStep, itemBase, itemStep, sleepChance, wakeChance, fovRadius;
  late final int maxHP, regenInterval, foodStart, foodMax, foodHungry, foodWeak, packLimit;
  late final Dice hitDie;
  late final List<String> startItems;
  late final List<int> xpLevels;
  late final Set<int> checkpoints;
  Config(List<List<String>> rows) {
    final values = {for (final row in rows) row.first: row.sublist(1)};
    int value(String key, [int position = 0]) => int.parse(values[key]![position]);
    generationSeed = value('seed');
    gameSeed = value('seed', 1);
    width = value('map');
    height = value('map', 1);
    minSize = value('bsp');
    maxSplit = value('bsp', 1);
    roomMin = value('room');
    roomMax = value('room', 1);
    levels = value('levels');
    monsterBase = value('monsters');
    monsterStep = value('monsters', 1);
    itemBase = value('items');
    itemStep = value('items', 1);
    sleepChance = value('sleep');
    wakeChance = value('sleep', 1);
    fovRadius = value('fov');
    maxHP = value('player');
    regenInterval = value('player', 1);
    hitDie = parseDice(values['hitdie']!.first);
    foodStart = value('food');
    foodMax = value('food', 1);
    foodHungry = value('food', 2);
    foodWeak = value('food', 3);
    packLimit = value('pack');
    startItems = values['start']!;
    xpLevels = values['xp']!.map(int.parse).toList();
    checkpoints = values['checkpoints']!.map(int.parse).toSet();
  }
}

typedef Command = (String, String);
List<Command> expandCommands(List<List<String>> rows) {
  final commands = <Command>[];
  for (final tokens in rows) {
    final name = tokens.first;
    var argument = '';
    var count = 1;
    if (name == 'wait') {
      if (tokens.length == 2) {
        count = int.parse(tokens[1]);
      }
    } else {
      if (tokens.length > 1) {
        argument = tokens[1];
      }
      if (tokens.length == 3) {
        count = int.parse(tokens[2]);
      }
    }
    for (var i = 0; i < count; i++) {
      commands.add((name, argument));
    }
  }
  return commands;
}

class Player {
  Point position;
  var depth = 1, level = 1, xp = 0, gold = 0, poison = 0;
  int hp;
  int maxHP;
  int satiation;
  final pack = <Item>[];
  Item? weapon;
  Item? armor;
  Player(Config config, this.position) : hp = config.maxHP, maxHP = config.maxHP, satiation = config.foodStart;
  int get defense => armor == null ? 10 : 10 + armor!.kind.armor + armor!.bonus;
}

class AttackStats {
  var count = 0, hits = 0, criticals = 0, damage = 0;
  void record(String outcome, int dealt) {
    count++;
    if (outcome != 'miss') {
      hits++;
      damage += dealt;
    }
    if (outcome == 'critical') {
      criticals++;
    }
  }
  String line(String label) => '$label $count hits $hits criticals $criticals damage $damage accuracy ${dec1(100 * hits, count)}';
}

class Game {
  final Config config;
  final List<MonsterType> monsterTypes;
  final List<ItemType> itemTypes;
  final List<Command> commands;
  final Minstd generationRng;
  final Minstd rng;
  final levels = <Level>[];
  late final Player player;
  var turn = 1;
  final messages = <String>[];
  final mapLines = <String>[];
  late List<List<bool>> visible;
  late List<List<int>> distance;
  var result = '', cause = '';
  var succeeded = 0, failed = 0, unused = 0, moves = 0;
  final playerAttacks = AttackStats(), monsterAttacks = AttackStats();
  var poisonDamage = 0, starvationDamage = 0;
  final usage = {'picked': 0, 'quaffed': 0, 'read': 0, 'eaten': 0, 'wielded': 0, 'worn': 0};
  final List<int> kills;
  Game(this.config, this.monsterTypes, this.itemTypes, this.commands)
      : generationRng = Minstd(config.generationSeed), rng = Minstd(config.gameSeed), kills = List.filled(monsterTypes.length, 0) {
    buildLevels();
    player = Player(config, levels.first.arrival);
    final byName = {for (final kind in itemTypes) kind.name: kind};
    for (final name in config.startItems) {
      final item = Item(byName[name]!, player.position);
      player.pack.add(item);
      if (item.kind.category == 'weapon' && player.weapon == null) {
        player.weapon = item;
      }
      if (item.kind.category == 'armor' && player.armor == null) {
        player.armor = item;
      }
    }
  }

  void buildLevels() {
    final generator = LevelGenerator(generationRng, config.minSize, config.maxSplit, config.roomMin, config.roomMax);
    for (var depth = 1; depth <= config.levels; depth++) {
      final level = generator.generate(depth, config.width, config.height);
      if (depth < config.levels) {
        level.terrain[level.target.y][level.target.x] = '>';
      } else {
        level.items.add(Item(ItemType('amulet', 'amulet'), level.target));
      }
      placeMonsters(level);
      placeItems(level);
      levels.add(level);
    }
  }

  void placeMonsters(Level level) {
    final candidates = monsterTypes.where((kind) => kind.minDepth <= level.depth && level.depth <= kind.maxDepth).toList();
    final weights = candidates.map((kind) => kind.weight).toList();
    final count = config.monsterBase + config.monsterStep * (level.depth - 1);
    for (var id = 1; id <= count; id++) {
      final kind = candidates[generationRng.select(weights)];
      late Point point;
      while (true) {
        final (room, drawn) = level.drawRoomCell(generationRng);
        if (room != level.arrivalRoom && level.terrain[drawn.y][drawn.x] == '.' && level.monsterAt(drawn.x, drawn.y) == null) {
          point = drawn;
          break;
        }
      }
      final hp = kind.hp.roll(generationRng);
      final asleep = generationRng.rnd(100) < config.sleepChance;
      level.monsters.add(Monster(id, kind, point, hp, asleep));
    }
    level.monstersCreated = count;
  }

  void placeItems(Level level) {
    final candidates = itemTypes.where((kind) => kind.minDepth <= level.depth && level.depth <= kind.maxDepth).toList();
    final weights = candidates.map((kind) => kind.weight).toList();
    final count = config.itemBase + config.itemStep * (level.depth - 1);
    for (var i = 0; i < count; i++) {
      final kind = candidates[generationRng.select(weights)];
      late Point point;
      while (true) {
        final (_, drawn) = level.drawRoomCell(generationRng);
        if (level.terrain[drawn.y][drawn.x] == '.' && level.itemAt(drawn.x, drawn.y) == null) {
          point = drawn;
          break;
        }
      }
      final amount = kind.category == 'gold' ? kind.dice!.roll(generationRng) : 0;
      level.items.add(Item(kind, point, amount));
    }
    level.itemsPlaced = level.items.length;
  }

  Level get currentLevel => levels[player.depth - 1];
  void say(String text) => messages.add('${turn.toString().padLeft(4, '0')} $text');
  String get hungerState {
    if (player.satiation > config.foodHungry) {
      return 'normal';
    }
    if (player.satiation > config.foodWeak) {
      return 'hungry';
    }
    return player.satiation > 0 ? 'weak' : 'starving';
  }
  void finish(String outcome, String reason) {
    result = outcome;
    cause = reason;
  }
  void die(String reason) {
    say('You die.');
    finish('died', reason);
  }

  void updateView() {
    final level = currentLevel;
    visible = fieldOfView(level, player.position.x, player.position.y, config.fovRadius);
    for (var y = 0; y < level.height; y++) {
      for (var x = 0; x < level.width; x++) {
        if (visible[y][x]) {
          level.memory[y][x] = level.itemAt(x, y)?.symbol ?? level.terrain[y][x];
        }
      }
    }
    for (final monster in level.monsters) {
      final seen = visible[monster.position.y][monster.position.x];
      if (seen && !monster.wasVisible) {
        say('You see the ${monster.kind.name}.');
      }
      monster.wasVisible = seen;
    }
  }

  void run() {
    updateView();
    for (final command in commands) {
      if (result.isNotEmpty) {
        unused++;
      } else if (!execute(command)) {
        failed++;
      } else {
        succeeded++;
        if (result.isEmpty) {
          advanceTurn();
        }
      }
    }
    if (result.isEmpty) {
      finish('alive', 'commands_exhausted');
    }
  }

  void advanceTurn() {
    updateView();
    monstersAct();
    if (result.isNotEmpty) {
      return;
    }
    endTurn();
    if (result.isNotEmpty) {
      return;
    }
    if (config.checkpoints.contains(turn)) {
      writeCheckpoint();
    }
    turn++;
  }

  bool execute(Command command) {
    final (name, argument) = command;
    switch (name) {
      case 'move':
        final step = directions[directionNames.indexOf(argument)];
        return move(step.x, step.y);
      case 'wait':
        return true;
      case 'pickup':
        return pickup();
      case 'descend':
        return descend();
      default:
        return useItem(name, int.parse(argument));
    }
  }

  bool move(int dx, int dy) {
    final level = currentLevel;
    final x = player.position.x + dx, y = player.position.y + dy;
    if (!passable(level, x, y)) {
      say('You bump into a wall.');
      return false;
    }
    if (!canMove(level, player.position.x, player.position.y, dx, dy)) {
      say('You cannot move diagonally through a door.');
      return false;
    }
    final monster = level.monsterAt(x, y);
    if (monster != null) {
      playerAttack(level, monster);
      return true;
    }
    player.position = Point(x, y);
    moves++;
    final item = level.itemAt(x, y);
    if (item != null) {
      say('You see ${item.referenceName} here.');
    } else if (level.terrain[y][x] == '>') {
      say('There is a staircase down here.');
    }
    return true;
  }

  bool pickup() {
    final level = currentLevel;
    final item = level.itemAt(player.position.x, player.position.y);
    if (item == null) {
      say('There is nothing here.');
      return false;
    }
    if (item.kind.category == 'gold') {
      player.gold += item.amount;
      say('You pick up ${item.displayName}.');
    } else if (item.kind.category == 'amulet') {
      say('You pick up the amulet.');
      say('You win!');
      finish('won', 'amulet');
    } else if (player.pack.length >= config.packLimit) {
      say('Your pack is full.');
      return false;
    } else {
      player.pack.add(item);
      say('You pick up the ${item.displayName} (${player.pack.length}).');
    }
    level.items.remove(item);
    level.picked++;
    usage['picked'] = usage['picked']! + 1;
    return true;
  }

  bool descend() {
    if (currentLevel.terrain[player.position.y][player.position.x] != '>') {
      say('There are no stairs here.');
      return false;
    }
    player.depth++;
    player.position = currentLevel.arrival;
    say('You descend to depth ${player.depth}.');
    return true;
  }

  bool useItem(String name, int number) {
    if (number > player.pack.length) {
      say('You do not have that item.');
      return false;
    }
    final item = player.pack[number - 1];
    const classes = {'quaff': 'potion', 'read': 'scroll', 'wield': 'weapon', 'wear': 'armor', 'eat': 'food'};
    if (item.kind.category != classes[name]) {
      say('You cannot $name that.');
      return false;
    }
    return switch (name) {'quaff' => quaff(item), 'read' => readScroll(item), 'wield' => wield(item), 'wear' => wear(item), 'eat' => eat(item), _ => throw StateError('Unknown item command')};
  }

  bool quaff(Item item) {
    player.pack.remove(item);
    usage['quaffed'] = usage['quaffed']! + 1;
    say('You quaff the ${item.displayName}.');
    switch (item.kind.effect) {
      case 'heal':
        player.hp += item.kind.dice!.roll(rng);
        if (player.hp > player.maxHP) {
          player.maxHP++;
          player.hp = player.maxHP;
        }
        player.poison = 0;
        say('You feel better.');
      case 'poison':
        player.poison += item.kind.poisonTurns;
        say('You feel very sick.');
      case 'level':
        say('You feel more experienced.');
        if (player.level <= config.xpLevels.length) {
          gainXP(config.xpLevels[player.level - 1] - player.xp);
        }
    }
    return true;
  }

  bool readScroll(Item item) {
    final level = currentLevel;
    player.pack.remove(item);
    usage['read'] = usage['read']! + 1;
    say('You read the ${item.displayName}.');
    switch (item.kind.effect) {
      case 'mapping':
        for (var y = 0; y < level.height; y++) {
          for (var x = 0; x < level.width; x++) {
            if (level.terrain[y][x] != ' ' && level.memory[y][x] == ' ') {
              level.memory[y][x] = level.terrain[y][x];
            }
          }
        }
        say('A map forms in your mind.');
      case 'teleport':
        while (true) {
          final (_, point) = level.drawRoomCell(rng);
          if (point != player.position && level.monsterAt(point.x, point.y) == null) {
            player.position = point;
            break;
          }
        }
        say('You are teleported.');
      case 'enchant_weapon':
        final weapon = player.weapon;
        if (weapon == null) {
          say('Your hands twitch.');
        } else {
          say('Your ${weapon.displayName} glows blue.');
          weapon.bonus++;
        }
      case 'enchant_armor':
        final armor = player.armor;
        if (armor == null) {
          say('Your skin tingles.');
        } else {
          say('Your ${armor.displayName} glows silver.');
          armor.bonus++;
        }
    }
    return true;
  }

  bool wield(Item item) {
    if (identical(item, player.weapon)) {
      say('You are already wielding that.');
      return false;
    }
    player.weapon = item;
    usage['wielded'] = usage['wielded']! + 1;
    say('You are now wielding the ${item.displayName}.');
    return true;
  }
  bool wear(Item item) {
    if (identical(item, player.armor)) {
      say('You are already wearing that.');
      return false;
    }
    player.armor = item;
    usage['worn'] = usage['worn']! + 1;
    say('You are now wearing the ${item.displayName}.');
    return true;
  }
  bool eat(Item item) {
    player.pack.remove(item);
    usage['eaten'] = usage['eaten']! + 1;
    player.satiation = math.min(player.satiation + item.kind.nutrition, config.foodMax);
    say('You eat the ${item.displayName}.');
    return true;
  }

  void playerAttack(Level level, Monster monster) {
    monster.asleep = false;
    final weapon = player.weapon;
    var toHit = player.level, bonus = 0;
    var dice = const Dice(1, 2);
    if (weapon != null) {
      toHit += weapon.kind.toHit + weapon.bonus;
      dice = weapon.kind.dice!;
      bonus = weapon.bonus;
    }
    if (hungerState == 'weak' || hungerState == 'starving') {
      toHit -= 2;
    }
    final (outcome, damage) = resolveAttack(rng, toHit, monster.kind.defense, dice, bonus);
    playerAttacks.record(outcome, damage);
    final name = monster.kind.name;
    if (outcome == 'miss') {
      say('You miss the $name.');
      return;
    }
    say('You hit the $name${outcome == 'critical' ? ' hard' : ''} for $damage.');
    monster.hp -= damage;
    if (monster.hp <= 0) {
      say('You kill the $name.');
      level.monsters.remove(monster);
      level.kills++;
      kills[monster.kind.index]++;
      gainXP(monster.kind.xp);
    }
  }

  void gainXP(int amount) {
    player.xp += amount;
    while (player.level <= config.xpLevels.length && player.xp >= config.xpLevels[player.level - 1]) {
      player.level++;
      final gained = config.hitDie.roll(rng);
      player.maxHP += gained;
      player.hp += gained;
      say('Welcome to level ${player.level}.');
    }
  }

  void monsterAttack(Monster monster) {
    final kind = monster.kind;
    final (outcome, damage) = resolveAttack(rng, kind.toHit, player.defense, kind.damage, 0);
    monsterAttacks.record(outcome, damage);
    if (outcome == 'miss') {
      say('The ${kind.name} misses you.');
      return;
    }
    say('The ${kind.name} hits you${outcome == 'critical' ? ' hard' : ''} for $damage.');
    player.hp -= damage;
    if (player.hp <= 0) {
      die('killed_by ${kind.name}');
    } else if (kind.poisonous) {
      player.poison += 5;
      say('You are poisoned.');
    }
  }

  void monstersAct() {
    final level = currentLevel;
    distance = distances(level, player.position.x, player.position.y);
    for (final monster in level.monsters) {
      monster.energy += monster.kind.speed;
      while (monster.energy >= 2) {
        monster.energy -= 2;
        monsterAction(level, monster);
        if (result.isNotEmpty) {
          return;
        }
      }
    }
  }

  void monsterAction(Level level, Monster monster) {
    final sees = visible[monster.position.y][monster.position.x];
    if (monster.asleep) {
      if (sees && rng.rnd(100) < config.wakeChance) {
        monster.asleep = false;
        say('The ${monster.kind.name} wakes up.');
      }
    } else if (monster.kind.stationary) {
      if (canAttack(level, monster)) {
        monsterAttack(monster);
      }
    } else if (monster.kind.erratic && rng.rnd(2) == 0) {
      wander(level, monster);
    } else if (sees) {
      chase(level, monster);
    } else {
      wander(level, monster);
    }
  }
  bool canAttack(Level level, Monster monster) {
    final dx = player.position.x - monster.position.x, dy = player.position.y - monster.position.y;
    return math.max(dx.abs(), dy.abs()) == 1 && canMove(level, monster.position.x, monster.position.y, dx, dy);
  }
  void wander(Level level, Monster monster) {
    final step = directions[rng.rnd(8)], point = monster.position;
    if (!canMove(level, point.x, point.y, step.x, step.y)) {
      return;
    }
    final target = Point(point.x + step.x, point.y + step.y);
    if (target == player.position) {
      monsterAttack(monster);
    } else if (level.monsterAt(target.x, target.y) == null) {
      monster.position = target;
    }
  }
  void chase(Level level, Monster monster) {
    if (canAttack(level, monster)) {
      monsterAttack(monster);
      return;
    }
    final here = distance[monster.position.y][monster.position.x];
    Point? best;
    var bestDistance = 0;
    for (final step in directions) {
      final point = monster.position;
      if (!canMove(level, point.x, point.y, step.x, step.y)) {
        continue;
      }
      final target = Point(point.x + step.x, point.y + step.y);
      final steps = distance[target.y][target.x];
      if (steps < 0 || (here >= 0 && steps >= here) || target == player.position || level.monsterAt(target.x, target.y) != null) {
        continue;
      }
      if (best == null || steps < bestDistance) {
        best = target;
        bestDistance = steps;
      }
    }
    if (best != null) {
      monster.position = best;
    }
  }

  void endTurn() {
    for (final monster in currentLevel.monsters) {
      if (monster.kind.regenerates && monster.hp < monster.maxHP) {
        monster.hp++;
      }
    }
    if (player.poison > 0) {
      player.hp--;
      poisonDamage++;
      if (player.hp <= 0) {
        die('poison');
        return;
      }
      player.poison--;
      if (player.poison == 0) {
        say('You feel less sick.');
      }
    }
    if (player.satiation == 0) {
      player.hp--;
      starvationDamage++;
      if (player.hp <= 0) {
        die('starvation');
        return;
      }
    } else {
      final before = hungerState;
      player.satiation--;
      final after = hungerState;
      if (after != before) {
        say(switch (after) {'hungry' => 'You are getting hungry.', 'weak' => 'You feel weak from hunger.', 'starving' => 'You are starving.', _ => throw StateError('Unexpected hunger transition')});
      }
    }
    if (turn % config.regenInterval == 0 && player.poison == 0 && player.satiation > 0 && player.hp < player.maxHP) {
      player.hp++;
    }
  }

  String viewSymbol(Level level, int x, int y) {
    if (player.position == Point(x, y)) {
      return '@';
    }
    return level.monsterAt(x, y)?.kind.symbol ?? level.itemAt(x, y)?.symbol ?? level.terrain[y][x];
  }
  List<String> mapRows(Level level, bool current) {
    final border = '+${List.filled(level.width, '-').join()}+';
    final lines = [border];
    for (var y = 0; y < level.height; y++) {
      final row = [for (var x = 0; x < level.width; x++) current && visible[y][x] ? viewSymbol(level, x, y) : level.memory[y][x]];
      lines.add('|${row.join()}|');
    }
    return [...lines, border];
  }
  String get statusLine => 'STATUS hp ${player.hp}/${player.maxHP} level ${player.level} xp ${player.xp} defense ${player.defense} gold ${player.gold} food ${player.satiation} $hungerState poison ${player.poison}';
  void writeCheckpoint() {
    mapLines.add('CHECKPOINT turn $turn depth ${player.depth}');
    mapLines.addAll(mapRows(currentLevel, true));
    mapLines.add(statusLine);
  }
  List<String> finalBlock() {
    final lines = ['FINAL turn $succeeded depth ${player.depth}'];
    for (final level in levels.take(player.depth)) {
      final (explored, total) = exploration(level);
      lines.add('LEVEL ${level.depth} explored $explored/$total');
      lines.addAll(mapRows(level, level.depth == player.depth));
    }
    return [...lines, statusLine];
  }
  List<String> statsLines() {
    final lines = ['result $result', 'cause $cause', 'turns $succeeded', 'depth ${player.depth}', 'level ${player.level}',
      'xp ${player.xp}', 'hp ${player.hp}/${player.maxHP}', 'defense ${player.defense}', 'gold ${player.gold}',
      'food ${player.satiation} $hungerState', 'poison ${player.poison}', 'weapon ${player.weapon?.displayName ?? '-'}',
      'armor ${player.armor?.displayName ?? '-'}', 'commands ${commands.length} executed $succeeded failed $failed unused $unused',
      'moves $moves', playerAttacks.line('player_attacks'), monsterAttacks.line('monster_attacks'),
      'poison_damage $poisonDamage starvation_damage $starvationDamage', usage.entries.map((entry) => '${entry.key} ${entry.value}').join(' '),
      'kills ${kills.fold(0, (sum, count) => sum + count)}'];
    for (final kind in monsterTypes) {
      if (kills[kind.index] > 0) {
        lines.add('KILL ${kind.name} ${kills[kind.index]}');
      }
    }
    for (final level in levels) {
      final (explored, total) = exploration(level);
      lines.add('LEVEL ${level.depth} rooms ${level.rooms.length} explored $explored/$total ${dec1(100 * explored, total)} monsters ${level.kills}/${level.monstersCreated} items ${level.picked}/${level.itemsPlaced}');
    }
    for (var i = 0; i < player.pack.length; i++) {
      final item = player.pack[i];
      final suffix = identical(item, player.weapon) ? ' (wielded)' : identical(item, player.armor) ? ' (worn)' : '';
      lines.add('INVENTORY ${i + 1} ${item.displayName}$suffix');
    }
    return lines;
  }
}

void writeLines(String name, List<String> lines) {
  File('output/$name').writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
}
void main() {
  final config = Config(readRows('config.txt'));
  final monsterRows = readRows('monsters.txt');
  final monsterTypes = [for (var i = 0; i < monsterRows.length; i++) MonsterType(monsterRows[i], i)];
  final itemTypes = readRows('items.txt').map(parseItemType).toList();
  final game = Game(config, monsterTypes, itemTypes, expandCommands(readRows('commands.txt')));
  game.run();
  Directory('output').createSync(recursive: true);
  writeLines('messages.txt', game.messages);
  writeLines('maps.txt', [...game.mapLines, ...game.finalBlock()]);
  writeLines('stats.txt', game.statsLines());
}
