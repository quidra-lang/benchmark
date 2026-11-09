import 'dart:collection';
import 'dart:io';
import 'dart:math';

const directions = 'udlr';
const deltas = [(-1, 0), (1, 0), (0, -1), (0, 1)];
const turns = {
  'ROT90': 'rlud',
  'ROT180': 'durl',
  'ROT270': 'lrdu',
  'FLIPH': 'udrl',
  'FLIPV': 'dulr',
};
const stepLetters = 'udlrUDLR';
const levelCharacters = r'#-.$*@+';
const digits = '0123456789';
const maxSide = 10;
const maxLimit = 100000;
final numberWord = RegExp(r'^(0|[1-9][0-9]{0,5})$');
final nameWord = RegExp(r'^[a-z]{1,8}$');

enum ArgumentKind { number, steps, direction, snapshotName, transform, text }

const cellKinds = [ArgumentKind.number, ArgumentKind.number];
const commands = <String, List<ArgumentKind>>{
  'IMPORT': [ArgumentKind.text],
  'VALID': [],
  'INFO': [],
  'SHOW': [],
  'EXPORT': [],
  'MOVE': [ArgumentKind.steps],
  'PUSH': [...cellKinds, ArgumentKind.direction],
  'BRING': [...cellKinds, ...cellKinds],
  'PATH': cellKinds,
  'UNDO': [ArgumentKind.number],
  'REDO': [ArgumentKind.number],
  'RESET': [],
  'STATUS': [],
  'HISTORY': [],
  'BOXES': [],
  'REACH': [],
  'DEADSQUARES': [],
  'DEADLOCK': [],
  'BOUND': [],
  'SAVE': [ArgumentKind.snapshotName],
  'RESTORE': [ArgumentKind.snapshotName],
  'CHECK': [ArgumentKind.steps],
  'SOLVE': [ArgumentKind.number],
  'HINT': [ArgumentKind.number],
  'PLAY': [],
  'TRANSFORM': [ArgumentKind.transform],
};
const cellCounts = {'PATH': 1, 'PUSH': 1, 'BRING': 2};
const levelFreeCommands = {'IMPORT', 'VALID'};

typedef Push = ({int box, String direction});
typedef Simulation = ({
  Position position,
  List<String> letters,
  String? failure,
});
typedef Snapshot = ({Position position, List<String> history});
typedef Solution = ({String notation, Position position});
typedef Assignment = ({List<int> order, List<int> pushes, int total});

class CommandException implements Exception {
  final String message;

  CommandException(this.message);
}

class StepException implements Exception {
  final String reason;

  StepException(this.reason);
}

String? decode(String text, String allowed) {
  final result = StringBuffer();
  var index = 0;
  while (index < text.length) {
    final start = index;
    while (index < text.length && digits.contains(text[index])) {
      index++;
    }
    final count = text.substring(start, index);
    if (count.length > 2 || count.startsWith('0') || index == text.length) {
      return null;
    }
    if (!allowed.contains(text[index])) {
      return null;
    }
    result.write(text[index] * (count.isEmpty ? 1 : int.parse(count)));
    index++;
  }
  return result.toString();
}

String encode(String text) {
  final result = StringBuffer();
  var start = 0;
  while (start < text.length) {
    var end = start;
    while (end < text.length && text[end] == text[start]) {
      end++;
    }
    final run = end - start;
    if (run > 1) {
      result.write(run);
    }
    result.write(text[start]);
    start = end;
  }
  return result.toString();
}

String stepSequence(String word) => decode(word, stepLetters)!.toLowerCase();

bool validArgument(ArgumentKind kind, String text) => switch (kind) {
  ArgumentKind.number => numberWord.hasMatch(text),
  ArgumentKind.steps => decode(text, stepLetters) != null,
  ArgumentKind.direction => text.length == 1 && directions.contains(text),
  ArgumentKind.snapshotName => nameWord.hasMatch(text),
  ArgumentKind.transform => turns.containsKey(text),
  ArgumentKind.text => true,
};

bool isPush(String letter) => letter != letter.toLowerCase();

int pushCount(Iterable<String> letters) => letters.where(isPush).length;

