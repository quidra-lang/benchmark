import 'dart:collection';
import 'dart:io';
import 'dart:math' show min, max;

enum GameState { ready, playing, won, lost }
enum Mark { none, flag, question }
enum MoveKind {
  reveal('reveal'), flag('flag'), unflag('unflag'), question('question'), chord('chord'),
  autoReveal('auto-reveal'), autoFlag('auto-flag'), guess('guess');
  final String label;
  const MoveKind(this.label);
}

typedef Move = ({MoveKind kind, int cell});
typedef Frontier = ({List<Component> components, List<Component?> at});

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

class UndoRecord {
  final String name;
  final List<bool> revealed;
  final List<Mark> marks;
  final int moveCount;
  UndoRecord(this.name, this.revealed, this.marks, this.moveCount);
}

class Constraint {
  final int cell, remaining;
  final List<int> unknown;
  Constraint(this.cell, this.unknown, this.remaining);
}

class Deduction {
  final List<String?> safe, mines;
  Deduction(int size) : safe = List.filled(size, null), mines = List.filled(size, null);
  bool get any => safe.any((reason) => reason != null) || mines.any((reason) => reason != null);
}

class Totals {
  int rounds = 0, flagged = 0, opened = 0, guesses = 0;
  void add(Totals other) {
    rounds += other.rounds;
    flagged += other.flagged;
    opened += other.opened;
  }
}

class Component {
  final List<int> cells;
  final List<Constraint> constraints;
  final int boardSize;
  final List<int> mineCounts;
  int configurations = 0, maximum = 0, minimum;
  bool _counted = false;
  Component(this.cells, this.constraints, this.boardSize)
      : minimum = cells.length, mineCounts = List.filled(cells.length, 0);

  void count() {
    if (_counted) return;
    _counted = true;
    if (constraints.any((c) => c.remaining < 0 || c.remaining > c.unknown.length)) return;
    final index = List.filled(boardSize, 0);
    for (var i = 0; i < cells.length; i++) index[cells[i]] = i;
    final links = List.generate(cells.length, (_) => <int>[]);
    for (var c = 0; c < constraints.length; c++) {
      for (final cell in constraints[c].unknown) links[index[cell]].add(c);
    }
    final order = List.generate(cells.length, (i) => i);
    order.sort((a, b) {
      final degree = links[b].length.compareTo(links[a].length);
      return degree != 0 ? degree : a.compareTo(b);
    });
    final remaining = [for (final c in constraints) c.unknown.length];
    final sums = List.filled(constraints.length, 0);
    final assignment = List.filled(cells.length, 0);
    void search(int depth, int mines) {
      if (depth == cells.length) {
        configurations++;
        minimum = min(minimum, mines);
        maximum = max(maximum, mines);
        for (var i = 0; i < cells.length; i++) mineCounts[i] += assignment[i];
        return;
      }
      final variable = order[depth];
      for (var value = 0; value <= 1; value++) {
        assignment[variable] = value;
        var possible = true;
        for (final c in links[variable]) {
          remaining[c]--;
          sums[c] += value;
          final required = constraints[c].remaining;
          if (sums[c] > required || sums[c] + remaining[c] < required) possible = false;
        }
        if (possible) search(depth + 1, mines + value);
        for (final c in links[variable]) {
          sums[c] -= value;
          remaining[c]++;
        }
      }
    }
    search(0, 0);
  }
}

List<List<int>> makeNeighbors(int width, int height) => List.generate(width * height, (cell) {
  final x = cell % width, y = cell ~/ width;
  return [
    for (var dy = -1; dy <= 1; dy++)
      for (var dx = -1; dx <= 1; dx++)
        if ((dx != 0 || dy != 0) && x + dx >= 0 && x + dx < width && y + dy >= 0 && y + dy < height)
          (y + dy) * width + x + dx,
  ];
});

class Game {
  final int width, height, mineCount, seed;
  final List<List<int>> neighbors;
  List<bool>? mines;
  List<int> numbers;
  List<bool> revealed;
  List<Mark> marks;
  GameState state;
  int exploded;
  final List<Move> moves;
  final undo = <UndoRecord>[];

