import 'dart:convert';
import 'dart:io';

typedef Move = ({String letter, int amount});
typedef Permutation = List<int>;
typedef PieceState = ({List<int> pieces, List<int> orientations});
typedef CubeSave = ({List<String> state, List<Move> history});
const faces = 'URFDLB';
const colors = 'WRGYOB';
const letters = 'UDFBLRMESudfblrxyz';
const cornerNames = ['URF', 'UFL', 'ULB', 'UBR', 'DFR', 'DLF', 'DBL', 'DRB'];
const edgeNames = ['UR', 'UF', 'UL', 'UB', 'DR', 'DF', 'DL', 'DB', 'FR', 'FL', 'BL', 'BR'];
const cornerStickers = ['U9 R1 F3', 'U7 F1 L3', 'U1 L1 B3', 'U3 B1 R3', 'D3 F9 R7', 'D1 L9 F7', 'D7 B9 L7', 'D9 R9 B7'];
const edgeStickers = ['U6 R2', 'U8 F2', 'U4 L2', 'U2 B2', 'D6 R8', 'D2 F8', 'D4 L8', 'D8 B8', 'F6 R4', 'F4 L6', 'B6 L4', 'B4 R6'];
Permutation identity() => List.generate(54, (index) => index);
List<String> solvedState() => colors.split('').expand((color) => List.filled(9, color)).toList();
String axis(String letter) => 'RLMrlx'.contains(letter) ? 'x' : 'UDEudy'.contains(letter) ? 'y' : 'z';
String moveText(Move move) => move.letter + (move.amount == 2 ? '2' : move.amount == 3 ? "'" : '');
String sequenceText(List<Move> moves) => '${moves.length}${moves.isEmpty ? '' : ' ${moves.map(moveText).join(' ')}'}';
List<Move> inverse(List<Move> moves) => moves.reversed.map((move) => (letter: move.letter, amount: 4 - move.amount)).toList();
int sticker(String face, int row, int column) => faces.indexOf(face) * 9 + (row - 1) * 3 + column - 1;
List<int> indices(String text) => text.split(' ').map((word) => faces.indexOf(word[0]) * 9 + int.parse(word.substring(1)) - 1).toList();
final cornerIndices = cornerStickers.map(indices).toList();
final edgeIndices = edgeStickers.map(indices).toList();
final centerIndices = List.generate(6, (face) => [face * 9 + 4]);
Permutation compose(Permutation first, Permutation second) => first.map((destination) => second[destination]).toList();
Permutation inversePermutation(Permutation permutation) {
  final result = identity();
  for (var source = 0; source < 54; source++) result[permutation[source]] = source;
  return result;
}
List<String> applyPermutation(List<String> state, Permutation permutation) {
  final result = state.toList();
  for (var source = 0; source < 54; source++) result[permutation[source]] = state[source];
  return result;
}