int countTrue(List<bool> flags) => flags.where((flag) => flag).length;

List<String> turnLetters(Iterable<String> letters, String kind) {
  final turn = turns[kind]!;
  return [
    for (final letter in letters)
      if (isPush(letter))
        turn[directions.indexOf(letter.toLowerCase())].toUpperCase()
      else
        turn[directions.indexOf(letter)],
  ];
}

List<int> moveBox(List<int> boxes, int source, int destination) =>
    [for (final box in boxes) box == source ? destination : box]..sort();

String counted(String label, List<String> letters) =>
    letters.isEmpty ? '$label 0' : '$label ${letters.length} ${letters.join()}';

Iterable<List<int>> permutations(List<int> items) sync* {
  if (items.isEmpty) {
    yield [];
    return;
  }
  for (final item in items) {
    final rest = [
      for (final other in items)
        if (other != item) other,
    ];
    for (final tail in permutations(rest)) {
      yield [item, ...tail];
    }
  }
}

List<bool> findInterior(int height, int width, List<bool> walls, int start) {
  final interior = List.filled(height * width, false);
  interior[start] = true;
  final stack = [start];
  while (stack.isNotEmpty) {
    final cell = stack.removeLast();
    final row = cell ~/ width;
    final column = cell % width;
    for (final (dRow, dColumn) in deltas) {
      final nextRow = row + dRow;
      final nextColumn = column + dColumn;
      if (nextRow >= 0 &&
          nextRow < height &&
          nextColumn >= 0 &&
          nextColumn < width) {
        final neighbor = nextRow * width + nextColumn;
        if (!walls[neighbor] && !interior[neighbor]) {
          interior[neighbor] = true;
          stack.add(neighbor);
        }
      }
    }
  }
  return interior;
}

class Position {
  final int player;
  final List<int> boxes;

  Position(this.player, this.boxes);

  bool same(Position other) {
    if (player != other.player || boxes.length != other.boxes.length) {
      return false;
    }
    for (var index = 0; index < boxes.length; index++) {
      if (boxes[index] != other.boxes[index]) {
        return false;
      }
    }
    return true;
  }
}

class Level {
  final int height;
  final int width;
  final int size;
  final List<bool> walls;
  final List<bool> goals;
  final List<bool> interior;
  final List<int> offsets;
  final List<int> goalCells;
  String? reason;
  List<List<int?>> distances = [];
  List<bool> dead;

  Level(this.height, this.width, this.walls, this.goals, this.interior)
    : size = height * width,
      offsets = [for (final (dRow, dColumn) in deltas) dRow * width + dColumn],
      goalCells = [
        for (var cell = 0; cell < goals.length; cell++)
          if (goals[cell]) cell,
      ],
      dead = List.filled(height * width, false);

  int offsetOf(String direction) => offsets[directions.indexOf(direction)];

  String cellText(int cell) => '${cell ~/ width + 1} ${cell % width + 1}';

  int cellAt(int row, int column) => (row - 1) * width + column - 1;

  bool contains(int row, int column) =>
      1 <= row && row <= height && 1 <= column && column <= width;

  bool onBorder(int cell) {
    final row = cell ~/ width;
    final column = cell % width;
    return row == 0 || row == height - 1 || column == 0 || column == width - 1;
  }

  String? invalidity(int players, List<int> boxes) {
    if (players != 1) {
      return 'players $players';
    }
    if (boxes.isEmpty) {
      return 'no boxes';
    }
    if (boxes.length != goalCells.length) {
      return 'boxes ${boxes.length} goals ${goalCells.length}';
    }
    for (var cell = 0; cell < size; cell++) {
      if (interior[cell] && onBorder(cell)) {
        return 'open ${cellText(cell)}';
      }
    }
    for (var cell = 0; cell < size; cell++) {
      if ((goals[cell] || boxes.contains(cell)) && !interior[cell]) {
        return 'outside ${cellText(cell)}';
      }
    }
    return null;
  }

  void analyze() {
    distances = [for (final goal in goalCells) pushDistances(goal)];
    dead = [
      for (var cell = 0; cell < size; cell++)
        interior[cell] && goalDistance(cell) == null,
    ];
  }