  Game(this.width, this.height, this.mineCount, this.seed, {List<bool>? placement})
      : neighbors = makeNeighbors(width, height), numbers = List.filled(width * height, 0),
        revealed = List.filled(width * height, false), marks = List.filled(width * height, Mark.none),
        state = GameState.ready, exploded = -1, moves = [] {
    if (placement != null) _setPlacement(placement);
  }

  Game.copy(Game source, {bool reset = false})
      : width = source.width, height = source.height, mineCount = source.mineCount, seed = source.seed,
        neighbors = source.neighbors, mines = source.mines, numbers = source.numbers,
        revealed = reset ? List.filled(source.size, false) : List.of(source.revealed),
        marks = reset ? List.filled(source.size, Mark.none) : List.of(source.marks),
        state = reset ? (source.mines == null ? GameState.ready : GameState.playing) : source.state,
        exploded = reset ? -1 : source.exploded, moves = reset ? [] : List.of(source.moves);

  int get size => width * height;
  bool get finished => state == GameState.won || state == GameState.lost;
  int get remaining => mineCount - marks.where((mark) => mark == Mark.flag).length;
  int get openCount => revealed.where((value) => value).length;
  String cellText(int cell) => '${cell % width},${cell ~/ width}';
  bool unknown(int cell) => !revealed[cell] && marks[cell] != Mark.flag;

  void _setPlacement(List<bool> placement) {
    mines = List.unmodifiable(placement);
    numbers = List.unmodifiable(neighbors.map((nearby) => nearby.where((cell) => placement[cell]).length));
    state = GameState.playing;
  }

  void _place(int first, String safety) {
    final sx = first % width, sy = first ~/ width;
    final candidates = <int>[];
    for (var cell = 0; cell < size; cell++) {
      if (safety == 'none' || safety == 'cell' && cell != first ||
          safety == 'block' && ((cell % width - sx).abs() >= 2 || (cell ~/ width - sy).abs() >= 2)) {
        candidates.add(cell);
      }
    }
    final placement = List.filled(size, false);
    var random = seed;
    for (var i = 0; i < mineCount; i++) {
      random = 48271 * random % 2147483647;
      placement[candidates.removeAt(random % candidates.length)] = true;
    }
    _setPlacement(placement);
  }

  void restart() {
    revealed = List.filled(size, false);
    marks = List.filled(size, Mark.none);
    moves.clear();
    undo.clear();
    exploded = -1;
    state = mines == null ? GameState.ready : GameState.playing;
  }

  UndoRecord snapshot(String name) => UndoRecord(name, List.of(revealed), List.of(marks), moves.length);
  void restore(UndoRecord saved) {
    revealed = saved.revealed;
    marks = saved.marks;
    moves.removeRange(saved.moveCount, moves.length);
  }

  int reveal(int first, String safety) {
    if (mines == null) _place(first, safety);
    if (mines![first]) {
      state = GameState.lost;
      exploded = first;
      return 0;
    }
    final queue = ListQueue<int>()..add(first);
    revealed[first] = true;
    marks[first] = Mark.none;
    var opened = 1;
    while (queue.isNotEmpty) {
      final cell = queue.removeFirst();
      if (numbers[cell] == 0) {
        for (final neighbor in neighbors[cell]) {
          if (unknown(neighbor)) {
            revealed[neighbor] = true;
            marks[neighbor] = Mark.none;
            queue.add(neighbor);
            opened++;
          }
        }
      }
    }
    return opened;
  }

  int chord(int cell, String safety) {
    var opened = 0;
    for (final neighbor in neighbors[cell]) {
      if (unknown(neighbor)) {
        opened += reveal(neighbor, safety);
        if (state == GameState.lost) break;
      }
    }
    return opened;
  }

  bool checkWin() {
    if (state != GameState.playing || openCount != size - mineCount) return false;
    state = GameState.won;
    for (var cell = 0; cell < size; cell++) {
      if (mines![cell]) marks[cell] = Mark.flag;
    }
    return true;
  }

