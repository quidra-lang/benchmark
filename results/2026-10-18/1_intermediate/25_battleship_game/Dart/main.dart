import 'dart:io';
import 'dart:math' show min, max;

enum Phase { setup, battle, over }
enum Strategy { hunt, prob, random }
enum ViewKind { reef, unattacked, miss, hit, sunk }
enum ShotKind { already, miss, hit, sunk }
enum LogMode { normal, match, silent }
typedef Choice = ({int cell, String info});

const shipNames = ['CARRIER', 'BATTLESHIP', 'CRUISER', 'SUBMARINE', 'DESTROYER'];
const shipLengths = [5, 4, 3, 3, 2];
const shipSymbols = 'CBRSD';
const lineDirections = [(0, 1), (1, 0)];
const stackDirections = [(0, -1), (1, 0), (0, 1), (-1, 0)];
final surroundings = List.generate(100, (cell) => <int>[
  for (var dr = -1; dr <= 1; dr++)
    for (var dc = -1; dc <= 1; dc++)
      if ((dr != 0 || dc != 0) && step(cell, dr, dc) >= 0) step(cell, dr, dc),
]);

int step(int cell, int dr, int dc) {
  final row = cell ~/ 10 + dr, column = cell % 10 + dc;
  return row >= 0 && row < 10 && column >= 0 && column < 10 ? row * 10 + column : -1;
}
String coordinate(int cell) => '${String.fromCharCode(65 + cell ~/ 10)}${cell % 10 + 1}';
int parseCell(String text) => (text.codeUnitAt(0) - 65) * 10 + int.parse(text.substring(1)) - 1;
String shipRange(List<int> cells) => '${coordinate(cells.first)}-${coordinate(cells.last)}';
int advance(int state) => 48271 * state % 2147483647;
String strategyName(Strategy strategy) => strategy.name.toUpperCase();
Strategy parseStrategy(String text) => Strategy.values.firstWhere((value) => strategyName(value) == text);
String switchName(bool enabled) => enabled ? 'ON' : 'OFF';
List<int>? positions(int start, bool horizontal, int length) {
  if ((horizontal ? start % 10 : start ~/ 10) + length > 10) return null;
  return List.generate(length, (i) => start + i * (horizontal ? 1 : 10));
}
bool touching(List<int> first, List<int> second) => first.any((cell) => surroundings[cell].any(second.contains));

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

class Shot {
  final ShotKind kind;
  final int ship;
  const Shot(this.kind, [this.ship = -1]);
  bool get isHit => kind == ShotKind.hit || kind == ShotKind.sunk;
  String get text => kind == ShotKind.sunk ? 'SUNK ${shipNames[ship]}' : kind.name.toUpperCase();
}

class Player {
  final ships = List.generate(5, (_) => <int>[]);
  final owner = List.filled(100, -1);
  final attacked = List.filled(100, false);
  final candidates = <int>[];
  int random;
  Strategy? controller;
  bool torpedoUsed = false, sonarUsed = false;
  int shots = 0, hits = 0, sinks = 0, turns = 0, streak = 0, bestStreak = 0, wins = 0;
  Player(this.random);
  bool sunk(int ship) => ships[ship].isNotEmpty && ships[ship].every((cell) => attacked[cell]);
  int get placed => ships.where((cells) => cells.isNotEmpty).length;
  int get afloat => [for (var ship = 0; ship < 5; ship++) if (ships[ship].isNotEmpty && !sunk(ship)) ship].length;

  void setShip(int ship, List<int> cells) {
    for (final cell in ships[ship]) owner[cell] = -1;
    ships[ship] = cells;
    for (final cell in cells) owner[cell] = ship;
  }
  void clearFleet() {
    for (var ship = 0; ship < 5; ship++) setShip(ship, []);
  }
  void record(Shot result) {
    shots++;
    if (result.isHit) {
      hits++; streak++; bestStreak = max(bestStreak, streak);
    } else {
      streak = 0;
    }
    if (result.kind == ShotKind.sunk) sinks++;
  }
}