  List<int?> pushDistances(int goal) {
    final distance = List<int?>.filled(size, null);
    distance[goal] = 0;
    final queue = Queue.of([goal]);
    while (queue.isNotEmpty) {
      final cell = queue.removeFirst();
      for (final offset in offsets) {
        final box = cell - offset;
        if (interior[box] && interior[box - offset] && distance[box] == null) {
          distance[box] = distance[cell]! + 1;
          queue.add(box);
        }
      }
    }
    return distance;
  }

  int? goalDistance(int cell) {
    final defined = distances.map((distance) => distance[cell]).nonNulls;
    return defined.isEmpty ? null : defined.reduce(min);
  }

  int boxesOnGoals(List<int> boxes) => boxes.where((box) => goals[box]).length;

  bool solved(List<int> boxes) => boxesOnGoals(boxes) == boxes.length;

  List<bool> reachable(int player, List<int> boxes) {
    final seen = List.filled(size, false);
    seen[player] = true;
    final stack = [player];
    while (stack.isNotEmpty) {
      final cell = stack.removeLast();
      for (final offset in offsets) {
        final neighbor = cell + offset;
        if (interior[neighbor] &&
            !seen[neighbor] &&
            !boxes.contains(neighbor)) {
          seen[neighbor] = true;
          stack.add(neighbor);
        }
      }
    }
    return seen;
  }

  int representative(int player, List<int> boxes) =>
      reachable(player, boxes).indexOf(true);

  String walkPath(int start, int target, List<int> boxes) {
    final cameFrom = List<(int, String)?>.filled(size, null);
    final queue = Queue.of([start]);
    while (queue.isNotEmpty) {
      final cell = queue.removeFirst();
      for (final direction in directions.split('')) {
        final neighbor = cell + offsetOf(direction);
        if (interior[neighbor] &&
            !boxes.contains(neighbor) &&
            neighbor != start &&
            cameFrom[neighbor] == null) {
          cameFrom[neighbor] = (cell, direction);
          queue.add(neighbor);
        }
      }
    }
    final path = <String>[];
    var cell = target;
    while (cell != start) {
      final (previous, direction) = cameFrom[cell]!;
      path.add(direction);
      cell = previous;
    }
    return path.reversed.join();
  }

  (Position, String) step(Position position, String direction) {
    final offset = offsetOf(direction);
    final target = position.player + offset;
    if (walls[target]) {
      throw StepException('wall');
    }
    if (!position.boxes.contains(target)) {
      return (Position(target, position.boxes), direction);
    }
    final beyond = target + offset;
    if (walls[beyond] || position.boxes.contains(beyond)) {
      throw StepException('blocked');
    }
    final boxes = moveBox(position.boxes, target, beyond);
    return (Position(target, boxes), direction.toUpperCase());
  }

  bool pushable(
    int box,
    String direction,
    List<int> boxes,
    List<bool> reachable,
  ) {
    final offset = offsetOf(direction);
    final destination = box + offset;
    return reachable[box - offset] &&
        interior[destination] &&
        !boxes.contains(destination);
  }

  bool sideBlocked(
    int box,
    List<int> sides,
    List<int> boxes,
    List<int> assumed,
  ) {
    if (sides.any((side) => walls[side] || assumed.contains(side))) {
      return true;
    }
    if (sides.every((side) => dead[side])) {
      return true;
    }
    final extended = [...assumed, box];
    return sides.any(
      (side) => boxes.contains(side) && frozen(side, boxes, extended),
    );
  }

  bool frozen(int box, List<int> boxes, List<int> assumed) {
    final horizontal = [box + offsetOf('l'), box + offsetOf('r')];
    final vertical = [box + offsetOf('u'), box + offsetOf('d')];
    return sideBlocked(box, horizontal, boxes, assumed) &&
        sideBlocked(box, vertical, boxes, assumed);
  }

  bool hasFrozenBox(List<int> boxes) =>
      boxes.any((box) => !goals[box] && frozen(box, boxes, const []));

  List<String> splitRows(List<String> symbols) => [
    for (var start = 0; start < size; start += width)
      symbols.sublist(start, start + width).join(),
  ];