  Iterable<String> display() sync* {
    for (var y = 0; y < height; y++) {
      final row = StringBuffer();
      for (var x = 0; x < width; x++) {
        final cell = y * width + x;
        row.write(state == GameState.lost && mines![cell]
            ? cell == exploded ? '!' : marks[cell] == Mark.flag ? 'F' : '*'
            : state == GameState.lost && marks[cell] == Mark.flag ? 'X'
            : revealed[cell] ? numbers[cell] == 0 ? '.' : '${numbers[cell]}'
            : marks[cell] == Mark.flag ? 'F' : marks[cell] == Mark.question ? '?' : '#');
      }
      yield row.toString();
    }
  }

  List<Constraint> _constraints() {
    final result = <Constraint>[];
    for (var cell = 0; cell < size; cell++) {
      if (revealed[cell] && numbers[cell] > 0) {
        final cells = neighbors[cell].where(unknown).toList();
        if (cells.isNotEmpty) {
          result.add(Constraint(cell, cells, numbers[cell] - neighbors[cell].where((n) => marks[n] == Mark.flag).length));
        }
      }
    }
    return result;
  }

  Deduction deduce() {
    final constraints = _constraints();
    final result = Deduction(size);
    for (final c in constraints) {
      if (c.remaining == 0) {
        for (final cell in c.unknown) result.safe[cell] ??= 'single ${cellText(c.cell)}';
      }
    }
    if (result.any) return result;
    for (final c in constraints) {
      if (c.remaining == c.unknown.length) {
        for (final cell in c.unknown) result.mines[cell] ??= 'single ${cellText(c.cell)}';
      }
    }
    if (result.any) return result;
    for (final a in constraints) {
      for (final b in constraints) {
        if (a.unknown.length >= b.unknown.length || !a.unknown.every(b.unknown.contains)) continue;
        final difference = b.unknown.length - a.unknown.length;
        final remaining = b.remaining - a.remaining;
        if (remaining != 0 && remaining != difference) continue;
        final side = remaining == 0 ? result.safe : result.mines;
        for (final cell in b.unknown) {
          if (!a.unknown.contains(cell)) side[cell] ??= 'subset ${cellText(a.cell)} ${cellText(b.cell)}';
        }
      }
    }
    if (result.any) return result;
    if (state == GameState.playing && remaining == 0) {
      for (var cell = 0; cell < size; cell++) {
        if (unknown(cell)) result.safe[cell] = 'count';
      }
    }
    return result;
  }

  Frontier buildFrontier() {
    final constraints = _constraints();
    final parents = List.generate(size, (i) => i);
    final frontier = List.filled(size, false);
    int root(int cell) {
      while (parents[cell] != cell) {
        parents[cell] = parents[parents[cell]];
        cell = parents[cell];
      }
      return cell;
    }
    for (final c in constraints) {
      for (final cell in c.unknown) {
        frontier[cell] = true;
        parents[root(cell)] = root(c.unknown.first);
      }
    }
    final groupForRoot = List.filled(size, -1);
    final groups = <List<int>>[];
    for (var cell = 0; cell < size; cell++) {
      if (!frontier[cell]) continue;
      final representative = root(cell);
      if (groupForRoot[representative] == -1) {
        groupForRoot[representative] = groups.length;
        groups.add([]);
      }
      groups[groupForRoot[representative]].add(cell);
    }
    final byGroup = List.generate(groups.length, (_) => <Constraint>[]);
    for (final c in constraints) byGroup[groupForRoot[root(c.unknown.first)]].add(c);
    final components = <Component>[];
    final at = List<Component?>.filled(size, null);
    for (var i = 0; i < groups.length; i++) {
      final component = Component(groups[i], byGroup[i], size);
      components.add(component);
      for (final cell in component.cells) at[cell] = component;
    }
    return (components: components, at: at);
  }

