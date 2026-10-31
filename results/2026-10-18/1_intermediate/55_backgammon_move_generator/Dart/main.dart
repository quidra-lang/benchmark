import 'dart:io';

const colors = ['W', 'B'];
const results = ['single', 'gammon', 'backgammon', 'drop'];
const strategies = ['BEST', 'FIRST', 'RANDOM'];

class Failure implements Exception {
  final String message;
  Failure(this.message);
}

Never fail(String message) => throw Failure(message);
void requireValue(bool valid, [String message = 'bad arguments']) {
  if (!valid) fail(message);
}

int number(String text, int low, int high, [String message = 'bad arguments']) {
  requireValue(RegExp(r'^[0-9]+$').hasMatch(text), message);
  final n = int.tryParse(text);
  if (n == null || n < low || n > high) fail(message);
  return n;
}

class Position {
  final List<List<int>> men;
  Position([List<List<int>>? values])
    : men = values ?? List.generate(2, (_) => List.filled(26, 0));
  factory Position.initial() {
    final p = Position();
    for (int c = 0; c < 2; c++) {
      p.men[c][24] = 2;
      p.men[c][13] = 5;
      p.men[c][8] = 3;
      p.men[c][6] = 5;
    }
    return p;
  }
  Position copy() => Position(men.map((v) => List<int>.of(v)).toList());
  String key() => '${men[0].join(',')};${men[1].join(',')}';
  int board(int p) => men[0][p] - men[1][25 - p];
  int opposing(int c, int p) => men[1 - c][25 - p];
  int pips(int c) {
    int total = 0;
    for (int p = 1; p <= 25; p++) {
      total += p * men[c][p];
    }
    return total;
  }

  int keith(int c) {
    final v = men[c];
    int extra(int n) => n > 0 ? n : 0;
    int total =
        pips(c) + 2 * extra(v[1] - 1) + extra(v[2] - 1) + extra(v[3] - 3);
    for (int p = 4; p <= 6; p++) {
      if (v[p] == 0) total++;
    }
    return total;
  }

  int rear(int c) {
    for (int p = 25; p > 0; p--) {
      if (men[c][p] > 0) return p;
    }
    return 0;
  }

  bool contact() => rear(0) + rear(1) > 25;
  bool home(int c) {
    for (int p = 7; p <= 25; p++) {
      if (men[c][p] > 0) return false;
    }
    return true;
  }

  List<int> starts(int c) => men[c][25] > 0
      ? [25]
      : [
          for (int p = 24; p > 0; p--)
            if (men[c][p] > 0) p,
        ];
  Outcome? move(int c, int source, int die) {
    int target = source - die;
    bool hit = false;
    if (target >= 1) {
      if (opposing(c, target) >= 2) return null;
      hit = opposing(c, target) == 1;
    } else {
      if (!home(c)) return null;
      if (target < 0) {
        for (int p = source + 1; p <= 6; p++) {
          if (men[c][p] > 0) return null;
        }
      }
      target = 0;
    }
    final after = copy();
    after.men[c][source]--;
    after.men[c][target]++;
    if (hit) {
      after.men[1 - c][25 - target]--;
      after.men[1 - c][25]++;
    }
    return Outcome(after, target, hit);
  }
}

class Outcome {
  final Position position;
  final int target;
  final bool hit;
  Outcome(this.position, this.target, this.hit);
}

typedef Move = (int, int);
int moveOrder(Move a, Move b) {
  final c = b.$1.compareTo(a.$1);
  return c == 0 ? b.$2.compareTo(a.$2) : c;
}

String point(int p) => p == 25
    ? 'bar'
    : p == 0
    ? 'off'
    : p.toString();

class Sequence {
  final Position position;
  final List<Move> moves;
  final List<int> used;
  final Set<int> hits;
  Sequence(this.position, this.moves, this.used, this.hits);
}