  String symbol(int cell, Position position) {
    if (walls[cell]) {
      return '#';
    }
    if (cell == position.player) {
      return goals[cell] ? '+' : '@';
    }
    if (position.boxes.contains(cell)) {
      return goals[cell] ? '*' : r'$';
    }
    return goals[cell] ? '.' : '-';
  }

  List<String> render(Position position) => splitRows([
    for (var cell = 0; cell < size; cell++) symbol(cell, position),
  ]);

  String deadSymbol(int cell) {
    if (walls[cell]) {
      return '#';
    }
    if (goals[cell]) {
      return '.';
    }
    return dead[cell] ? 'x' : '-';
  }

  List<String> deadMap() =>
      splitRows([for (var cell = 0; cell < size; cell++) deadSymbol(cell)]);

  int mapCell(String kind, int cell) {
    final row = cell ~/ width;
    final column = cell % width;
    final lastRow = height - 1;
    final lastColumn = width - 1;
    return switch (kind) {
      'ROT90' => column * height + lastRow - row,
      'ROT180' => (lastRow - row) * width + lastColumn - column,
      'ROT270' => (lastColumn - column) * height + row,
      'FLIPH' => row * width + lastColumn - column,
      _ => (lastRow - row) * width + column,
    };
  }

  Position mapPosition(String kind, Position position) => Position(
    mapCell(kind, position.player),
    [for (final box in position.boxes) mapCell(kind, box)]..sort(),
  );

  Level transformed(String kind) {
    final rotated = kind == 'ROT90' || kind == 'ROT270';
    final movedWalls = List.filled(size, false);
    final movedGoals = List.filled(size, false);
    final movedInterior = List.filled(size, false);
    for (var cell = 0; cell < size; cell++) {
      final moved = mapCell(kind, cell);
      movedWalls[moved] = walls[cell];
      movedGoals[moved] = goals[cell];
      movedInterior[moved] = interior[cell];
    }
    return Level(
      rotated ? width : height,
      rotated ? height : width,
      movedWalls,
      movedGoals,
      movedInterior,
    )..analyze();
  }
}

(Level, Position) buildLevel(List<String> rows) {
  final height = rows.length;
  final width = rows[0].length;
  final cells = rows.join().split('');
  final walls = [for (final symbol in cells) symbol == '#'];
  final goals = [for (final symbol in cells) '.*+'.contains(symbol)];
  final players = [
    for (var cell = 0; cell < cells.length; cell++)
      if ('@+'.contains(cells[cell])) cell,
  ];
  final boxes = [
    for (var cell = 0; cell < cells.length; cell++)
      if (r'$*'.contains(cells[cell])) cell,
  ];
  final interior = players.length == 1
      ? findInterior(height, width, walls, players[0])
      : List.filled(cells.length, false);
  final level = Level(height, width, walls, goals, interior);
  level.reason = level.invalidity(players.length, boxes);
  if (level.reason == null) {
    level.analyze();
  }
  return (level, Position(players.isEmpty ? -1 : players[0], boxes));
}

class SearchNode {
  final List<int> boxes;
  final int representative;
  final int? parent;
  final Push? push;

  SearchNode(this.boxes, this.representative, this.parent, this.push);
}

class SearchResult {
  final String outcome;
  final int expanded;
  final int states;
  final String notation;

  SearchResult(this.outcome, this.expanded, this.states, [this.notation = '']);
}

String stateKey(List<int> boxes, int representative) =>
    '${boxes.join(',')}/$representative';

List<Push> solutionPushes(List<SearchNode> nodes) {
  final pushes = <Push>[];
  var node = nodes.last;
  while (node.parent != null) {
    pushes.add(node.push!);
    node = nodes[node.parent!];
  }
  return pushes.reversed.toList();
}

String solutionNotation(Level level, Position start, List<Push> pushes) {
  var position = start;
  final notation = StringBuffer();
  for (final (:box, :direction) in pushes) {
    final offset = level.offsetOf(direction);
    notation.write(
      level.walkPath(position.player, box - offset, position.boxes),
    );
    notation.write(direction.toUpperCase());
    position = Position(box, moveBox(position.boxes, box, box + offset));
  }
  return notation.toString();
}