Map<String, Permutation> buildMoves() {
  final quarter = <String, Permutation>{};
  for (final letter in 'URFDLBMES'.split('')) {
    final permutation = identity();
    void put(String from, int i, int j, String to, int row, int column) {
      permutation[sticker(from, i, j)] = sticker(to, row, column);
    }
    if (faces.contains(letter)) {
      for (var i = 1; i <= 3; i++) {
        for (var j = 1; j <= 3; j++) put(letter, i, j, letter, j, 4 - i);
      }
    }
    for (var n = 1; n <= 3; n++) {
      switch (letter) {
        case 'U': put('F', 1, n, 'L', 1, n); put('L', 1, n, 'B', 1, n); put('B', 1, n, 'R', 1, n); put('R', 1, n, 'F', 1, n);
        case 'R': put('F', n, 3, 'U', n, 3); put('U', n, 3, 'B', 4 - n, 1); put('B', n, 1, 'D', 4 - n, 3); put('D', n, 3, 'F', n, 3);
        case 'F': put('U', 3, n, 'R', n, 1); put('R', n, 1, 'D', 1, 4 - n); put('D', 1, n, 'L', n, 3); put('L', n, 3, 'U', 3, 4 - n);
        case 'D': put('F', 3, n, 'R', 3, n); put('R', 3, n, 'B', 3, n); put('B', 3, n, 'L', 3, n); put('L', 3, n, 'F', 3, n);
        case 'L': put('U', n, 1, 'F', n, 1); put('F', n, 1, 'D', n, 1); put('D', n, 1, 'B', 4 - n, 3); put('B', n, 3, 'U', 4 - n, 1);
        case 'B': put('U', 1, n, 'L', 4 - n, 1); put('L', n, 1, 'D', 3, n); put('D', 3, n, 'R', 4 - n, 3); put('R', n, 3, 'U', 1, n);
        case 'M': put('U', n, 2, 'F', n, 2); put('F', n, 2, 'D', n, 2); put('D', n, 2, 'B', 4 - n, 2); put('B', n, 2, 'U', 4 - n, 2);
        case 'E': put('F', 2, n, 'R', 2, n); put('R', 2, n, 'B', 2, n); put('B', 2, n, 'L', 2, n); put('L', 2, n, 'F', 2, n);
        case 'S': put('U', 2, n, 'R', n, 2); put('R', n, 2, 'D', 2, 4 - n); put('D', 2, n, 'L', n, 2); put('L', n, 2, 'U', 2, 4 - n);
      }
    }
    quarter[letter] = permutation;
  }
  const definitions = {'r': "R M'", 'l': 'L M', 'u': "U E'", 'd': 'D E', 'f': 'F S', 'b': "B S'", 'x': "R M' L'", 'y': "U E' D'", 'z': "F S B'"};
  for (final entry in definitions.entries) {
    var permutation = identity();
    for (final word in entry.value.split(' ')) {
      final base = quarter[word[0]]!;
      permutation = compose(permutation, word.endsWith("'") ? inversePermutation(base) : base);
    }
    quarter[entry.key] = permutation;
  }
  final result = <String, Permutation>{};
  for (final letter in letters.split('')) {
    var permutation = identity();
    for (var amount = 1; amount <= 3; amount++) {
      permutation = compose(permutation, quarter[letter]!);
      result[moveText((letter: letter, amount: amount))] = permutation;
    }
  }
  return result;
}
final movePermutations = buildMoves();
Permutation effect(List<Move> moves) => moves.fold<Permutation>(identity(), (permutation, move) => compose(permutation, movePermutations[moveText(move)]!));
List<Move> basicSequence(String text) => text.isEmpty ? [] : text.split(' ').map((word) => (letter: word[0], amount: word.endsWith('2') ? 2 : word.endsWith("'") ? 3 : 1)).toList();
final rotations = ['', 'y', 'y2', "y'", 'x', 'x y', 'x y2', "x y'", 'x2', 'x2 y', 'x2 y2', "x2 y'", "x'", "x' y", "x' y2", "x' y'", 'z', 'z y', 'z y2', "z y'", "z'", "z' y", "z' y2", "z' y'"].map(basicSequence).toList();
final rotationEffects = rotations.map(effect).toList();

({List<String> state, int rotation})? normalize(List<String> state) {
  for (var index = 0; index < rotations.length; index++) {
    final rotated = applyPermutation(state, rotationEffects[index]);
    if (List.generate(6, (face) => rotated[face * 9 + 4] == colors[face]).every((correct) => correct)) return (state: rotated, rotation: index);
  }
  return null;
}

PieceState identify(List<String> state, List<String> names, List<List<int>> positions) {
  final pieces = <int>[];
  final orientations = <int>[];
  for (final position in positions) {
    final current = position.map((index) => state[index]).toList();
    var found = -1;
    var twist = 0;
    for (var piece = 0; piece < names.length && found < 0; piece++) {
      final expected = names[piece].split('').map((face) => colors[faces.indexOf(face)]).toList();
      for (var orientation = 0; orientation < current.length; orientation++) {
        var equal = true;
        for (var i = 0; i < expected.length; i++) {
          if (current[(orientation + i) % current.length] != expected[i]) equal = false;
        }
        if (equal) { found = piece; twist = orientation; break; }
      }
    }
    pieces.add(found);
    orientations.add(twist);
  }
  return (pieces: pieces, orientations: orientations);
}