class View {
  final List<ViewKind> cells;
  final List<bool> excluded;
  final List<int> remaining;
  View(this.cells, this.excluded, this.remaining);
  bool candidate(int cell) => cell >= 0 && cell < 100 && cells[cell] == ViewKind.unattacked && !excluded[cell];
}

class Game {
  final players = [Player(1), Player(2)];
  List<bool> reefs = List.filled(100, false);
  bool salvo = false, chain = false, touch = false;
  Phase phase = Phase.setup;
  int current = 0, winner = -1;

  int allowance(int player) => salvo ? players[player].afloat : 1;
  void setupCheck() {
    if (phase != Phase.setup) throw CommandError('setup closed');
  }
  void turnCheck(int player) {
    if (phase == Phase.over) throw CommandError('game over');
    if (phase == Phase.setup && players.any((p) => p.placed != 5)) throw CommandError('fleets not ready');
    if (player != current) throw CommandError('not your turn');
  }
  String? placementProblem(int player, List<int>? cells) {
    if (cells == null) return 'out of bounds';
    if (cells.any((cell) => reefs[cell])) return 'on reef';
    var first = 5;
    for (final cell in cells) {
      if (players[player].owner[cell] >= 0) first = min(first, players[player].owner[cell]);
    }
    if (first < 5) return 'overlaps ${shipNames[first]}';
    if (!touch) {
      for (final cell in cells) {
        for (final neighbor in surroundings[cell]) {
          if (players[player].owner[neighbor] >= 0) first = min(first, players[player].owner[neighbor]);
        }
      }
      if (first < 5) return 'touches ${shipNames[first]}';
    }
    return null;
  }
  int autoPlace(int player, int seed) {
    final owner = players[player];
    owner.random = seed;
    owner.clearFleet();
    var attempts = 0;
    for (var ship = 0; ship < 5; ship++) {
      while (true) {
        attempts++;
        final length = shipLengths[ship];
        owner.random = advance(owner.random);
        final horizontal = owner.random.isEven;
        owner.random = advance(owner.random);
        final k = owner.random % (10 * (11 - length));
        final start = horizontal ? k ~/ (11 - length) * 10 + k % (11 - length) : k;
        final cells = positions(start, horizontal, length)!;
        if (placementProblem(player, cells) != null) continue;
        owner.setShip(ship, cells);
        break;
      }
    }
    return attempts;
  }
  void layout(int player, String text) {
    final grid = text.replaceAll('/', '');
    final fleet = <List<int>>[];
    for (var ship = 0; ship < 5; ship++) {
      final cells = [for (var cell = 0; cell < 100; cell++) if (grid[cell] == shipSymbols[ship]) cell];
      final name = shipNames[ship];
      final length = shipLengths[ship];
      if (cells.length != length) throw CommandError('$name has ${cells.length} cells');
      var horizontal = true, vertical = true;
      for (var i = 0; i < length; i++) {
        horizontal = horizontal && cells[i] == cells[0] + i && cells[i] ~/ 10 == cells[0] ~/ 10;
        vertical = vertical && cells[i] == cells[0] + 10 * i;
      }
      if (!horizontal && !vertical) throw CommandError('$name not straight');
      if (cells.any((cell) => reefs[cell])) throw CommandError('$name on reef');
      fleet.add(cells);
    }
    if (!touch) {
      for (var first = 0; first < 5; first++) {
        for (var second = first + 1; second < 5; second++) {
          if (touching(fleet[first], fleet[second])) throw CommandError('${shipNames[first]} touches ${shipNames[second]}');
        }
      }
    }
    players[player].clearFleet();
    for (var ship = 0; ship < 5; ship++) players[player].setShip(ship, fleet[ship]);
  }
  void placedLines(int player, List<String> output) {
    for (var ship = 0; ship < 5; ship++) {
      output.add('PLACED ${player + 1} ${shipNames[ship]} ${shipRange(players[player].ships[ship])}');
    }
  }
  View view(int player) {
    final opponent = players[1 - player];
    final sunk = List.generate(5, opponent.sunk);
    final cells = List.generate(100, (cell) {
      final ship = opponent.owner[cell];
      return reefs[cell] ? ViewKind.reef : !opponent.attacked[cell] ? ViewKind.unattacked :
          ship < 0 ? ViewKind.miss : sunk[ship] ? ViewKind.sunk : ViewKind.hit;
    });
    final excluded = List.filled(100, false);
    if (!touch) {
      for (var cell = 0; cell < 100; cell++) {
        if (cells[cell] == ViewKind.sunk) {
          for (final neighbor in surroundings[cell]) excluded[neighbor] = true;
        }
      }
    }
    return View(cells, excluded, [for (var ship = 0; ship < 5; ship++) if (!sunk[ship]) ship]);
  }
  static List<int> scores(View view) {
    final result = List.filled(100, 0);
    for (final ship in view.remaining) {
      for (var start = 0; start < 100; start++) {
        for (final horizontal in [true, false]) {
          final cells = positions(start, horizontal, shipLengths[ship]);
          if (cells == null || cells.any((cell) => view.excluded[cell] ||
              (view.cells[cell] != ViewKind.unattacked && view.cells[cell] != ViewKind.hit))) continue;
          final weight = 1 + 10 * cells.where((cell) => view.cells[cell] == ViewKind.hit).length;
          for (final cell in cells) result[cell] += weight;
        }
      }
    }
    return result;
  }
  static int best(View view, List<int> scores) {
    var chosen = -1;
    for (var cell = 0; cell < 100; cell++) {
      if (view.cells[cell] == ViewKind.unattacked && (chosen < 0 || scores[cell] > scores[chosen])) chosen = cell;
    }
    return chosen;
  }
  Choice choose(int player, Strategy strategy, {bool advanceRandom = true}) {
    final currentView = view(player);
    if (strategy == Strategy.prob) {
      final density = scores(currentView);
      final cell = best(currentView, density);
      return (cell: cell, info: '${density[cell]}');
    }
    if (strategy == Strategy.random) {
      final candidates = [for (var cell = 0; cell < 100; cell++) if (currentView.candidate(cell)) cell];
      final random = advance(players[player].random);
      if (advanceRandom) players[player].random = random;
      return (cell: candidates[random % candidates.length], info: '${candidates.length}');
    }
    for (var cell = 0; cell < 100; cell++) {
      if (currentView.cells[cell] != ViewKind.hit) continue;
      for (final (dr, dc) in lineDirections) {
        var front = step(cell, dr, dc);
        if (front < 0 || currentView.cells[front] != ViewKind.hit) continue;
        while (front >= 0 && currentView.cells[front] == ViewKind.hit) front = step(front, dr, dc);
        final back = step(cell, -dr, -dc);
        if (currentView.candidate(front)) return (cell: front, info: 'LINE');
        if (currentView.candidate(back)) return (cell: back, info: 'LINE');
      }
    }
    for (final cell in players[player].candidates.reversed) {
      if (currentView.candidate(cell)) return (cell: cell, info: 'STACK');
    }
    final shortest = currentView.remaining.map((ship) => shipLengths[ship]).reduce(min);
    for (var cell = 0; cell < 100; cell++) {
      if (currentView.candidate(cell) && (cell ~/ 10 + cell % 10) % shortest == 0) return (cell: cell, info: 'PARITY');
    }
    throw StateError('No strategy candidate');
  }
  Shot shoot(int player, int cell) {
    final owner = players[player], opponent = players[1 - player];
    Shot result;
    if (opponent.attacked[cell]) {
      result = const Shot(ShotKind.already);
    } else {
      opponent.attacked[cell] = true;
      final ship = opponent.owner[cell];
      result = ship < 0 ? const Shot(ShotKind.miss) : opponent.sunk(ship) ? Shot(ShotKind.sunk, ship) : const Shot(ShotKind.hit);
      if (result.kind == ShotKind.hit) {
        for (final (dr, dc) in stackDirections) {
          final neighbor = step(cell, dr, dc);
          if (neighbor >= 0) owner.candidates.add(neighbor);
        }
      }
    }
    owner.record(result);
    return result;
  }
  void finishTurn(int player, bool hit, LogMode mode, List<String>? output) {
    players[player].turns++;
    if (players[1 - player].afloat == 0) {
      phase = Phase.over; winner = player; players[player].wins++;
      if (mode == LogMode.normal) output!.add('WINNER ${player + 1}');
    } else {
      current = chain && hit ? player : 1 - player;
    }
  }
  void shootingTurn(int player, {Strategy? strategy, List<int>? targets, LogMode mode = LogMode.normal, List<String>? output}) {
    final count = allowance(player);
    phase = Phase.battle;
    var hit = false;
    for (var i = 0; i < count; i++) {
      final cell = strategy == null ? targets![i] : choose(player, strategy).cell;
      final result = shoot(player, cell);
      hit = hit || result.isHit;
      if (mode == LogMode.normal) output!.add('SHOT ${player + 1} ${coordinate(cell)} ${result.text}');
      if (mode == LogMode.match && result.kind == ShotKind.sunk) output!.add('SINK ${player + 1} ${shipNames[result.ship]} ${players[player].shots}');
      if (players[1 - player].afloat == 0) break;
    }
    finishTurn(player, hit, mode, output);
  }
  void torpedo(int player, int row, bool west, List<String> output) {
    phase = Phase.battle;
    players[player].torpedoUsed = true;
    final opponent = players[1 - player];
    var result = 'MISS';
    var stoppedAtShip = false, hit = false;
    for (var i = 0; i < 10; i++) {
      final cell = row * 10 + (west ? i : 9 - i);
      if (reefs[cell]) { result = 'REEF ${coordinate(cell)}'; break; }
      if (opponent.owner[cell] >= 0) {
        final shot = shoot(player, cell);
        result = '${shot.text} ${coordinate(cell)}';
        hit = shot.isHit; stoppedAtShip = true; break;
      }
      opponent.attacked[cell] = true;
    }
    if (!stoppedAtShip) players[player].record(const Shot(ShotKind.miss));
    output.add('TORPEDO ${player + 1} ${String.fromCharCode(65 + row)} ${west ? 'W' : 'E'} $result');
    finishTurn(player, hit, LogMode.normal, output);
  }
  void sonar(int player, int cell, List<String> output) {
    phase = Phase.battle;
    players[player].sonarUsed = true;
    final opponent = players[1 - player];
    final count = [cell, ...surroundings[cell]].where((at) => opponent.owner[at] >= 0 && !opponent.attacked[at]).length;
    output.add('SONAR ${player + 1} ${coordinate(cell)} $count');
    finishTurn(player, false, LogMode.normal, output);
  }
  void automatic(List<String> output) {
    while (phase == Phase.battle && players[current].controller != null) {
      shootingTurn(current, strategy: players[current].controller!, output: output);
    }
  }
  void show(int player, bool radar, List<String> output) {
    output.add('${radar ? 'RADAR' : 'BOARD'} ${player + 1}');
    output.add('  1 2 3 4 5 6 7 8 9 10');
    final currentView = radar ? view(player) : null;
    final owner = players[player];
    const viewSymbols = ['~', '.', 'o', 'x', '#'];
    for (var row = 0; row < 10; row++) {
      final symbols = <String>[];
      for (var column = 0; column < 10; column++) {
        final cell = row * 10 + column, ship = owner.owner[cell];
        final symbol = currentView != null ? viewSymbols[currentView.cells[cell].index] : reefs[cell] ? '~' :
            ship >= 0 ? (owner.attacked[cell] ? shipSymbols[ship].toLowerCase() : shipSymbols[ship]) : owner.attacked[cell] ? 'o' : '.';
        symbols.add(symbol);
      }
      output.add('${String.fromCharCode(65 + row)} ${symbols.join(' ')}');
    }
  }
  void density(int player, List<String> output) {
    final currentView = view(player);
    final distribution = scores(currentView);
    output.add('DENSITY ${player + 1}');
    output.add(' ${[for (var column = 1; column <= 10; column++) '$column'.padLeft(5)].join()}');
    for (var row = 0; row < 10; row++) {
      final text = StringBuffer(String.fromCharCode(65 + row));
      for (var column = 0; column < 10; column++) {
        final cell = row * 10 + column;
        final value = currentView.cells[cell] == ViewKind.unattacked ? '${distribution[cell]}' : currentView.cells[cell] == ViewKind.reef ? '~' : '-';
        text.write(value.padLeft(5));
      }
      output.add(text.toString());
    }
    final cell = best(currentView, distribution);
    output.add('BEST ${coordinate(cell)} ${distribution[cell]}');
  }
  void fleet(int player, List<String> output) {
    final owner = players[player];
    output.add('FLEET ${player + 1} afloat ${owner.afloat}');
    for (var ship = 0; ship < 5; ship++) {
      final cells = owner.ships[ship];
      output.add(cells.isEmpty ? '${shipNames[ship]} unplaced' :
          '${shipNames[ship]} ${shipRange(cells)} ${cells.where((cell) => owner.attacked[cell]).length}/${shipLengths[ship]} ${owner.sunk(ship) ? 'SUNK' : 'AFLOAT'}');
    }
  }
  String exportFleet(int player) => [
    for (var row = 0; row < 10; row++) [
      for (var column = 0; column < 10; column++)
        players[player].owner[row * 10 + column] < 0 ? '.' : shipSymbols[players[player].owner[row * 10 + column]],
    ].join(),
  ].join('/');
  String status() {
    final text = 'STATUS ${phase.name.toUpperCase()} salvo ${switchName(salvo)} chain ${switchName(chain)} touch ${switchName(touch)} reefs ${reefs.where((value) => value).length}';
    if (phase == Phase.setup) return '$text placed ${players[0].placed} ${players[1].placed}';
    final afloat = 'afloat ${players[0].afloat} ${players[1].afloat}';
    return phase == Phase.battle ? '$text turn ${current + 1} shots ${allowance(current)} $afloat' : '$text winner ${winner + 1} $afloat';
  }
  void stats(List<String> output) {
    for (var i = 0; i < 2; i++) {
      final player = players[i];
      final accuracy = player.shots == 0 ? '-' : '${player.hits * 100 ~/ player.shots}%';
      output.add('STATS ${i + 1} shots ${player.shots} hits ${player.hits} sunk ${player.sinks} turns ${player.turns} streak ${player.bestStreak} accuracy $accuracy wins ${player.wins}');
    }
  }
  Game match(int firstSeed, int secondSeed, Strategy first, Strategy second, {List<String>? sinks}) {
    final game = Game()
      ..salvo = salvo
      ..chain = chain
      ..touch = touch
      ..reefs = List.of(reefs);
    game.autoPlace(0, firstSeed); game.autoPlace(1, secondSeed);
    game.phase = Phase.battle;
    final strategies = [first, second];
    while (game.phase == Phase.battle) {
      game.shootingTurn(game.current, strategy: strategies[game.current], mode: sinks == null ? LogMode.silent : LogMode.match, output: sinks);
    }
    return game;
  }
}