SearchResult pushSearch(
  Level level,
  Position start,
  List<int> fixed,
  int? target,
  bool pruning,
  int? limit,
) {
  final first = SearchNode(
    start.boxes,
    level.representative(start.player, start.boxes),
    null,
    null,
  );
  final nodes = [first];
  final known = {stateKey(first.boxes, first.representative)};
  var expanded = 0;
  while (expanded < nodes.length) {
    if (expanded == limit) {
      return SearchResult('limit', expanded, nodes.length);
    }
    final node = nodes[expanded];
    expanded++;
    final reachable = level.reachable(node.representative, node.boxes);
    for (final box in node.boxes) {
      if (fixed.contains(box)) {
        continue;
      }
      for (final direction in directions.split('')) {
        if (!level.pushable(box, direction, node.boxes, reachable)) {
          continue;
        }
        final destination = box + level.offsetOf(direction);
        final boxes = moveBox(node.boxes, box, destination);
        if (pruning && (level.dead[destination] || level.hasFrozenBox(boxes))) {
          continue;
        }
        final representative = level.representative(box, boxes);
        if (!known.add(stateKey(boxes, representative))) {
          continue;
        }
        final push = (box: box, direction: direction);
        nodes.add(SearchNode(boxes, representative, expanded - 1, push));
        final reached = target == null
            ? level.solved(boxes)
            : destination == target;
        if (reached) {
          final notation = solutionNotation(
            level,
            start,
            solutionPushes(nodes),
          );
          return SearchResult('found', expanded, nodes.length, notation);
        }
      }
    }
  }
  return SearchResult('no solution', expanded, nodes.length);
}

class Sokoban {
  final output = StringBuffer();
  late Level level;
  late Position initial;
  late Position current;
  List<String> history = [];
  List<String> redoList = [];
  Map<String, Snapshot> snapshots = {};
  Solution? solution;
  late final Map<String, void Function(List<String>)> handlers = {
    'IMPORT': importLevel,
    'VALID': valid,
    'INFO': info,
    'SHOW': show,
    'EXPORT': exportLevel,
    'MOVE': move,
    'PUSH': push,
    'BRING': bring,
    'PATH': path,
    'UNDO': undo,
    'REDO': redo,
    'RESET': reset,
    'STATUS': status,
    'HISTORY': showHistory,
    'BOXES': showBoxes,
    'REACH': reach,
    'DEADSQUARES': deadSquares,
    'DEADLOCK': deadlock,
    'BOUND': bound,
    'SAVE': save,
    'RESTORE': restore,
    'CHECK': check,
    'SOLVE': solve,
    'HINT': hint,
    'PLAY': play,
    'TRANSFORM': transform,
  };

  Sokoban(List<String> rows) {
    load(rows);
  }

  void emit(String line) {
    output.writeln(line);
  }

  void load(List<String> rows) {
    final (loaded, position) = buildLevel(rows);
    level = loaded;
    initial = position;
    current = position;
    history = [];
    redoList = [];
    snapshots = {};
    solution = null;
  }

  int cellArgument(List<String> arguments, int index) => level.cellAt(
    int.parse(arguments[index]),
    int.parse(arguments[index + 1]),
  );

  Simulation simulate(String directions) {
    var position = current;
    final letters = <String>[];
    try {
      for (final direction in directions.split('')) {
        final (next, letter) = level.step(position, direction);
        position = next;
        letters.add(letter);
      }
    } on StepException catch (failure) {
      final reason = 'step ${letters.length + 1} ${failure.reason}';
      return (position: position, letters: letters, failure: reason);
    }
    return (position: position, letters: letters, failure: null);
  }

  Simulation takeSteps(String directions) {
    final simulation = simulate(directions);
    current = simulation.position;
    history.addAll(simulation.letters);
    if (simulation.letters.isNotEmpty) {
      redoList = [];
    }
    return simulation;
  }

  String progress(List<int> boxes) {
    final onGoals = level.boxesOnGoals(boxes);
    final text = 'goals $onGoals/${boxes.length}';
    return onGoals == boxes.length ? '$text solved' : text;
  }