class Play {
  final Position position;
  final Set<int> hits;
  final List<Move> key;
  late final String notation;
  Play(Sequence s)
    : position = s.position,
      hits = s.hits,
      key = List.of(s.moves) {
    key.sort(moveOrder);
    while (true) {
      int first = -1, second = -1;
      search:
      for (int i = 0; i < key.length; i++) {
        final middle = key[i].$2;
        if (middle < 1 || hits.contains(middle)) continue;
        for (int j = 0; j < key.length; j++) {
          if (key[j].$1 == middle) {
            first = i;
            second = j;
            break search;
          }
        }
      }
      if (first < 0) break;
      final merged = (key[first].$1, key[second].$2);
      key.removeAt(first > second ? first : second);
      key.removeAt(first < second ? first : second);
      key.add(merged);
      key.sort(moveOrder);
    }
    final List<String> elements = [];
    final Set<int> starred = {};
    int i = 0;
    while (i < key.length) {
      final m = key[i];
      int end = i + 1;
      while (end < key.length && key[end] == m) {
        end++;
      }
      String text = '${point(m.$1)}/${point(m.$2)}';
      if (hits.contains(m.$2) && starred.add(m.$2)) text += '*';
      if (end - i >= 2) text += '(${end - i})';
      elements.add(text);
      i = end;
    }
    notation = elements.isEmpty ? 'none' : elements.join(' ');
  }
}

int comparePlays(Play a, Play b) {
  for (int i = 0; i < a.key.length && i < b.key.length; i++) {
    final c = moveOrder(a.key[i], b.key[i]);
    if (c != 0) return c;
  }
  return b.key.length.compareTo(a.key.length);
}

class Generator {
  final int color;
  final List<Sequence> sequences = [];
  final Map<String, int> shortest = {};
  late final int maximum;
  late final List<Play> plays;
  Generator(Position position, this.color, int first, int second) {
    explore(
      position,
      first == second ? List.filled(4, first) : [first, second],
      [],
      [],
      {},
    );
    maximum = sequences
        .map((s) => s.moves.length)
        .reduce((a, b) => a > b ? a : b);
    final larger = first > second ? first : second;
    final largerRequired =
        maximum == 1 &&
        first != second &&
        sequences.any((s) => s.moves.length == 1 && s.used[0] == larger);
    final Set<String> seen = {};
    plays = sequences
        .where(
          (s) =>
              s.moves.length == maximum &&
              (!largerRequired || s.used[0] == larger) &&
              seen.add(s.position.key()),
        )
        .map(Play.new)
        .toList();
    plays.sort(comparePlays);
  }
  void explore(
    Position p,
    List<int> remaining,
    List<Move> moves,
    List<int> used,
    Set<int> hits,
  ) {
    final key = p.key(), previous = shortest[p.key()];
    if (previous == null || moves.length < previous)
      shortest[key] = moves.length;
    sequences.add(Sequence(p, moves, used, hits));
    final Set<int> tried = {};
    for (int i = 0; i < remaining.length; i++) {
      final die = remaining[i];
      if (!tried.add(die)) continue;
      final rest = List<int>.of(remaining)..removeAt(i);
      for (final source in p.starts(color)) {
        final outcome = p.move(color, source, die);
        if (outcome == null) continue;
        explore(
          outcome.position,
          rest,
          [...moves, (source, outcome.target)],
          [...used, die],
          {...hits, if (outcome.hit) outcome.target},
        );
      }
    }
  }
}

List<int> terms(Position p, int c) {
  final pip = p.pips(1 - c) - p.pips(c);
  int blots = 0, home = 0, prime = 0, run = 0, anchors = 0;
  for (int point = 1; point <= 24; point++) {
    if (p.men[c][point] == 1) {
      final Set<int> distances = {
        for (int q = 0; q < point; q++)
          if (p.opposing(c, q) > 0) point - q,
      };
      for (int a = 1; a <= 6; a++) {
        for (int b = 1; b <= 6; b++) {
          if (distances.contains(a) ||
              distances.contains(b) ||
              distances.contains(a + b) ||
              a == b &&
                  (distances.contains(3 * a) || distances.contains(4 * a)))
            blots++;
        }
      }
    }
    run = p.men[c][point] >= 2 ? run + 1 : 0;
    if (run > prime) prime = run;
    if (p.men[c][point] >= 2 && point <= 6) home++;
    if (p.men[c][point] >= 2 && point >= 19) anchors++;
  }
  return [pip, blots, home, prime, anchors, p.men[1 - c][25] - p.men[c][25]];
}