String cycles(List<String> state, List<String> names, List<List<int>> positions) {
  final data = identify(state, names, positions);
  final destination = List.filled(names.length, 0);
  for (var position = 0; position < names.length; position++) destination[data.pieces[position]] = position;
  final seen = <int>{};
  final result = <String>[];
  for (var start = 0; start < names.length; start++) {
    if (seen.contains(start)) continue;
    final cycle = <String>[];
    var current = start;
    var orientation = 0;
    do {
      seen.add(current); cycle.add(names[current]);
      current = destination[current]; orientation += data.orientations[current];
    } while (current != start);
    final remainder = orientation % positions[0].length;
    final mark = remainder == 0 ? '' : remainder == 1 ? '+' : '-';
    if (cycle.length > 1 || mark.isNotEmpty) result.add('(${cycle.join(' ')})$mark');
  }
  return result.isEmpty ? 'none' : result.join(' ');
}
int parity(List<int> pieces) {
  var count = 0;
  for (var i = 0; i < pieces.length; i++) {
    for (var j = i + 1; j < pieces.length; j++) {
      if (pieces[i] > pieces[j]) count++;
    }
  }
  return count % 2;
}
String? invalidState(String text) {
  if (text.length != 54) return 'length ${text.length}';
  final state = text.split('');
  final bad = state.indexWhere((color) => !colors.contains(color));
  if (bad >= 0) return 'char ${bad + 1}';
  for (final color in colors.split('')) {
    final count = state.where((value) => value == color).length;
    if (count != 9) return 'count $color $count';
  }
  final normalized = normalize(state);
  if (normalized == null) return 'centers';
  final corners = identify(state, cornerNames, cornerIndices);
  final edges = identify(state, edgeNames, edgeIndices);
  if (corners.pieces.contains(-1)) return 'corner ${cornerNames[corners.pieces.indexOf(-1)]}';
  if (edges.pieces.contains(-1)) return 'edge ${edgeNames[edges.pieces.indexOf(-1)]}';
  for (var piece = 0; piece < 8; piece++) {
    if (!corners.pieces.contains(piece)) return 'missing ${cornerNames[piece]}';
  }
  for (var piece = 0; piece < 12; piece++) {
    if (!edges.pieces.contains(piece)) return 'missing ${edgeNames[piece]}';
  }
  final normalCorners = identify(normalized.state, cornerNames, cornerIndices);
  final normalEdges = identify(normalized.state, edgeNames, edgeIndices);
  if (normalCorners.orientations.fold<int>(0, (a, b) => a + b) % 3 != 0) return 'twist';
  if (normalEdges.orientations.fold<int>(0, (a, b) => a + b) % 2 != 0) return 'flip';
  return parity(normalCorners.pieces) == parity(normalEdges.pieces) ? null : 'parity';
}
int mismatch(List<String> state) => List.generate(54, (index) => state[index] != state[(index ~/ 9) * 9 + 4] ? 1 : 0).fold<int>(0, (a, b) => a + b);
List<Move> simplify(List<Move> moves) {
  var current = moves;
  while (true) {
    final result = <Move>[];
    for (var start = 0; start < current.length;) {
      var end = start;
      final sums = <String, int>{};
      while (end < current.length && axis(current[end].letter) == axis(current[start].letter)) {
        final move = current[end++];
        sums[move.letter] = (sums[move.letter] ?? 0) + move.amount;
      }
      for (final entry in sums.entries) {
        if (entry.value % 4 != 0) result.add((letter: entry.key, amount: entry.value % 4));
      }
      start = end;
    }
    if (sequenceText(result) == sequenceText(current)) return result;
    current = result;
  }
}
Move matchingMove(Permutation permutation, [bool outerOnly = false]) {
  for (final letter in (outerOnly ? faces : letters).split('')) {
    for (var amount = 1; amount <= 3; amount++) {
      final move = (letter: letter, amount: amount);
      final candidate = movePermutations[moveText(move)]!;
      if (List.generate(54, (i) => candidate[i] == permutation[i]).every((equal) => equal)) return move;
    }
  }
  throw StateError('move effect unavailable');
}
Move conjugate(Move move, Permutation rotation, [bool outerOnly = false]) => matchingMove(compose(compose(rotation, movePermutations[moveText(move)]!), inversePermutation(rotation)), outerOnly);
List<Move> unrotate(List<Move> moves) {
  const replacements = {'M': "R L' x'", 'E': "U D' y'", 'S': "F' B z", 'r': 'L x', 'l': "R x'", 'u': 'D y', 'd': "U y'", 'f': 'B z', 'b': "F z'"};
  final result = <Move>[];
  var rotation = identity();
  for (final move in moves) {
    final replacement = replacements[move.letter];
    final expanded = replacement == null ? [move] : basicSequence(replacement).map((part) => (letter: part.letter, amount: part.amount * move.amount % 4)).toList();
    for (final part in expanded) {
      if ('xyz'.contains(part.letter)) {
        rotation = compose(rotation, movePermutations[moveText(part)]!);
      } else {
        result.add(conjugate(part, rotation, true));
      }
    }
  }
  final index = rotationEffects.indexWhere((candidate) => List.generate(54, (i) => candidate[i] == rotation[i]).every((equal) => equal));
  return [...result, ...rotations[index]];
}
int gcd(int a, int b) {
  while (b != 0) { final remainder = a % b; a = b; b = remainder; }
  return a;
}
int order(Permutation permutation) {
  final seen = <int>{};
  var result = 1;
  for (var start = 0; start < 54; start++) {
    if (seen.contains(start)) continue;
    var current = start;
    var length = 0;
    do { seen.add(current); current = permutation[current]; length++; } while (current != start);
    result = result ~/ gcd(result, length) * length;
  }
  return result;
}