  (String, String?) searchSolution(int limit) {
    if (level.solved(current.boxes)) {
      return ('already solved', null);
    }
    final result = pushSearch(level, current, const [], null, true, limit);
    final counts = 'expanded ${result.expanded} states ${result.states}';
    if (result.outcome != 'found') {
      return ('${result.outcome} $counts', null);
    }
    final notation = result.notation;
    final pushes = pushCount(notation.split(''));
    return (
      'solution pushes $pushes moves ${notation.length} $counts',
      notation,
    );
  }

  void loadRows(int width, List<String> rows) {
    for (var number = 1; number <= rows.length; number++) {
      final row = rows[number - 1];
      final known = row.split('').every(levelCharacters.contains);
      if (row.length != width || !known) {
        throw CommandException('bad row $number');
      }
    }
    load(rows);
    emit('loaded ${rows.length}x$width');
  }

  void importLevel(List<String> arguments) {
    final decoded = [
      for (final part in arguments[0].split('|')) decode(part, levelCharacters),
    ];
    if (decoded.contains(null) || decoded.length > maxSide) {
      throw CommandException('bad level');
    }
    final rows = decoded.nonNulls.toList();
    final width = rows[0].length;
    if (rows.any((row) => row.length != width) ||
        width < 1 ||
        width > maxSide) {
      throw CommandException('bad level');
    }
    load(rows);
    emit('loaded ${rows.length}x$width');
  }

  void valid(List<String> arguments) {
    final reason = level.reason;
    emit(reason == null ? 'valid' : 'invalid $reason');
  }

  void info(List<String> arguments) {
    final walls = countTrue(level.walls);
    final cells = countTrue(level.interior);
    final dead = countTrue(level.dead);
    emit(
      'size ${level.height}x${level.width} walls $walls cells $cells '
      'boxes ${current.boxes.length} dead $dead',
    );
  }

  void show(List<String> arguments) {
    level.render(current).forEach(emit);
  }

  void exportLevel(List<String> arguments) {
    emit('level ${level.render(current).map(encode).join('|')}');
  }

  void move(List<String> arguments) {
    final simulation = takeSteps(stepSequence(arguments[0]));
    if (simulation.letters.isNotEmpty) {
      emit('moved ${simulation.letters.join()}');
    }
    final failure = simulation.failure;
    if (failure != null) {
      throw CommandException(failure);
    }
  }

  void push(List<String> arguments) {
    final box = cellArgument(arguments, 0);
    final direction = arguments[2];
    final offset = level.offsetOf(direction);
    final boxes = current.boxes;
    if (!boxes.contains(box)) {
      throw CommandException('no box');
    }
    final destination = box + offset;
    if (!level.interior[destination] || boxes.contains(destination)) {
      throw CommandException('blocked');
    }
    if (!level.reachable(current.player, boxes)[box - offset]) {
      throw CommandException('unreachable');
    }
    final path = level.walkPath(current.player, box - offset, boxes);
    emit('pushed ${takeSteps(path + direction).letters.join()}');
  }

  void bring(List<String> arguments) {
    final source = cellArgument(arguments, 0);
    final target = cellArgument(arguments, 2);
    if (!current.boxes.contains(source)) {
      throw CommandException('no box');
    }
    if (source == target) {
      emit('brought 0');
      return;
    }
    final fixed = [
      for (final box in current.boxes)
        if (box != source) box,
    ];
    final result = pushSearch(level, current, fixed, target, false, null);
    if (result.outcome != 'found') {
      throw CommandException('no route');
    }
    final notation = result.notation;
    takeSteps(notation.toLowerCase());
    emit('brought ${pushCount(notation.split(''))} $notation');
  }

  void path(List<String> arguments) {
    final target = cellArgument(arguments, 0);
    if (!level.reachable(current.player, current.boxes)[target]) {
      throw CommandException('unreachable');
    }
    final path = level.walkPath(current.player, target, current.boxes);
    emit(counted('path', takeSteps(path).letters));
  }