  Totals auto(String safety) {
    final totals = Totals();
    while (state == GameState.playing) {
      final deduction = deduce();
      if (!deduction.any) break;
      totals.rounds++;
      for (var cell = 0; cell < size; cell++) {
        if (deduction.safe[cell] != null && !revealed[cell]) {
          moves.add((kind: MoveKind.autoReveal, cell: cell));
          totals.opened += reveal(cell, safety);
          checkWin();
          if (finished) return totals;
        }
      }
      for (var cell = 0; cell < size; cell++) {
        if (deduction.mines[cell] != null && unknown(cell)) {
          marks[cell] = Mark.flag;
          totals.flagged++;
          moves.add((kind: MoveKind.autoFlag, cell: cell));
        }
      }
    }
    return totals;
  }

  Totals solve(String safety) {
    final totals = Totals();
    while (!finished) {
      totals.add(auto(safety));
      if (finished) break;
      final frontier = buildFrontier();
      final numerators = List.filled(size, 0), denominators = List.filled(size, 0);
      for (final component in frontier.components) {
        component.count();
        for (var i = 0; i < component.cells.length; i++) {
          numerators[component.cells[i]] = component.mineCounts[i];
          denominators[component.cells[i]] = component.configurations;
        }
      }
      var unknownCount = 0;
      for (var cell = 0; cell < size; cell++) {
        if (unknown(cell)) unknownCount++;
      }
      final backgroundMines = max(remaining, 0);
      var chosen = -1, bestNumerator = 0, bestDenominator = 1;
      for (var cell = 0; cell < size; cell++) {
        if (!unknown(cell)) continue;
        final numerator = frontier.at[cell] == null ? backgroundMines : numerators[cell];
        final denominator = frontier.at[cell] == null ? unknownCount : denominators[cell];
        if (denominator != 0 && (chosen == -1 || numerator * bestDenominator < bestNumerator * denominator)) {
          chosen = cell;
          bestNumerator = numerator;
          bestDenominator = denominator;
        }
      }
      if (chosen == -1) break;
      totals.guesses++;
      moves.add((kind: MoveKind.guess, cell: chosen));
      totals.opened += reveal(chosen, safety);
      checkWin();
    }
    return totals;
  }

  Game replay(int count, String safety) {
    final copy = Game.copy(this, reset: true);
    for (final move in moves.take(count)) {
      switch (move.kind) {
        case MoveKind.reveal: case MoveKind.autoReveal: case MoveKind.guess:
          copy.reveal(move.cell, safety);
          break;
        case MoveKind.chord: copy.chord(move.cell, safety); break;
        case MoveKind.flag: case MoveKind.autoFlag: copy.marks[move.cell] = Mark.flag; break;
        case MoveKind.unflag: copy.marks[move.cell] = Mark.none; break;
        case MoveKind.question:
          copy.marks[move.cell] = copy.marks[move.cell] == Mark.question ? Mark.none : Mark.question;
          break;
      }
      copy.moves.add(move);
      copy.checkWin();
    }
    return copy;
  }

  ({int bv, int openings, int largest}) boardInfo() {
    final visited = List.filled(size, false);
    var openings = 0, largest = 0, isolated = 0;
    bool blank(int cell) => !mines![cell] && numbers[cell] == 0;
    for (var first = 0; first < size; first++) {
      if (blank(first) && !visited[first]) {
        openings++;
        final area = <int>{first};
        final queue = ListQueue<int>()..add(first);
        visited[first] = true;
        while (queue.isNotEmpty) {
          final cell = queue.removeFirst();
          for (final neighbor in neighbors[cell]) {
            area.add(neighbor);
            if (blank(neighbor) && !visited[neighbor]) {
              visited[neighbor] = true;
              queue.add(neighbor);
            }
          }
        }
        largest = max(largest, area.length);
      }
      if (!mines![first] && numbers[first] > 0 && !neighbors[first].any(blank)) isolated++;
    }
    return (bv: openings + isolated, openings: openings, largest: largest);
  }
}