int evaluate(Position p, int c) {
  final t = terms(p, c);
  return 2 * t[0] - t[1] + 4 * t[2] + 3 * t[3] + 3 * t[4] + 6 * t[5];
}

String result(Position p, int winner) {
  final loser = p.men[1 - winner];
  if (loser[0] > 0) return 'single';
  if (loser[25] > 0 || loser.sublist(19, 25).any((n) => n > 0))
    return 'backgammon';
  return 'gammon';
}

int multiplier(String result) => result == 'gammon'
    ? 2
    : result == 'backgammon'
    ? 3
    : 1;

class State {
  Position position = Position.initial();
  int side = 0, cube = 1, owner = -1;
  bool pending = false, over = false;
  List<int> score = [0, 0];
  State copy() {
    final s = State();
    s.position = position.copy();
    s.side = side;
    s.cube = cube;
    s.owner = owner;
    s.pending = pending;
    s.over = over;
    s.score = List.of(score);
    return s;
  }

  String ownerName() => owner < 0 ? 'center' : colors[owner];
}

String cube(State s, bool prohibited) {
  final c = s.side;
  if (s.owner == 1 - c || s.cube == 64 || prohibited) return 'unavailable';
  if (s.position.contact()) {
    final e = evaluate(s.position, c);
    return e < 60
        ? 'no double'
        : e <= 100
        ? 'double take'
        : 'double drop';
  }
  final v = 8 * s.position.keith(c) - 7 * s.position.keith(1 - c),
      limit = s.owner == -1 ? 28 : 21;
  return v > limit
      ? 'no double'
      : v >= 14
      ? 'double take'
      : 'double drop';
}

class Entry {
  final String record;
  final State before, after;
  Entry(this.record, this.before, this.after);
}

State state = State();
final List<Entry> history = [], redo = [];
final output = StringBuffer();
void emit(String text) => output.writeln(text);
void end(int winner, String result, int points) {
  state.over = true;
  state.score[winner] += points;
  emit('result ${colors[winner]} $result $points');
}

void commit(Play p, int first, int second) {
  final before = state.copy(), side = state.side;
  state.position = p.position;
  if (state.position.men[side][0] == 15) {
    final r = result(state.position, side);
    end(side, r, multiplier(r) * state.cube);
  } else {
    state.side = 1 - side;
  }
  history.add(
    Entry('${colors[side]} $first-$second ${p.notation}', before, state.copy()),
  );
  redo.clear();
}

List<Move>? parsePlay(List<String> elements) {
  if (elements.length == 1 && elements[0] == 'none') return [];
  final List<Move> moves = [];
  for (final element in elements) {
    final match = RegExp(r'^(.*)\(([234])\)$').firstMatch(element);
    final count = match == null ? 1 : int.parse(match.group(2)!);
    final path = match == null ? element : match.group(1)!;
    final parts = path.split('/');
    if (parts.length < 2) return null;
    final List<int> points = [];
    for (int i = 0; i < parts.length; i++) {
      String part = parts[i];
      final int point;
      if (i == 0 && part == 'bar') {
        point = 25;
      } else if (i > 0 && part == 'off') {
        point = 0;
      } else {
        if (i > 0 && part.endsWith('*'))
          part = part.substring(0, part.length - 1);
        if (!RegExp(r'^[1-9][0-9]?$').hasMatch(part)) return null;
        point = int.parse(part);
        if (point > 24) return null;
      }
      points.add(point);
    }
    for (int i = 1; i < points.length; i++) {
      if (points[i - 1] <= points[i]) return null;
      for (int j = 0; j < count; j++) {
        moves.add((points[i - 1], points[i]));
      }
    }
  }
  return moves;
}