  void undo(List<String> arguments) {
    if (history.isEmpty) {
      throw CommandException('nothing to undo');
    }
    final count = min(int.parse(arguments[0]), history.length);
    for (var index = 0; index < count; index++) {
      final letter = history.removeLast();
      final direction = letter.toLowerCase();
      final offset = level.offsetOf(direction);
      final player = current.player;
      final boxes = isPush(letter)
          ? moveBox(current.boxes, player + offset, player)
          : current.boxes;
      current = Position(player - offset, boxes);
      redoList.add(direction);
    }
    emit('undone $count');
  }

  void redo(List<String> arguments) {
    if (redoList.isEmpty) {
      throw CommandException('nothing to redo');
    }
    final count = min(int.parse(arguments[0]), redoList.length);
    for (var index = 0; index < count; index++) {
      final (position, letter) = level.step(current, redoList.removeLast());
      current = position;
      history.add(letter);
    }
    emit('redone $count');
  }

  void reset(List<String> arguments) {
    current = initial;
    history = [];
    redoList = [];
    emit('reset');
  }

  void status(List<String> arguments) {
    emit(
      'moves ${history.length} pushes ${pushCount(history)} '
      '${progress(current.boxes)}',
    );
  }

  void showHistory(List<String> arguments) {
    emit(counted('history', history));
  }

  void showBoxes(List<String> arguments) {
    final boxes = current.boxes;
    final reachable = level.reachable(current.player, boxes);
    emit('boxes ${boxes.length}');
    for (final box in boxes) {
      final distance = level.goalDistance(box) ?? 'dead';
      final pushable = directions
          .split('')
          .where(
            (direction) => level.pushable(box, direction, boxes, reachable),
          )
          .join();
      emit(
        'box ${level.cellText(box)} $distance ${pushable.isEmpty ? '-' : pushable}',
      );
    }
  }

  void reach(List<String> arguments) {
    final reachable = level.reachable(current.player, current.boxes);
    final first = level.cellText(reachable.indexOf(true));
    emit('reach ${countTrue(reachable)} first $first');
  }

  void deadSquares(List<String> arguments) {
    emit('dead ${countTrue(level.dead)}');
    level.deadMap().forEach(emit);
  }

  void deadlock(List<String> arguments) {
    final boxes = current.boxes;
    for (final box in boxes) {
      if (level.dead[box]) {
        emit('deadlock dead ${level.cellText(box)}');
        return;
      }
    }
    for (final box in boxes) {
      if (!level.goals[box] && level.frozen(box, boxes, const [])) {
        emit('deadlock frozen ${level.cellText(box)}');
        return;
      }
    }
    emit('no deadlock');
  }

  void bound(List<String> arguments) {
    final boxes = current.boxes;
    Assignment? best;
    final goalIndices = List.generate(level.goalCells.length, (index) => index);
    for (final order in permutations(goalIndices)) {
      final pushes = [
        for (var index = 0; index < boxes.length; index++)
          level.distances[order[index]][boxes[index]],
      ];
      if (pushes.contains(null)) {
        continue;
      }
      final defined = pushes.nonNulls.toList();
      final total = defined.fold(0, (sum, count) => sum + count);
      if (best == null || total < best.total) {
        best = (order: order, pushes: defined, total: total);
      }
    }
    if (best == null) {
      emit('bound none');
      return;
    }
    emit('bound ${best.total}');
    for (var index = 0; index < boxes.length; index++) {
      final box = level.cellText(boxes[index]);
      final goal = level.cellText(level.goalCells[best.order[index]]);
      emit('box $box goal $goal pushes ${best.pushes[index]}');
    }
  }

  void save(List<String> arguments) {
    final name = arguments[0];
    snapshots[name] = (position: current, history: [...history]);
    emit('saved $name moves ${history.length}');
  }

  void restore(List<String> arguments) {
    final name = arguments[0];
    final snapshot = snapshots[name];
    if (snapshot == null) {
      throw CommandException('no snapshot $name');
    }
    current = snapshot.position;
    history = [...snapshot.history];
    redoList = [];
    emit('restored $name moves ${history.length}');
  }