const arities = {
  'NEW': 4, 'PRESET': 2, 'LAYOUT': 2, 'SAFETY': 1, 'RESTART': 0,
  'REVEAL': 2, 'FLAG': 2, 'UNFLAG': 2, 'QUESTION': 2, 'CHORD': 2,
  'UNDO': 0, 'SHOW': 0, 'STATUS': 0, 'CELL': 2, 'HISTORY': 1,
  'REPLAY': 1, 'HINT': 0, 'AUTO': 0, 'ANALYZE': 0, 'PROB': 2,
  'FRONTIER': 0, 'SOLVE': 0, 'BOARDINFO': 0, 'STATS': 0,
};
const cellCommands = {'REVEAL', 'FLAG', 'UNFLAG', 'QUESTION', 'CHORD', 'CELL', 'PROB'};
const activeCommands = {'REVEAL', 'FLAG', 'UNFLAG', 'QUESTION', 'CHORD', 'UNDO', 'HINT', 'AUTO', 'ANALYZE', 'PROB', 'FRONTIER', 'SOLVE'};
const undoCommands = {'REVEAL', 'FLAG', 'UNFLAG', 'QUESTION', 'CHORD', 'AUTO', 'SOLVE'};

Never fail(String message) => throw CommandError(message);
void emit(String line) => stdout.writeln(line);
int number(String word) {
  if (word.length > 10 || word.length > 1 && word[0] == '0' || word.codeUnits.any((c) => c < 48 || c > 57)) fail('bad arguments');
  return int.parse(word);
}
void show(Game game) {
  for (final row in game.display()) emit(row);
}
void finishOutput(Game game) {
  if (game.state == GameState.lost) {
    emit('boom ${game.cellText(game.exploded)}');
    show(game);
  } else if (game.state == GameState.won) {
    emit('win moves ${game.moves.length}');
  }
}

class Program {
  Game? game;
  String safety = 'block';
  int played = 0, wins = 0, losses = 0, streak = 0, best = 0;
  int? fastest;

  void recordFinish(Game game) {
    played++;
    if (game.state == GameState.won) {
      wins++;
      streak++;
      best = max(best, streak);
      fastest = fastest == null ? game.moves.length : min(fastest!, game.moves.length);
    } else {
      losses++;
      streak = 0;
    }
  }

  void layout(List<String> words) {
    final width = int.parse(words[1]), height = int.parse(words[2]);
    final rows = [for (var y = 0; y < height; y++) stdin.readLineSync()!];
    for (var y = 0; y < height; y++) {
      if (rows[y].length != width || rows[y].codeUnits.any((c) => c != 42 && c != 46)) fail('bad row ${y + 1}');
    }
    final mines = [for (final row in rows) for (final c in row.codeUnits) c == 42];
    final count = mines.where((value) => value).length;
    if (count == 0 || count == width * height) fail('bad mine count $count');
    game = Game(width, height, count, 0, placement: mines);
    emit('layout ${width}x$height mines $count');
  }