class Program {
  Game game = Game();
  static const setupCommands = {'PLACE', 'REMOVE', 'AUTOPLACE', 'LAYOUT', 'REEF', 'SALVO', 'CHAIN', 'TOUCH'};
  static const turnCommands = {'FIRE', 'AI', 'TORPEDO', 'SONAR'};

  List<String> execute(List<String> words) {
    final command = words[0];
    final output = <String>[];
    if (setupCommands.contains(command)) game.setupCheck();
    if (turnCommands.contains(command)) {
      final player = int.parse(words[1]) - 1;
      game.turnCheck(player);
      switch (command) {
        case 'FIRE':
          final cells = words.skip(2).map(parseCell).toList();
          if (cells.length != game.allowance(player)) throw CommandError('expected ${game.allowance(player)} shots');
          for (final cell in cells) {
            if (game.reefs[cell]) throw CommandError('reef at ${coordinate(cell)}');
          }
          game.shootingTurn(player, targets: cells, output: output);
        case 'AI':
          game.shootingTurn(player, strategy: parseStrategy(words[2]), output: output);
        case 'TORPEDO':
          if (game.players[player].torpedoUsed) throw CommandError('torpedo used');
          game.torpedo(player, words[2].codeUnitAt(0) - 65, words[3] == 'W', output);
        case 'SONAR':
          if (game.players[player].sonarUsed) throw CommandError('sonar used');
          game.sonar(player, parseCell(words[2]), output);
      }
      game.automatic(output);
      return output;
    }
    switch (command) {
      case 'NEW':
        final wins = [for (final player in game.players) player.wins];
        game = Game();
        for (var i = 0; i < 2; i++) game.players[i].wins = wins[i];
        output.add('NEW');
      case 'PLACE':
        final player = int.parse(words[1]) - 1, ship = shipNames.indexOf(words[2]);
        if (game.players[player].ships[ship].isNotEmpty) throw CommandError('${words[2]} already placed');
        final cells = positions(parseCell(words[3]), words[4] == 'H', shipLengths[ship]);
        final problem = game.placementProblem(player, cells);
        if (problem != null) throw CommandError(problem);
        final placed = cells!;
        game.players[player].setShip(ship, placed);
        output.add('PLACED ${player + 1} ${words[2]} ${shipRange(placed)}');
      case 'REMOVE':
        final player = int.parse(words[1]) - 1, ship = shipNames.indexOf(words[2]);
        if (game.players[player].ships[ship].isEmpty) throw CommandError('${words[2]} not placed');
        game.players[player].setShip(ship, []);
        output.add('REMOVED ${player + 1} ${words[2]}');
      case 'AUTOPLACE':
        final player = int.parse(words[1]) - 1;
        final attempts = game.autoPlace(player, int.parse(words[2]));
        output.add('AUTOPLACE ${player + 1} attempts $attempts');
        game.placedLines(player, output);
      case 'LAYOUT':
        final player = int.parse(words[1]) - 1;
        game.layout(player, words[2]);
        output.add('LAYOUT ${player + 1}'); game.placedLines(player, output);
      case 'REEF':
        final cell = parseCell(words[1]);
        if (game.reefs[cell]) throw CommandError('reef exists at ${coordinate(cell)}');
        for (var player = 0; player < 2; player++) {
          final ship = game.players[player].owner[cell];
          if (ship >= 0) throw CommandError('${coordinate(cell)} occupied by ${player + 1} ${shipNames[ship]}');
        }
        game.reefs[cell] = true; output.add('REEF ${coordinate(cell)}');
      case 'SALVO':
      case 'CHAIN':
      case 'TOUCH':
        final enabled = words[1] == 'ON';
        if (command == 'SALVO') game.salvo = enabled;
        if (command == 'CHAIN') game.chain = enabled;
        if (command == 'TOUCH') game.touch = enabled;
        output.add('$command ${words[1]}');
      case 'CONTROL':
        final player = int.parse(words[1]) - 1;
        game.players[player].controller = words[2] == 'HUMAN' ? null : parseStrategy(words[2]);
        output.add('CONTROL ${player + 1} ${words[2]}');
      case 'SEED':
        final player = int.parse(words[1]) - 1, seed = int.parse(words[2]);
        game.players[player].random = seed;
        output.add('SEED ${player + 1} $seed');
      case 'RESIGN':
        if (game.phase != Phase.battle) throw CommandError('not in battle');
        final player = int.parse(words[1]) - 1;
        game.winner = 1 - player; game.phase = Phase.over; game.players[game.winner].wins++;
        output.add('RESIGN ${player + 1}'); output.add('WINNER ${game.winner + 1}');
      case 'HINT':
        if (game.phase == Phase.over) throw CommandError('game over');
        final player = int.parse(words[1]) - 1;
        final choice = game.choose(player, parseStrategy(words[2]), advanceRandom: false);
        output.add('HINT ${player + 1} ${words[2]} ${coordinate(choice.cell)} ${choice.info}');
      case 'DENSITY':
        if (game.phase == Phase.over) throw CommandError('game over');
        game.density(int.parse(words[1]) - 1, output);
      case 'SHOW':
      case 'RADAR':
        game.show(int.parse(words[1]) - 1, command == 'RADAR', output);
      case 'EXPORT':
        final player = int.parse(words[1]) - 1;
        output.add('EXPORT ${player + 1} ${game.exportFleet(player)}');
      case 'FLEET':
        game.fleet(int.parse(words[1]) - 1, output);
      case 'STATUS':
        output.add(game.status());
      case 'STATS':
        game.stats(output);
      case 'MATCH':
      case 'SERIES':
      case 'TOURNEY':
        simulation(words, output);
    }
    return output;
  }
  void simulation(List<String> words, List<String> output) {
    if (words[0] == 'MATCH') {
      output.add('MATCH 1 ${words[3]} 2 ${words[4]}');
      final match = game.match(int.parse(words[1]), int.parse(words[2]), parseStrategy(words[3]), parseStrategy(words[4]), sinks: output);
      output.add('RESULT winner ${match.winner + 1} shots ${match.players[0].shots} ${match.players[1].shots} hits ${match.players[0].hits} ${match.players[1].hits}');
      return;
    }
    final count = int.parse(words[1]);
    var random = int.parse(words[2]);
    if (words[0] == 'SERIES') {
      final wins = [0, 0], shots = [0, 0];
      final fastest = <int?>[null, null];
      for (var i = 0; i < count; i++) {
        random = advance(random); final first = random; random = advance(random);
        final match = game.match(first, random, parseStrategy(words[3]), parseStrategy(words[4]));
        wins[match.winner]++;
        for (var player = 0; player < 2; player++) shots[player] += match.players[player].shots;
        final winningShots = match.players[match.winner].shots;
        fastest[match.winner] = min(fastest[match.winner] ?? winningShots, winningShots);
      }
      output.add('SERIES $count wins ${wins[0]} ${wins[1]} shots ${shots[0]} ${shots[1]} fastest ${fastest[0] ?? '-'} ${fastest[1] ?? '-'}');
      return;
    }
    final wins = [0, 0, 0], shots = [0, 0, 0];
    for (var first = 0; first < 3; first++) {
      for (var second = 0; second < 3; second++) {
        if (first == second) continue;
        for (var i = 0; i < count; i++) {
          random = advance(random); final firstSeed = random; random = advance(random);
          final match = game.match(firstSeed, random, Strategy.values[first], Strategy.values[second]);
          wins[match.winner == 0 ? first : second]++;
          shots[first] += match.players[0].shots; shots[second] += match.players[1].shots;
        }
      }
    }
    final ranking = [0, 1, 2]..sort((a, b) {
      final byWins = wins[b].compareTo(wins[a]), byShots = shots[a].compareTo(shots[b]);
      return byWins != 0 ? byWins : byShots != 0 ? byShots : a.compareTo(b);
    });
    output.add('TOURNEY $count');
    for (var rank = 0; rank < 3; rank++) {
      final strategy = ranking[rank];
      output.add('${rank + 1} ${strategyName(Strategy.values[strategy])} wins ${wins[strategy]} shots ${shots[strategy]}');
    }
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final program = Program();
  for (var i = 0; i < count; i++) {
    try {
      for (final line in program.execute(stdin.readLineSync()!.split(' '))) stdout.writeln(line);
    } on CommandError catch (error) {
      stdout.writeln('ERROR ${error.message}');
    }
  }
}