class CubeFailure implements Exception {
  final String message;
  CubeFailure(this.message);
}
class SequenceParser {
  final String line;
  int position;
  final Map<String, List<Move>> macros;
  SequenceParser(this.line, this.position, this.macros);
  String current() => position < line.length ? line[position] : '';
  void spaces() { while (current() == ' ') position++; }
  Never syntax() => throw CubeFailure('syntax at ${(position < line.length ? position : line.length) + 1}');
  List<Move> power(List<Move> moves) {
    var count = 1;
    if (RegExp(r'^[1-9]$').hasMatch(current())) {
      count = int.parse(current()); position++;
      if (RegExp(r'^[0-9]$').hasMatch(current())) { count = count * 10 + int.parse(current()); position++; }
    }
    final invert = current() == "'";
    if (invert) position++;
    final result = <Move>[];
    for (var i = 0; i < count; i++) result.addAll(moves);
    return invert ? inverse(result) : result;
  }
  List<Move> sequence() {
    final result = <Move>[];
    while (true) {
      spaces(); final char = current();
      if (char.isNotEmpty && letters.contains(char)) {
        position++; var amount = 1;
        if (current() == '2') { amount = 2; position++; }
        else if (current() == "'") { amount = 3; position++; }
        result.add((letter: char, amount: amount));
      } else if (char == '(') {
        position++; final group = sequence(); spaces();
        if (current() != ')') syntax();
        position++; result.addAll(power(group));
      } else if (char == '[') {
        position++; final left = sequence(); spaces(); final separator = current();
        if (separator != ',' && separator != ':') syntax();
        position++; final right = sequence(); spaces();
        if (current() != ']') syntax();
        position++;
        result.addAll(power([...left, ...right, ...inverse(left), if (separator == ',') ...inverse(right)]));
      } else if (char == '{') {
        position++; final start = position;
        while (RegExp(r'^[a-z]$').hasMatch(current())) position++;
        final name = line.substring(start, position);
        if (name.isEmpty || current() != '}') syntax();
        final macro = macros[name];
        if (macro == null) throw CubeFailure('undefined $name');
        position++; result.addAll(power(macro));
      } else {
        return result;
      }
    }
  }
  List<Move> parse() {
    final result = sequence(); spaces();
    if (current().isNotEmpty) syntax();
    if (result.length > 500) throw CubeFailure('too long');
    return result;
  }
}