void play(int first, int second, List<String> elements) {
  final moves = parsePlay(elements);
  if (moves == null) {
    emit('ILLEGAL syntax');
    return;
  }
  final c = state.side,
      original = state.position,
      after = state.position.copy();
  final Set<int> destinations = {};
  for (final m in moves) {
    after.men[c][m.$1]--;
    after.men[c][m.$2]++;
    if (m.$2 > 0) destinations.add(m.$2);
  }
  for (final p in destinations) {
    if (original.opposing(c, p) == 1) {
      after.men[1 - c][25 - p]--;
      after.men[1 - c][25]++;
    }
  }
  String? error;
  if (after.men[c].any((n) => n < 0)) {
    error = 'no checker';
  } else if (after.men[c][25] > 0 && moves.any((m) => m.$1 != 25)) {
    error = 'bar';
  } else if (moves.any((m) => m.$2 > 0 && original.opposing(c, m.$2) >= 2)) {
    error = 'blocked';
  } else if (moves.any((m) => m.$2 == 0) && !after.home(c)) {
    error = 'bear-off';
  }
  if (error != null) {
    emit('ILLEGAL $error');
    return;
  }
  final g = Generator(original, c, first, second), key = after.key();
  for (final p in g.plays) {
    if (p.position.key() == key) {
      emit('OK ${p.notation}');
      commit(p, first, second);
      return;
    }
  }
  final shortest = g.shortest[key];
  emit(
    'ILLEGAL ${shortest == null
        ? 'impossible'
        : shortest < g.maximum
        ? 'too few dice'
        : 'larger die required'}',
  );
}

List<Play> ranked(List<Play> plays, int c) {
  final result = List<Play>.of(plays);
  final Map<Play, int> scores = {
    for (final play in plays) play: evaluate(play.position, c),
  };
  result.sort((a, b) {
    final value = scores[b]!.compareTo(scores[a]!);
    return value == 0 ? comparePlays(a, b) : value;
  });
  return result;
}

class Dice {
  int value;
  Dice(this.value);
  int next() {
    value = value * 48271 % 2147483647;
    return value;
  }

  int roll() => next() % 6 + 1;
}

class Game {
  final List<String> lines = [];
  int plays = 0, winner = 0, points = 0;
  String result = '';
  void finish(int winner, String result, int points) {
    this.winner = winner;
    this.result = result;
    this.points = points;
  }
}

Game simulate(
  State s,
  List<String> strategies,
  Dice dice, {
  List<int>? opening,
  int target = 0,
  List<int> matchPoints = const [0, 0],
  bool crawford = false,
}) {
  final game = Game();
  for (int turn = 1; ; turn++) {
    final side = s.side, other = 1 - s.side;
    final int first, second;
    if (turn == 1 && opening != null) {
      first = opening[0];
      second = opening[1];
    } else {
      final decision = cube(
        s,
        target > 0 && (crawford || matchPoints[side] + s.cube >= target),
      );
      if (decision.startsWith('double'))
        game.lines.add('$turn ${colors[side]} doubles ${2 * s.cube}');
      if (decision == 'double drop') {
        game.lines.add('$turn ${colors[other]} drops');
        game.finish(side, 'drop', s.cube);
        return game;
      }
      if (decision == 'double take') {
        game.lines.add('$turn ${colors[other]} takes');
        s.cube *= 2;
        s.owner = other;
      }
      first = dice.roll();
      second = dice.roll();
    }
    final plays = Generator(s.position, side, first, second).plays;
    final chosen = strategies[side] == 'BEST'
        ? ranked(plays, side).first
        : strategies[side] == 'FIRST'
        ? plays.first
        : plays[dice.next() % plays.length];
    s.position = chosen.position;
    game.plays++;
    game.lines.add('$turn ${colors[side]} $first-$second ${chosen.notation}');
    if (s.position.men[side][0] == 15) {
      final r = result(s.position, side);
      game.finish(side, r, multiplier(r) * s.cube);
      return game;
    }
    s.side = other;
  }
}

