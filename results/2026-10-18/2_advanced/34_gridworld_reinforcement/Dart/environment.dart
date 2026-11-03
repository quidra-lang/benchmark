part of 'main.dart';

const actionLetters = 'NESW';
const rowSteps = [-1, 0, 1, 0], colSteps = [0, 1, 0, -1];
List<String> readLines(String path) => File(path).readAsLinesSync();

class World {
  final int rows, cols;
  final String kinds;
  final List<int> wind, rewards;
  final states = <int>[], terminals = <int>[];
  late final List<int> stateIndex, terminalIndex;
  late final int start, startState;
  World(this.rows, this.cols, this.kinds, this.wind, this.rewards) {
    stateIndex = List.filled(kinds.length, -1);
    terminalIndex = List.filled(kinds.length, -1);
    for (var cell = 0; cell < kinds.length; cell++) {
      final kind = kinds[cell];
      if (kind == 'G' || kind == 'P') {
        terminalIndex[cell] = terminals.length;
        terminals.add(cell);
      } else if (kind != '#') {
        stateIndex[cell] = states.length;
        states.add(cell);
      }
    }
    start = kinds.indexOf('S');
    startState = stateIndex[start];
  }
  bool isTerminal(int cell) => terminalIndex[cell] >= 0;
  String terminalName(int cell) => kinds[cell] == 'G' ? 'goal' : 'pit';
  int move(int cell, int direction) {
    var target = cell + rowSteps[direction] * cols + colSteps[direction];
    if (kinds[target] == '#') target = cell;
    if (isTerminal(target)) return target;
    for (var i = 0; i < wind[cell % cols]; i++) {
      final above = target - cols;
      if (kinds[above] == '#') break;
      target = above;
      if (isTerminal(target)) break;
    }
    return target;
  }
}

World readWorld() {
  final lines = readLines('input/world.txt'),
      rows = int.parse(lines[0].split(' ')[1]),
      cols = int.parse(lines[1].split(' ')[1]);
  return World(
    rows,
    cols,
    lines.sublist(2, 2 + rows).join(),
    lines[2 + rows].split(' ')[1].split('').map(int.parse).toList(),
    lines[3 + rows].split(' ').skip(1).map(int.parse).toList(),
  );
}

class RandomGenerator {
  int value;
  RandomGenerator(this.value);
  int draw() {
    value = value * 48271 % 2147483647;
    return value;
  }
}

class Environment {
  final World world;
  final int stepReward, slipTotal, floorSlip, iceSlip;
  late final List<List<int>> moves;
  late final List<List<List<(int, int)>>> transitions;
  Environment(
    this.world,
    this.stepReward,
    this.slipTotal,
    this.floorSlip,
    this.iceSlip,
  ) {
    moves = [
      for (final cell in world.states)
        [for (var d = 0; d < 4; d++) world.move(cell, d)],
    ];
    transitions = [
      for (var s = 0; s < world.states.length; s++)
        [
          for (var a = 0; a < 4; a++)
            [
              for (final (d, weight) in [
                (a, slipTotal - 2 * slip(s)),
                ((a + 1) % 4, slip(s)),
                ((a + 3) % 4, slip(s)),
              ])
                if (weight > 0) (moves[s][d], weight),
            ],
        ],
    ];
  }
  int slip(int s) => world.kinds[world.states[s]] == '~' ? iceSlip : floorSlip;
  int reward(int cell) => world.isTerminal(cell)
      ? world.rewards[world.terminalIndex[cell]]
      : stepReward;
  (int, int) step(RandomGenerator g, int state, int action) {
    final draw = g.draw() % slipTotal, p = slip(state);
    final direction = draw < slipTotal - 2 * p
        ? action
        : draw < slipTotal - p
        ? (action + 1) % 4
        : (action + 3) % 4;
    final cell = moves[state][direction];
    return (cell, reward(cell));
  }
}