class Cube {
  List<String> state = solvedState();
  List<Move> history = [];
  List<Move> redo = [];
  final Map<String, List<Move>> macros = {};
  final Map<String, CubeSave> saves = {};
  final List<String> output = [];

  List<Move>? search(int depth) {
    List<Move>? visit(List<String> state, int remaining, String previous) {
      if (remaining == 0) return mismatch(state) == 0 ? [] : null;
      for (final face in faces.split('')) {
        if (face == previous || previous == 'D' && face == 'U' || previous == 'L' && face == 'R' || previous == 'B' && face == 'F') continue;
        for (final amount in [1, 2, 3]) {
          final move = (letter: face, amount: amount);
          final tail = visit(applyPermutation(state, movePermutations[moveText(move)]!), remaining - 1, face);
          if (tail != null) return [move, ...tail];
        }
      }
      return null;
    }
    for (var limit = 0; limit <= depth; limit++) {
      final result = visit(state, limit, '');
      if (result != null) return result;
    }
    return null;
  }
  void apply(List<Move> moves) {
    state = applyPermutation(state, effect(moves)); history.addAll(moves); redo = [];
  }
  void execute(String line) {
    final space = line.indexOf(' ');
    final command = space < 0 ? line : line.substring(0, space);
    final argument = space < 0 ? null : line.substring(space + 1);
    const noArguments = {'RESET', 'SHOW', 'STATE', 'ISSOLVED', 'HISTORY', 'SOLUTION', 'ANALYZE', 'STAGE', 'MACROS'};
    const wordCommands = {'CHECK': 1, 'LOAD': 1, 'UNDO': 1, 'REDO': 1, 'SEARCH': 1, 'WHERE': 1, 'SAVE': 1, 'RESTORE': 1, 'SCRAMBLE': 2};
    const sequenceCommands = {'APPLY', 'INVERT', 'SIMPLIFY', 'METRICS', 'ORDER', 'CYCLES', 'UNROTATE', 'UNTIL'};
    const headCommands = {'DEFINE', 'MIRROR', 'ROTATE'};
    if (!noArguments.contains(command) && !wordCommands.containsKey(command) && !sequenceCommands.contains(command) && !headCommands.contains(command)) throw CubeFailure('unknown command $command');
    final words = argument == null ? <String>[] : argument.split(' ');
    if (noArguments.contains(command) && argument != null || wordCommands.containsKey(command) && words.length != wordCommands[command]) throw CubeFailure('bad arguments');
    if (['UNDO', 'REDO', 'SEARCH', 'SCRAMBLE'].contains(command) && !words.every((word) => RegExp(r'^(?:0|[1-9][0-9]{0,9})$').hasMatch(word))) throw CubeFailure('bad arguments');
    if (['SAVE', 'RESTORE'].contains(command) && !RegExp(r'^[a-z]{1,8}$').hasMatch(words[0])) throw CubeFailure('bad arguments');
    if (headCommands.contains(command) && (argument == null || command == 'DEFINE' && !RegExp(r'^[a-z]{1,8}$').hasMatch(words[0]) || command == 'MIRROR' && !['LR', 'UD', 'FB'].contains(words[0]) || command == 'ROTATE' && !RegExp(r"^[xyz](?:2|')?$").hasMatch(words[0]))) throw CubeFailure('bad arguments');
    List<Move> moves = [];
    if (sequenceCommands.contains(command)) {
      moves = SequenceParser(line, space < 0 ? line.length : space + 1, macros).parse();
    } else if (headCommands.contains(command)) {
      moves = SequenceParser(line, space + 1 + words[0].length + 1, macros).parse();
    }
    if (['UNDO', 'REDO'].contains(command) && int.parse(words[0]) < 1 || command == 'SEARCH' && int.parse(words[0]) > 4 || command == 'SCRAMBLE' && (int.parse(words[0]) < 1 || int.parse(words[0]) > 50 || int.parse(words[1]) < 1 || int.parse(words[1]) > 2147483646)) throw CubeFailure('bad value');
    if (command == 'WHERE' && !cornerNames.contains(words[0]) && !edgeNames.contains(words[0])) throw CubeFailure('unknown piece ${words[0]}');
    switch (command) {
      case 'RESET': state = solvedState(); history = []; redo = []; output.add('reset');
      case 'STATE': output.add('state ${state.join()}');
      case 'ISSOLVED': final count = mismatch(state); output.add(count == 0 ? 'solved' : 'unsolved $count');
      case 'HISTORY': output.add('history ${sequenceText(history)}');
      case 'SOLUTION': output.add('solution ${sequenceText(simplify(inverse(history)))}');
      case 'SHOW':
        String row(String face, int index) => state.sublist(faces.indexOf(face) * 9 + index * 3, faces.indexOf(face) * 9 + index * 3 + 3).join(' ');
        for (var i = 0; i < 3; i++) output.add('      ${row('U', i)}');
        for (var i = 0; i < 3; i++) output.add(['L', 'F', 'R', 'B'].map((face) => row(face, i)).join(' '));
        for (var i = 0; i < 3; i++) output.add('      ${row('D', i)}');
      case 'MACROS':
        output.add('macros ${macros.length}');
        final names = macros.keys.toList()..sort();
        for (final name in names) output.add('macro $name ${sequenceText(macros[name]!)}');
      case 'CHECK': case 'LOAD':
        final reason = invalidState(words[0]);
        if (command == 'CHECK') {
          output.add(reason == null ? 'valid' : 'invalid $reason');
        } else {
          if (reason != null) throw CubeFailure('invalid $reason');
          state = words[0].split(''); history = []; redo = []; output.add('loaded');
        }
      case 'UNDO': case 'REDO':
        final source = command == 'UNDO' ? history : redo;
        final target = command == 'UNDO' ? redo : history;
        if (source.isEmpty) throw CubeFailure(command == 'UNDO' ? 'nothing to undo' : 'nothing to redo');
        final requested = int.parse(words[0]);
        final count = requested < source.length ? requested : source.length;
        for (var i = 0; i < count; i++) {
          final move = source.removeLast();
          state = applyPermutation(state, effect(command == 'UNDO' ? inverse([move]) : [move])); target.add(move);
        }
        output.add('${command == 'UNDO' ? 'undone' : 'redone'} $count');
      case 'SAVE': saves[words[0]] = (state: state.toList(), history: history.toList()); output.add('saved ${words[0]}');
      case 'RESTORE':
        final save = saves[words[0]];
        if (save == null) throw CubeFailure('no save ${words[0]}');
        state = save.state.toList(); history = save.history.toList(); redo = []; output.add('restored ${words[0]}');
      case 'SEARCH': final solution = search(int.parse(words[0])); output.add(solution == null ? 'not found' : 'found ${sequenceText(solution)}');
      case 'ANALYZE': case 'WHERE': case 'STAGE':
        final normalized = normalize(state)!;
        final corners = identify(normalized.state, cornerNames, cornerIndices);
        final edges = identify(normalized.state, edgeNames, edgeIndices);
        if (command == 'ANALYZE') {
          final rotation = rotations[normalized.rotation];
          output.add('rotation ${rotation.isEmpty ? 'none' : rotation.map(moveText).join(' ')}');
          output.add('corners ${cycles(normalized.state, cornerNames, cornerIndices)}');
          output.add('edges ${cycles(normalized.state, edgeNames, edgeIndices)}');
        } else if (command == 'WHERE') {
          final corner = cornerNames.contains(words[0]);
          final names = corner ? cornerNames : edgeNames;
          final data = corner ? corners : edges;
          final at = data.pieces.indexOf(names.indexOf(words[0]));
          output.add('${words[0]} at ${names[at]} ${corner ? 'twist' : 'flip'} ${data.orientations[at]}');
        } else {
          bool correct(PieceState data, int index) => data.pieces[index] == index && data.orientations[index] == 0;
          final cross = [4, 5, 6, 7].where((index) => correct(edges, index)).length;
          final slots = [4, 5, 6, 7].where((index) => correct(corners, index) && correct(edges, index + 4)).length;
          final top = normalized.state.take(9).where((color) => color == 'W').length;
          final stage = mismatch(normalized.state) == 0 ? 'solved' : cross == 4 && slots == 4 ? top == 9 ? 'oll' : 'f2l' : cross == 4 ? 'cross' : 'none';
          output.add('stage $stage cross $cross slots $slots top $top');
        }
      case 'SCRAMBLE':
        var random = int.parse(words[1]);
        int next() => random = random * 48271 % 2147483647;
        final scramble = <Move>[];
        for (var i = 0; i < int.parse(words[0]); i++) {
          final previous = i >= 1 ? scramble[i - 1].letter : null;
          final before = i >= 2 ? scramble[i - 2].letter : null;
          final usable = faces.split('').where((face) => face != previous && !(before != null && previous != null && axis(before) == axis(previous) && axis(face) == axis(previous))).toList();
          final letter = usable[next() % usable.length];
          final amount = [1, 3, 2][next() % 3];
          scramble.add((letter: letter, amount: amount));
        }
        apply(scramble); output.add('scramble ${scramble.map(moveText).join(' ')}');
      case 'APPLY': apply(moves); output.add('applied ${moves.length}');
      case 'DEFINE': macros[words[0]] = moves.toList(); output.add('defined ${words[0]} ${moves.length}');
      case 'INVERT': output.add('inverse ${sequenceText(inverse(moves))}');
      case 'SIMPLIFY': output.add('simplified ${sequenceText(simplify(moves))}');
      case 'UNROTATE': output.add('unrotated ${sequenceText(unrotate(moves))}');
      case 'ROTATE':
        final rotation = effect(basicSequence(words[0]));
        output.add('rotated ${sequenceText(moves.map((move) => conjugate(move, rotation)).toList())}');
      case 'MIRROR':
        final mirrorAxis = words[0] == 'LR' ? 'x' : words[0] == 'UD' ? 'y' : 'z';
        const opposites = {'R': 'L', 'L': 'R', 'r': 'l', 'l': 'r', 'U': 'D', 'D': 'U', 'u': 'd', 'd': 'u', 'F': 'B', 'B': 'F', 'f': 'b', 'b': 'f'};
        final mirrored = moves.map((move) => axis(move.letter) != mirrorAxis ? (letter: move.letter, amount: 4 - move.amount) : opposites.containsKey(move.letter) ? (letter: opposites[move.letter]!, amount: 4 - move.amount) : move).toList();
        output.add('mirror ${sequenceText(mirrored)}');
      case 'METRICS':
        var htm = 0; var qtm = 0; var stm = 0;
        for (final move in moves) {
          if ('xyz'.contains(move.letter)) continue;
          final weight = 'MES'.contains(move.letter) ? 2 : 1;
          htm += weight; qtm += weight * (move.amount == 2 ? 2 : 1); stm++;
        }
        output.add('metrics htm $htm qtm $qtm stm $stm etm ${moves.length}');
      case 'ORDER': output.add('order ${order(effect(moves))}');
      case 'CYCLES':
        final state = applyPermutation(solvedState(), effect(moves));
        output.add('corners ${cycles(state, cornerNames, cornerIndices)}');
        output.add('edges ${cycles(state, edgeNames, edgeIndices)}');
        output.add('centers ${cycles(state, faces.split(''), centerIndices)}');
      case 'UNTIL':
        final permutation = effect(moves); var candidate = state; var found = 0;
        for (var i = 1; i <= order(permutation); i++) {
          candidate = applyPermutation(candidate, permutation);
          if (mismatch(candidate) == 0) { found = i; break; }
        }
        output.add(found == 0 ? 'until never' : 'until $found');
    }
  }
  void run(List<String> lines) {
    for (final line in lines.skip(1).take(int.parse(lines[0]))) {
      try { execute(line); } on CubeFailure catch (error) { output.add('error: ${error.message}'); }
    }
  }
}
Future<void> main() async {
  final cube = Cube();
  cube.run((await stdin.transform(utf8.decoder).join()).split('\n'));
  stdout.write('${cube.output.join('\n')}\n');
}