  void check(List<String> arguments) {
    final simulation = simulate(stepSequence(arguments[0]));
    final failure = simulation.failure;
    if (failure != null) {
      emit('check fail $failure');
      return;
    }
    final letters = simulation.letters;
    emit(
      'check ok moves ${letters.length} pushes ${pushCount(letters)} '
      '${progress(simulation.position.boxes)}',
    );
  }

  void solve(List<String> arguments) {
    final (summary, notation) = searchSolution(int.parse(arguments[0]));
    emit(summary);
    solution = null;
    if (notation != null) {
      emit(notation);
      solution = (notation: notation, position: current);
    }
  }

  void hint(List<String> arguments) {
    final (summary, notation) = searchSolution(int.parse(arguments[0]));
    if (notation == null) {
      emit(summary);
      return;
    }
    final end = notation.split('').indexWhere(isPush);
    final part = notation.substring(0, end + 1);
    takeSteps(part.toLowerCase());
    emit('hint $part');
  }

  void play(List<String> arguments) {
    final stored = solution;
    if (stored == null || !stored.position.same(current)) {
      throw CommandException('no solution');
    }
    final notation = stored.notation;
    takeSteps(notation.toLowerCase());
    emit(
      'played pushes ${pushCount(notation.split(''))} moves ${notation.length}',
    );
  }

  void transform(List<String> arguments) {
    final kind = arguments[0];
    final old = level;
    level = old.transformed(kind);
    initial = old.mapPosition(kind, initial);
    current = old.mapPosition(kind, current);
    history = turnLetters(history, kind);
    redoList = turnLetters(redoList, kind);
    snapshots.updateAll(
      (name, snapshot) => (
        position: old.mapPosition(kind, snapshot.position),
        history: turnLetters(snapshot.history, kind),
      ),
    );
    final stored = solution;
    if (stored != null) {
      solution = (
        notation: turnLetters(stored.notation.split(''), kind).join(),
        position: old.mapPosition(kind, stored.position),
      );
    }
    emit('transformed ${level.height}x${level.width}');
  }

  void checkValues(String name, List<String> arguments) {
    final cells = cellCounts[name] ?? 0;
    for (var index = 0; index < 2 * cells; index += 2) {
      final row = int.parse(arguments[index]);
      final column = int.parse(arguments[index + 1]);
      if (!level.contains(row, column)) {
        throw CommandException('bad value');
      }
    }
    if ((name == 'UNDO' || name == 'REDO') && int.parse(arguments[0]) < 1) {
      throw CommandException('bad value');
    }
    if (name == 'SOLVE' || name == 'HINT') {
      final limit = int.parse(arguments[0]);
      if (limit < 1 || limit > maxLimit) {
        throw CommandException('bad value');
      }
    }
  }

  void runCommand(String name, List<String> arguments) {
    final kinds = commands[name];
    if (kinds == null) {
      throw CommandException('unknown command $name');
    }
    if (arguments.length != kinds.length ||
        !Iterable<int>.generate(kinds.length)
            .every((index) => validArgument(kinds[index], arguments[index]))) {
      throw CommandException('bad arguments');
    }
    if (!levelFreeCommands.contains(name)) {
      if (level.reason != null) {
        throw CommandException('invalid level');
      }
      checkValues(name, arguments);
    }
    handlers[name]!(arguments);
  }

  void execute(List<String> words, List<String> rows) {
    try {
      if (words[0] == 'LOAD') {
        loadRows(int.parse(words[2]), rows);
      } else {
        runCommand(words[0], words.sublist(1));
      }
    } on CommandException catch (error) {
      emit('error: ${error.message}');
    }
  }
}

List<String> readRows(int count) => [
  for (var index = 0; index < count; index++) stdin.readLineSync()!,
];

void main() {
  final height = int.parse(stdin.readLineSync()!.split(' ')[0]);
  final game = Sokoban(readRows(height));
  final count = int.parse(stdin.readLineSync()!.trim());
  for (var index = 0; index < count; index++) {
    final words = stdin.readLineSync()!.split(' ');
    final rows = words[0] == 'LOAD'
        ? readRows(int.parse(words[1]))
        : <String>[];
    game.execute(words, rows);
  }
  stdout.write(game.output);
}