String positionText() =>
    'POS ${[for (int p = 1; p <= 24; p++) state.position.board(p)].join(',')} ${state.position.men[0][25]} ${state.position.men[1][25]} ${colors[state.side]}';
void boardLine(List<String> fields) => emit(
  '${fields.take(6).map((s) => s.padLeft(3)).join()} |${fields.skip(6).map((s) => s.padLeft(3)).join()}',
);
void board() {
  void row(List<int> points, int r) {
    boardLine(
      points.map((p) {
        final value = state.position.board(p),
            count = state.position.board(p).abs();
        return count < r
            ? '.'
            : r == 5 && count > 5
            ? count.toString()
            : value > 0
            ? 'W'
            : 'B';
      }).toList(),
    );
  }

  boardLine([for (int p = 13; p <= 24; p++) '$p']);
  for (int r = 1; r <= 5; r++) {
    row([for (int p = 13; p <= 24; p++) p], r);
  }
  final status = state.over
      ? 'game over'
      : '${colors[state.side]}${state.pending ? ' doubles' : ' to move'}';
  emit(
    'bar W${state.position.men[0][25]} B${state.position.men[1][25]} | off W${state.position.men[0][0]} B${state.position.men[1][0]} | cube ${state.cube} ${state.ownerName()} | $status',
  );
  for (int r = 5; r >= 1; r--) {
    row([for (int p = 12; p >= 1; p--) p], r);
  }
  boardLine([for (int p = 12; p >= 1; p--) '$p']);
}

void shots() {
  final c = state.side;
  final blots = [
    for (int p = 24; p >= 1; p--)
      if (state.position.men[c][p] == 1) p,
  ];
  final counts = {for (final p in blots) p: 0};
  int total = 0;
  final List<String> rolls = [];
  for (int a = 6; a >= 1; a--) {
    for (int b = a; b >= 1; b--) {
      final plays = Generator(state.position, 1 - c, a, b).plays;
      final hit = blots
          .where((p) => plays.any((play) => play.hits.contains(25 - p)))
          .toList();
      final weight = a == b ? 1 : 2;
      if (hit.isNotEmpty) {
        total += weight;
        rolls.add('$a-$b');
      }
      for (final p in hit) {
        counts[p] = counts[p]! + weight;
      }
    }
  }
  emit('shots $total/36${rolls.isEmpty ? '' : ' ${rolls.join(' ')}'}');
  for (final p in blots) {
    emit('blot $p ${counts[p]}/36');
  }
}