  void execute(List<String> words) {
    final command = words[0];
    if (command == 'LAYOUT') { layout(words); return; }
    final arity = arities[command];
    if (arity == null) fail('unknown command $command');
    if (words.length != arity + 1) fail('bad arguments');
    final values = List.filled(arity, 0);
    for (var i = 0; i < arity; i++) {
      final word = words[i + 1];
      if (command == 'PRESET' && i == 0) {
        if (!const {'beginner', 'intermediate', 'expert'}.contains(word)) fail('bad arguments');
      } else if (command == 'SAFETY') {
        if (!const {'block', 'cell', 'none'}.contains(word)) fail('bad arguments');
      } else {
        values[i] = number(word);
      }
    }
    if (command == 'NEW' || command == 'PRESET') {
      int width, height, mines, seed;
      if (command == 'NEW') {
        width = values[0]; height = values[1]; mines = values[2]; seed = values[3];
      } else {
        (width, height, mines) = switch (words[1]) {
          'beginner' => (9, 9, 10), 'intermediate' => (16, 16, 40), _ => (30, 16, 99),
        };
        seed = values[1];
      }
      if (width < 1 || width > 30 || height < 1 || height > 30 || mines < 1 || mines > width * height - 9 || seed < 1 || seed > 2147483646) fail('bad value');
      game = Game(width, height, mines, seed);
      emit('new ${width}x$height mines $mines');
      return;
    }
    if (command == 'HISTORY' && values[0] == 0) fail('bad value');
    if (command == 'SAFETY') { safety = words[1]; emit('safety $safety'); return; }
    if (command == 'STATS') {
      final rate = played == 0 ? '-' : '${wins * 100 ~/ played}%';
      emit('stats played $played won $wins lost $losses rate $rate streak $streak best $best fastest ${fastest ?? '-'}');
      return;
    }
    final board = game;
    if (board == null) fail('no game');
    var cell = 0;
    if (cellCommands.contains(command)) {
      if (values[0] >= board.width || values[1] >= board.height) fail('out of range');
      cell = values[1] * board.width + values[0];
    }
    if (board.finished && activeCommands.contains(command)) fail('game over');
    if (board.mines == null && (command == 'ANALYZE' || command == 'BOARDINFO')) fail('not started');
    final wasFinished = board.finished;
    final snapshot = undoCommands.contains(command) ? board.snapshot(command.toLowerCase()) : null;
    switch (command) {
      case 'RESTART':
        board.restart();
        emit('restart ${board.width}x${board.height} mines ${board.mineCount}');
        break;
      case 'REVEAL':
        if (board.revealed[cell]) fail('already revealed');
        if (board.marks[cell] == Mark.flag) fail('flagged');
        board.moves.add((kind: MoveKind.reveal, cell: cell));
        final opened = board.reveal(cell, safety);
        if (board.state != GameState.lost) emit('revealed $opened');
        board.checkWin();
        finishOutput(board);
        break;
      case 'FLAG': case 'UNFLAG': case 'QUESTION':
        if (board.revealed[cell]) fail('already revealed');
        if (command == 'FLAG' && board.marks[cell] == Mark.flag) fail('already flagged');
        if (command == 'UNFLAG' && board.marks[cell] != Mark.flag) fail('not flagged');
        String action;
        if (command == 'FLAG') { board.marks[cell] = Mark.flag; action = 'flagged'; }
        else if (command == 'UNFLAG') { board.marks[cell] = Mark.none; action = 'unflagged'; }
        else if (board.marks[cell] == Mark.question) { board.marks[cell] = Mark.none; action = 'unmarked'; }
        else { board.marks[cell] = Mark.question; action = 'questioned'; }
        board.moves.add((kind: command == 'FLAG' ? MoveKind.flag : command == 'UNFLAG' ? MoveKind.unflag : MoveKind.question, cell: cell));
        emit('$action ${board.cellText(cell)} left ${board.remaining}');
        break;
      case 'CHORD':
        if (!board.revealed[cell]) fail('not revealed');
        if (board.numbers[cell] == 0) fail('no number');
        final flags = board.neighbors[cell].where((n) => board.marks[n] == Mark.flag).length;
        if (flags != board.numbers[cell]) fail('flags $flags of ${board.numbers[cell]}');
        if (!board.neighbors[cell].any(board.unknown)) fail('nothing to reveal');
        board.moves.add((kind: MoveKind.chord, cell: cell));
        final chorded = board.chord(cell, safety);
        if (board.state != GameState.lost) emit('chorded $chorded');
        board.checkWin();
        finishOutput(board);
        break;
      case 'UNDO':
        if (board.undo.isEmpty) fail('nothing to undo');
        final saved = board.undo.removeLast();
        board.restore(saved);
        emit('undo ${saved.name} moves ${board.moves.length}');
        break;
      case 'SHOW': show(board); break;
      case 'STATUS':
        emit('status ${board.state.name} left ${board.remaining} moves ${board.moves.length} revealed ${board.openCount}/${board.size - board.mineCount}');
        break;
      case 'CELL':
        if (board.revealed[cell]) {
          emit('cell ${board.cellText(cell)} number ${board.numbers[cell]} flags ${board.neighbors[cell].where((n) => board.marks[n] == Mark.flag).length} unknown ${board.neighbors[cell].where(board.unknown).length}');
        } else {
          emit('cell ${board.cellText(cell)} hidden mark ${board.marks[cell].name} open ${board.neighbors[cell].where((n) => board.revealed[n]).length}');
        }
        break;
      case 'HISTORY':
        emit('history ${board.moves.length}');
        for (var i = board.moves.length - min(values[0], board.moves.length); i < board.moves.length; i++) {
          emit('${i + 1} ${board.moves[i].kind.label} ${board.cellText(board.moves[i].cell)}');
        }
        break;
      case 'REPLAY':
        if (values[0] > board.moves.length) fail('no move ${values[0]}');
        emit('replay ${values[0]}/${board.moves.length}');
        show(board.replay(values[0], safety));
        break;
      case 'HINT':
        final deduction = board.deduce();
        var target = deduction.safe.indexWhere((reason) => reason != null);
        if (target != -1) {
          emit('hint safe ${board.cellText(target)} by ${deduction.safe[target]}');
        } else {
          target = deduction.mines.indexWhere((reason) => reason != null);
          emit(target == -1 ? 'hint none' : 'hint mine ${board.cellText(target)} by ${deduction.mines[target]}');
        }
        break;
      case 'AUTO': case 'SOLVE':
        final totals = command == 'AUTO' ? board.auto(safety) : board.solve(safety);
        emit(command == 'AUTO' ? 'auto rounds ${totals.rounds} flagged ${totals.flagged} revealed ${totals.opened}'
            : 'solve guesses ${totals.guesses} rounds ${totals.rounds} flagged ${totals.flagged} revealed ${totals.opened}');
        finishOutput(board);
        break;
      case 'ANALYZE':
        final copy = Game.copy(board);
        final analysis = copy.auto(safety);
        emit(copy.state == GameState.lost ? 'analyze boom ${copy.cellText(copy.exploded)} rounds ${analysis.rounds}'
            : copy.state == GameState.won ? 'analyze clear rounds ${analysis.rounds}'
            : 'analyze stuck rounds ${analysis.rounds} revealed ${copy.openCount}/${copy.size - copy.mineCount}');
        break;
      case 'PROB':
        if (board.revealed[cell]) fail('already revealed');
        if (board.marks[cell] == Mark.flag) fail('flagged');
        final component = board.buildFrontier().at[cell];
        if (component == null) { emit('prob ${board.cellText(cell)} unconstrained'); }
        else {
          component.count();
          if (component.configurations == 0) { emit('prob ${board.cellText(cell)} inconsistent'); }
          else {
            final numerator = component.mineCounts[component.cells.indexOf(cell)], denominator = component.configurations;
            final divisor = numerator.gcd(denominator);
            emit('prob ${board.cellText(cell)} ${numerator ~/ divisor}/${denominator ~/ divisor} size ${component.cells.length} configs ${component.configurations}');
          }
        }
        break;
      case 'FRONTIER':
        final frontier = board.buildFrontier();
        final count = frontier.components.fold(0, (sum, part) => sum + part.cells.length);
        emit('frontier $count components ${frontier.components.length}');
        for (final part in frontier.components) {
          part.count();
          final prefix = 'component ${board.cellText(part.cells.first)} size ${part.cells.length}';
          emit(part.configurations == 0 ? '$prefix inconsistent' : '$prefix configs ${part.configurations} min ${part.minimum} max ${part.maximum}');
        }
        break;
      case 'BOARDINFO':
        final info = board.boardInfo();
        emit('3bv ${info.bv} openings ${info.openings} largest ${info.largest} mines ${board.mineCount} safe ${board.size - board.mineCount}');
        break;
    }
    if (snapshot != null && board.moves.length > snapshot.moveCount) board.undo.add(snapshot);
    if (!wasFinished && board.finished) recordFinish(board);
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final program = Program();
  for (var i = 0; i < count; i++) {
    final words = stdin.readLineSync()!.split(' ');
    try { program.execute(words); }
    on CommandError catch (error) { emit('error: ${error.message}'); }
  }
}