void execute(List<String> words) {
  final c = words[0], a = words.skip(1).toList();
  const known = [
    'NEW',
    'POS',
    'SHOW',
    'BOARD',
    'PIPS',
    'RACE',
    'MOVES',
    'PLAY',
    'AUTO',
    'HINT',
    'EVAL',
    'SHOTS',
    'CUBE',
    'DOUBLE',
    'TAKE',
    'DROP',
    'RESIGN',
    'SCORE',
    'HISTORY',
    'UNDO',
    'REDO',
    'GAME',
    'MATCH',
    'STATS',
  ];
  if (!known.contains(c)) fail('unknown command');
  if (c == 'POS') {
    requireValue(a.length == 4, 'bad position');
    final points = a[0].split(',');
    requireValue(points.length == 24, 'bad position');
    final p = Position();
    p.men[0][25] = number(a[1], 0, 15, 'bad position');
    p.men[1][25] = number(a[2], 0, 15, 'bad position');
    requireValue(colors.contains(a[3]), 'bad position');
    for (int i = 0; i < 24; i++) {
      requireValue(RegExp(r'^-?[0-9]+$').hasMatch(points[i]), 'bad position');
      final v = int.tryParse(points[i]);
      if (v == null || v < -15 || v > 15) fail('bad position');
      if (v > 0) {
        p.men[0][i + 1] = v;
      } else {
        p.men[1][24 - i] = -v;
      }
    }
    for (int side = 0; side < 2; side++) {
      p.men[side][0] = 15 - p.men[side].fold(0, (a, b) => a + b);
      requireValue(p.men[side][0] >= 0 && p.men[side][0] <= 14, 'bad position');
    }
    final score = state.score;
    state = State();
    state.position = p;
    state.side = colors.indexOf(a[3]);
    state.score = score;
    history.clear();
    redo.clear();
    emit('OK');
    return;
  }
  int first = 0, second = 0, amount = 0, seed = 0;
  if (['MOVES', 'PLAY', 'AUTO', 'HINT'].contains(c)) {
    requireValue(
      c == 'PLAY' ? a.length >= 3 : a.length == (c == 'HINT' ? 3 : 2),
    );
    first = number(a[0], 1, 6);
    second = number(a[1], 1, 6);
    if (c == 'HINT') amount = number(a[2], 1, 1000);
  } else if (c == 'UNDO' || c == 'REDO') {
    requireValue(a.length == 1);
    amount = number(a[0], 1, 1000);
  } else if (c == 'RESIGN') {
    requireValue(a.length == 1 && results.take(3).contains(a[0]));
  } else if (c == 'GAME') {
    requireValue(a.length == 3);
    seed = number(a[0], 1, 2147483646);
    requireValue(strategies.contains(a[1]) && strategies.contains(a[2]));
  } else if (c == 'MATCH' || c == 'STATS') {
    requireValue(a.length == 2);
    amount = number(a[0], 1, c == 'MATCH' ? 15 : 50);
    seed = number(a[1], 1, 2147483646);
  } else {
    requireValue(a.isEmpty);
  }
  if ([
        'RACE',
        'MOVES',
        'PLAY',
        'AUTO',
        'HINT',
        'EVAL',
        'SHOTS',
        'CUBE',
        'DOUBLE',
        'TAKE',
        'DROP',
        'RESIGN',
        'GAME',
      ].contains(c) &&
      state.over)
    fail('game over');
  if (['PLAY', 'AUTO', 'CUBE', 'DOUBLE', 'RESIGN', 'GAME'].contains(c) &&
      state.pending)
    fail('double pending');
  switch (c) {
    case 'NEW':
      {
        final score = state.score;
        state = State();
        state.score = score;
        history.clear();
        redo.clear();
        emit('OK');
      }
    case 'SHOW':
      {
        emit(positionText());
      }
    case 'BOARD':
      {
        board();
      }
    case 'PIPS':
      {
        emit('pips W ${state.position.pips(0)} B ${state.position.pips(1)}');
      }
    case 'RACE':
      {
        emit(
          state.position.contact()
              ? 'contact'
              : 'race W ${state.position.keith(0)} B ${state.position.keith(1)}',
        );
      }
    case 'MOVES':
      {
        final plays = Generator(
          state.position,
          state.side,
          first,
          second,
        ).plays;
        for (final p in plays) {
          emit(p.notation);
        }
        emit('total ${plays.length}');
      }
    case 'PLAY':
      {
        play(first, second, a.skip(2).toList());
      }
    case 'AUTO':
    case 'HINT':
      {
        final plays = ranked(
          Generator(state.position, state.side, first, second).plays,
          state.side,
        );
        if (c == 'AUTO') {
          final p = plays.first;
          emit('OK ${p.notation} eval ${evaluate(p.position, state.side)}');
          commit(p, first, second);
        } else {
          for (final p in plays.take(amount)) {
            emit('${evaluate(p.position, state.side)} ${p.notation}');
          }
        }
      }
    case 'EVAL':
      {
        final t = terms(state.position, state.side);
        emit(
          'eval ${evaluate(state.position, state.side)} pips ${t[0]} blots ${t[1]} home ${t[2]} prime ${t[3]} anchors ${t[4]} bar ${t[5]}',
        );
      }
    case 'SHOTS':
      {
        shots();
      }
    case 'CUBE':
      {
        emit('cube ${cube(state, false)}');
      }
    case 'DOUBLE':
      {
        if (state.owner == 1 - state.side || state.cube == 64)
          fail('cube unavailable');
        state.pending = true;
        redo.clear();
        emit('OK double ${2 * state.cube}');
      }
    case 'TAKE':
      {
        if (!state.pending) fail('no double');
        state.pending = false;
        state.cube *= 2;
        state.owner = 1 - state.side;
        redo.clear();
        emit('OK take ${state.cube} ${state.ownerName()}');
      }
    case 'DROP':
      {
        if (!state.pending) fail('no double');
        state.pending = false;
        redo.clear();
        emit('OK drop');
        end(state.side, 'drop', state.cube);
      }
    case 'RESIGN':
      {
        redo.clear();
        emit('OK resign');
        end(1 - state.side, a[0], multiplier(a[0]) * state.cube);
      }
    case 'SCORE':
      {
        emit('score W ${state.score[0]} B ${state.score[1]}');
      }
    case 'HISTORY':
      {
        emit('history ${history.length}');
        for (int i = 0; i < history.length; i++) {
          emit('${i + 1} ${history[i].record}');
        }
      }
    case 'UNDO':
      {
        if (amount > history.length) fail('cannot undo');
        final index = history.length - amount;
        final removed = history.sublist(index);
        state = removed.first.before.copy();
        history.removeRange(index, history.length);
        redo.insertAll(0, removed);
        emit('OK');
      }
    case 'REDO':
      {
        if (amount > redo.length) fail('cannot redo');
        final entries = redo.take(amount).toList();
        redo.removeRange(0, amount);
        history.addAll(entries);
        state = entries.last.after.copy();
        emit('OK');
      }
    case 'GAME':
      {
        final g = simulate(state.copy(), [a[1], a[2]], Dice(seed));
        for (final line in g.lines) {
          emit(line);
        }
        emit('result ${colors[g.winner]} ${g.result} ${g.points}');
      }
    case 'MATCH':
    case 'STATS':
      {
        final dice = Dice(seed),
            points = [0, 0],
            counts = List.generate(4, (_) => [0, 0]);
        int turns = 0, games = 0;
        bool crawfordPlayed = false;
        while (c == 'MATCH'
            ? (points[0] > points[1] ? points[0] : points[1]) < amount
            : games < amount) {
          final maxPoints = points[0] > points[1] ? points[0] : points[1];
          final crawford =
              c == 'MATCH' && !crawfordPlayed && maxPoints == amount - 1;
          int white, black;
          do {
            white = dice.roll();
            black = dice.roll();
          } while (white == black);
          final start = State();
          start.side = white > black ? 0 : 1;
          final firstPlayer = start.side;
          final g = simulate(
            start,
            ['BEST', 'BEST'],
            dice,
            opening: [white, black],
            target: c == 'MATCH' ? amount : 0,
            matchPoints: points,
            crawford: crawford,
          );
          games++;
          turns += g.plays;
          points[g.winner] += g.points;
          counts[results.indexOf(g.result)][g.winner]++;
          if (crawford) crawfordPlayed = true;
          if (c == 'MATCH')
            emit(
              'game $games${crawford ? ' crawford' : ''} start ${colors[firstPlayer]} turns ${g.plays} result ${colors[g.winner]} ${g.result} ${g.points} score ${points[0]}-${points[1]}',
            );
        }
        if (c == 'MATCH') {
          emit(
            'match ${colors[points[0] >= amount ? 0 : 1]} ${points[0]}-${points[1]}',
          );
        } else {
          for (int i = 0; i < 4; i++) {
            emit('${results[i]} W ${counts[i][0]} B ${counts[i][1]}');
          }
          emit('points W ${points[0]} B ${points[1]}');
          emit('turns $turns');
        }
      }
  }
}

Future<void> main() async {
  final n = int.parse(stdin.readLineSync()!);
  for (int i = 0; i < n; i++) {
    try {
      execute(stdin.readLineSync()!.split(' '));
    } on Failure catch (error) {
      emit('ERROR ${error.message}');
    }
    stdout.write(output);
    await stdout.flush();
    output.clear();
  }
}
