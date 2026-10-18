import 'dart:io';

class MatchError implements Exception {
  final String message;
  MatchError(this.message);
}
Never fail(String message) => throw MatchError(message);
String pair(List<int> values, [bool reverse = false]) => reverse ? '${values[1]}-${values[0]}' : '${values[0]}-${values[1]}';
class DartValue {
  final String name;
  final int value;
  final bool double;
  DartValue(this.name, this.value, this.double);
}
final darts = <DartValue>[
  for (final prefix in ['S', 'T', 'D'])
    for (var n = 20; n >= 1; n--) DartValue('$prefix$n', n * (prefix == 'S' ? 1 : prefix == 'T' ? 3 : 2), prefix == 'D'),
  DartValue('25', 25, false), DartValue('BULL', 50, true), DartValue('MISS', 0, false),
];
final doubles = [for (var i = 40; i < 60; i++) i, 61];
List<int>? checkout(int score, int maximum) {
  for (final last in doubles)
    if (darts[last].value == score) return [last];
  if (maximum >= 2) {
    for (var a = 0; a < 62; a++) {
      for (final b in doubles)
        if (darts[a].value + darts[b].value == score) return [a, b];
    }
  }
  if (maximum >= 3) {
    for (var a = 0; a < 62; a++) {
      for (var b = 0; b < 62; b++) {
        for (final c in doubles)
          if (darts[a].value + darts[b].value + darts[c].value == score) return [a, b, c];
      }
    }
  }
  return null;
}

String dartNames(List<int> values) => values.map((i) => darts[i].name).join(' ');
class FinishedSet {
  final List<int> score;
  final int? tieLoser;
  final bool superTie;
  FinishedSet(this.score, { this.tieLoser, this.superTie = false });
  String display([bool reverse = false]) => superTie ? '[${pair(score, reverse)}]' : '${pair(score, reverse)}${tieLoser == null ? '' : '($tieLoser)'}';
}

class Event {
  final String kind;
  final int side, first, second;
  Event(this.kind, [this.side = 0, this.first = 0, this.second = 0]);
}

class Match {
  final String id, sport;
  final List<String> names;
  final Map<String, String> options;
  final List<List<int>> startingLineup;
  final history = <Event>[];
  late State state;
  Match(this.id, this.sport, this.names, this.options, this.startingLineup) {
    state = State(this);
  }

  bool get rally => ['TENNIS', 'TABLETENNIS', 'BADMINTON', 'VOLLEYBALL'].contains(sport);
  int get first => options['FIRST'] == 'B' ? 1 : 0;
  void undo() {
    if (history.isEmpty)
      fail('nothing to undo');
    history.removeLast();
    state = State(this);
    for (final event in history)
      state.apply(event);
  }
}

class State {
  final Match match;
  bool finished = false;
  int winner = 0;
  List<int> points = [0, 0], games = [0, 0], wins = [0, 0];
  List<FinishedSet> completed = [];
  int server = 0, previousWinner = -1, currentRun = 0;
  List<int> rallyPoints = [0, 0], served = [0, 0], serveWins = [0, 0], runs = [0, 0];
  List<int> holds = [0, 0], serviceGames = [0, 0], breaks = [0, 0], opportunities = [0, 0], convertedBreaks = [0,
    0];
  List<List<int>> lineup = [[], []];
  List<int> substitutions = [0, 0], timeouts = [0, 0];
  List<List<int>> frames = [[]];
  List<List<String>> marks = [[]];
  int standing = 10;
  bool newPins = true;
  List<int> remaining = [0, 0], legs = [0, 0];
  int legNumber = 1, turnStart = 0, turnValue = 0;
  List<int> turn = [];
  List<int> dartCount = [0, 0], scored = [0, 0], busts = [0, 0], high = [0, 0], tons = [0, 0],
    maximums = [0, 0], attempts = [0, 0], hits = [0, 0];
  State(this.match) {
    server = match.first;
    lineup = match.startingLineup.map((line) => List<int>.of(line)).toList();
    if (match.sport == 'DARTS') {
      final start = int.parse(match.options['START']!);
      remaining = [start, start];
      turnStart = start;
    }
  }
  State copy() {
    final s = State(match);
    s.finished = finished;
    s.winner = winner;
    s.points = List.of(points);
    s.games = List.of(games);
    s.wins = List.of(wins);
    s.completed = List.of(completed);
    s.server = server;
    s.previousWinner = previousWinner;
    s.currentRun = currentRun;
    s.rallyPoints = List.of(rallyPoints);
    s.served = List.of(served);
    s.serveWins = List.of(serveWins);
    s.runs = List.of(runs);
    s.holds = List.of(holds);
    s.serviceGames = List.of(serviceGames);
    s.breaks = List.of(breaks);
    s.opportunities = List.of(opportunities);
    s.convertedBreaks = List.of(convertedBreaks);
    s.lineup = lineup.map((line) => List<int>.of(line)).toList();
    s.substitutions = List.of(substitutions);
    s.timeouts = List.of(timeouts);
    s.frames = frames.map((f) => List<int>.of(f)).toList();
    s.marks = marks.map((f) => List<String>.of(f)).toList();
    s.standing = standing;
    s.newPins = newPins;
    s.remaining = List.of(remaining);
    s.legs = List.of(legs);
    s.legNumber = legNumber;
    s.turnStart = turnStart;
    s.turnValue = turnValue;
    s.turn = List.of(turn);
    s.dartCount = List.of(dartCount);
    s.scored = List.of(scored);
    s.busts = List.of(busts);
    s.high = List.of(high);
    s.tons = List.of(tons);
    s.maximums = List.of(maximums);
    s.attempts = List.of(attempts);
    s.hits = List.of(hits);
    return s;
  }

  bool get finalTennisSet => wins[0] == int.parse(match.options['SETS']!) ~/ 2 && wins[1] == wins[0];
  String get tennisKind => finalTennisSet && match.options['FINAL'] == 'SUPER' ? 'SUPER' : games[0] == 6
    && games[1] == 6 && !(finalTennisSet && match.options['FINAL'] == 'ADV') ? 'TIE' : 'NORMAL';
  int nextServer() {
    if (match.sport == 'TENNIS')
      return tennisKind == 'NORMAL' ? server : server ^ (((points[0] + points[1] + 1) ~/ 2) % 2);
    if (match.sport == 'TABLETENNIS') {
      final t = points[0] + points[1], initial = match.first ^ (completed.length % 2);
      return initial ^ ((t < 20 ? t ~/ 2 : t) % 2);
    }
    return server;
  }

  bool normalGameWin(int side, int extra) => points[side] + extra >= 4 && (match.options['DEUCE'] == 'NOAD'
    || points[side] + extra - points[1 - side] >= 2);
  void endSet(int side, FinishedSet result) {
    completed.add(result);
    wins[side]++;
    final target = switch (match.sport) {
      'TENNIS' => int.parse(match.options['SETS']!) ~/ 2 + 1,
      'TABLETENNIS' => int.parse(match.options['GAMES']!) ~/ 2 + 1,
      'BADMINTON' => 2,
      _ => 3,
    };
    if (wins[side] == target) {
      finished = true;
      winner = side;
      return;
    }
    points = [0, 0];
    games = [0, 0];
    if (match.sport == 'VOLLEYBALL') {
      lineup = match.startingLineup.map((line) => List<int>.of(line)).toList();
      substitutions = [0, 0];
      timeouts = [0, 0];
      server = match.first ^ (completed.length % 2);
    }
  }

  void point(int side) {
    final serving = nextServer(), kind = match.sport == 'TENNIS' ? tennisKind : '';
    rallyPoints[side]++;
    served[serving]++;
    if (side == serving)
      serveWins[side]++;
    if (previousWinner == side)
      currentRun++;
    else {
      previousWinner = side;
      currentRun = 1;
    }
    if (currentRun > runs[side])
      runs[side] = currentRun;
    if (match.sport == 'TENNIS' && kind == 'NORMAL') {
      final receiver = 1 - server;
      if (normalGameWin(receiver, 1)) {
        opportunities[receiver]++;
        if (side == receiver)
          convertedBreaks[receiver]++;
      }
    }
    points[side]++;
    if (match.sport == 'TENNIS') {
      if (kind != 'NORMAL') {
        final target = kind == 'SUPER' || finalTennisSet && match.options['FINAL'] == 'TB10' ? 10 : 7;
        if (points[side] >= target && points[side] - points[1 - side] >= 2) {
          server = 1 - server;
          if (kind == 'SUPER')
            endSet(side, FinishedSet(List.of(points), superTie: true));
          else {
            games[side] = 7;
            endSet(side, FinishedSet(List.of(games), tieLoser: points[1 - side]));
          }
        }
      } else if (normalGameWin(side, 0)) {
        serviceGames[server]++;
        if (side == server)
          holds[side]++;
        else breaks[side]++;
        games[side]++;
        points = [0, 0];
        server = 1 - server;
        if (games[side] >= 6 && games[side] - games[1 - side] >= 2)
          endSet(side, FinishedSet(List.of(games)));
      }
      return;
    }
    if (match.sport == 'BADMINTON')
      server = side;
    if (match.sport == 'VOLLEYBALL' && server != side) {
      server = side;
      lineup[side].add(lineup[side].removeAt(0));
    }
    final target = match.sport == 'TABLETENNIS' ? 11 : match.sport == 'BADMINTON' ? 21 : completed.length == 4 ? 15 : 25;
    if (points[side] >= target && points[side] - points[1 - side] >= 2 || match.sport == 'BADMINTON' && points[side] == 30) {
      endSet(side, FinishedSet(List.of(points)));
    }
  }

  void roll(int pins) {
    if (pins > standing)
      fail('too many pins');
    final frame = frames.last, symbols = marks.last;
    symbols.add(newPins && pins == 10 ? 'X' : pins == standing ? '/' : pins == 0 ? '-' : '$pins');
    frame.add(pins);
    standing -= pins;
    newPins = false;
    if (frames.length < 10) {
      if (frame[0] == 10 || frame.length == 2) {
        frames.add([]);
        marks.add([]);
        standing = 10;
        newPins = true;
      }
    } else if (frame.length == 3 || frame.length == 2 && frame[0] != 10 && frame[0] + frame[1] < 10) {
      finished = true;
    } else if (standing == 0) {
      standing = 10;
      newPins = true;
    }
  }
  List<int?> frameScores() {
    final result = <int?>[];
    for (var i = 0; i < frames.length; i++) {
      final frame = frames[i], later = frames.skip(i + 1).expand((f) => f).toList();
      int? value;
      if (i == 9) {
        if (finished)
          value = frame.fold(0, (a, b) => a + b);
      } else if (frame.isNotEmpty && frame[0] == 10) {
        if (later.length >= 2)
          value = 10 + later[0] + later[1];
      } else if (frame.length == 2) {
        final base = frame[0] + frame[1];
        if (base < 10)
          value = base;
        else if (later.isNotEmpty) value = 10 + later[0];
      }
      result.add(value);
    }
    return result;
  }

  int finalBowlingScore() => frameScores().fold(0, (s, v) => s + (v ?? 0));
  void endTurn() {
    server = 1 - server;
    turn.clear();
    turnValue = 0;
    turnStart = remaining[server];
  }

  void completedTurn(int side) {
    if (turnValue > high[side])
      high[side] = turnValue;
    if (turnValue >= 100)
      tons[side]++;
    if (turnValue == 180)
      maximums[side]++;
  }

  void throwDart(int index) {
    final dart = darts[index], side = server, before = remaining[side];
    if (before == 50 || before <= 40 && before % 2 == 0)
      attempts[side]++;
    dartCount[side]++;
    final rest = before - dart.value;
    if (rest < 0 || rest == 1 || rest == 0 && !dart.double) {
      scored[side] -= turnValue;
      remaining[side] = turnStart;
      busts[side]++;
      endTurn();
      return;
    }
    remaining[side] = rest;
    scored[side] += dart.value;
    turnValue += dart.value;
    turn.add(index);
    if (rest == 0) {
      hits[side]++;
      completedTurn(side);
      legs[side]++;
      if (legs[side] == int.parse(match.options['LEGS']!)) {
        completed.add(FinishedSet(List.of(legs)));
        wins[side]++;
        if (wins[side] == int.parse(match.options['SETS']!)) {
          finished = true;
          winner = side;
          return;
        }
        legs = [0, 0];
      }
      legNumber++;
      remaining = List.filled(2, int.parse(match.options['START']!));
      server = match.first ^ ((legNumber - 1) % 2);
      turn = [];
      turnValue = 0;
      turnStart = remaining[server];
    } else if (turn.length == 3) {
      completedTurn(side);
      endTurn();
    }
  }

  void apply(Event event) {
    if (finished)
      fail('match over');
    switch (event.kind) {
      case 'POINT':
      point(event.side);
      case 'ROLL':
      roll(event.first);
      case 'THROW':
      throwDart(event.first);
      case 'SUB':
      final team = lineup[event.side],
      position = team.indexOf(event.first);
      if (position < 0)
        fail('player not on court');
      if (team.contains(event.second))
        fail('player already on court');
      if (substitutions[event.side] == 6)
        fail('no substitutions left');
      team[position] = event.second;
      substitutions[event.side]++;
      case 'TIMEOUT':
      if (timeouts[event.side] == 2) fail('no timeouts left');
      timeouts[event.side]++;
    }
  }
  String? situation(int side) {
    final trial = copy();
    trial.point(side);
    if (trial.finished)
      return 'match point';
    if (trial.completed.length > completed.length)
      return match.sport == 'TABLETENNIS' || match.sport == 'BADMINTON' ? 'game point' : 'set point';
    if (match.sport == 'TENNIS' && tennisKind == 'NORMAL' && trial.games[side] != games[side])
      return side == nextServer() ? 'game point' : 'break point';
    return null;
  }

  String score() {
    if (match.sport == 'BOWLING') {
      final scores = frameScores(), parts = <String>[];
      var cumulative = 0;
      for (var i = 0; i < frames.length; i++) {
        if (frames[i].isEmpty)
          continue;
        if (scores[i] != null)
          cumulative += scores[i]!;
        parts.add('${marks[i].join()}${scores[i] == null ? '' : '($cumulative)'}');
      }
      return '${match.id}: ${match.names[0]}${parts.isEmpty ? '' : ' ${parts.join(' ')}'}';
    }
    final serving = nextServer(), display = [for (var i = 0; i < 2; i++) '${match.names[i]}${!finished && i == serving ? '*' : ''}'];
    final items = <String>[];
    if (match.sport == 'DARTS') {
      items.addAll(['sets', pair(wins), 'legs', pair(legs), 'score', pair(remaining)]);
      if (!finished) {
        if (turn.isNotEmpty)
          items.addAll(['turn', dartNames(turn)]);
        final route = checkout(remaining[server], 3 - turn.length);
        if (route != null)
          items.addAll(['checkout', dartNames(route)]);
      }
    } else {
      items.addAll(completed.map((s) => s.display()));
      if (!finished) {
        if (match.sport == 'TENNIS') {
          if (tennisKind == 'SUPER')
            items.add('[${pair(points)}]');
          else {
            items.add(pair(games));
            if (tennisKind == 'TIE')
              items.add(pair(points));
            else if (match.options['DEUCE'] == 'AD' && points.every((p) => p >= 3)) items.add(points[0] == points[1] ? '40-40' : points[0] > points[1] ? 'AD-40' : '40-AD');
            else items.add('${['0', '15', '30', '40'][points[0]]}-${['0', '15', '30', '40'][points[1]]}');
          }
        } else {
          items.add(pair(points));
          if (match.sport == 'VOLLEYBALL')
            items.addAll(['server', '${lineup[server][0]}']);
        }
        for (var side = 0; side < 2; side++) {
          final condition = situation(side);
          if (condition != null)
            items.add('($condition ${match.names[side]})');
        }
      }
    }
    return '${match.id}: ${display[0]} vs ${display[1]} ${items.join(' ')}';
  }

  String stats() {
    final out = StringBuffer();
    for (var side = 0; side < match.names.length; side++) {
      out.write('${match.id} ${match.names[side]}: ');
      if (match.rally) {
        out.write('points ${rallyPoints[side]} serve ${serveWins[side]}/${served[side]} run ${runs[side]}');
        if (match.sport == 'TENNIS')
          out.write(' holds ${holds[side]}/${serviceGames[side]} breaks ${breaks[side]} break points ${convertedBreaks[side]}/${opportunities[side]}');
        if (match.sport == 'VOLLEYBALL')
          out.write(' subs ${substitutions[side]} timeouts ${timeouts[side]} lineup ${lineup[side].join(',')}');
      } else if (match.sport == 'BOWLING') {
        final allMarks = marks.expand((f) => f), trial = copy();
        while (!trial.finished)
          trial.roll(trial.standing);
        final open = frames.where((f) => f.length >= 2 && f[0] != 10 && f[0] + f[1] < 10).length;
        out.write('strikes ${allMarks.where((m) => m == 'X').length} spares ${allMarks.where((m) => m == '/').length} open $open max ${trial.finalBowlingScore()}');
      } else {
        final average = dartCount[side] == 0 ? 0 : scored[side] * 300 ~/ dartCount[side];
        out.write('darts ${dartCount[side]} average ${average ~/ 100}.${(average % 100).toString().padLeft(2, '0')} busts ${busts[side]} high ${high[side]} tons ${tons[side]} 180s ${maximums[side]} doubles ${hits[side]}/${attempts[side]}');
      }
      out.writeln();
    }
    return out.toString();
  }

  String result() {
    if (!finished)
      fail('match not finished');
    if (match.sport == 'BOWLING')
      return '${match.id}: ${match.names[0]} ${finalBowlingScore()}';
    return '${match.id}: ${match.names[winner]} def. ${match.names[1 - winner]} ${completed.map((s) => s.display(winner == 1)).join(' ')}';
  }
}
const allowed = <String, Map<String, List<String>>>{
  'TENNIS': {
    'SETS': ['3', '5'],
    'DEUCE': ['AD', 'NOAD'],
    'FINAL': ['TB7', 'TB10', 'ADV', 'SUPER'],
    'FIRST': ['A', 'B']
  },
  'TABLETENNIS': { 'GAMES': ['5', '7'], 'FIRST': ['A', 'B'] },
  'BADMINTON': { 'FIRST': ['A', 'B'] },
  'VOLLEYBALL': { 'FIRST': ['A', 'B'] },
  'BOWLING': {},
  'DARTS': {
    'START': ['501', '301', '701'],
    'SETS': ['1', '2', '3', '4', '5'],
    'LEGS': ['1', '2', '3', '4', '5'],
    'FIRST': ['A', 'B']
  },
};
void main() {
  final matches = <String, Match>{}, output = StringBuffer();
  final count = int.parse(stdin.readLineSync()!);
  for (var command = 0; command < count; command++) {
    final a = stdin.readLineSync()!.split(' '), op = a[0];
    try {
      if (op == 'MATCH') {
        if (matches.containsKey(a[1]))
          fail('duplicate match');
        final sport = a[2], rules = allowed[sport]!, options = {
          for (final key in allowed[a[2]]!.keys)
            key: allowed[a[2]]![key]!.first
          };
        final seen = <String>{}, start = sport == 'BOWLING' ? 4 : sport == 'VOLLEYBALL' ? 7 : 5;
        for (final option in a.skip(start)) {
          final pair = option.split('=');
          if (pair.length != 2 || !rules.containsKey(pair[0]) || !rules[pair[0]]!.contains(pair[1]) || !seen.add(pair[0]))
            fail('invalid option');
          options[pair[0]] = pair[1];
        }
        final names = sport == 'BOWLING' ? [a[3]] : [a[3], a[4]];
        final lineup = sport == 'VOLLEYBALL' ? [a[5].split(',').map(int.parse).toList(), a[6].split(',').map(int.parse).toList()] : <List<int>>[[],
          []];
        matches[a[1]] = Match(a[1], sport, names, options, lineup);
      } else if (op == 'CHECKOUT') {
        final score = int.parse(a[1]), route = checkout(score, 3);
        output.writeln('checkout $score: ${route == null ? 'none' : dartNames(route)}');
      } else if (op == 'STANDINGS') {
        final records = <String, List<int>>{};
        for (final m in matches.values.where((m) => m.sport != 'BOWLING' && m.state.finished)) {
          (records[m.names[m.state.winner]] ??= [0, 0])[0]++;
          (records[m.names[1 - m.state.winner]] ??= [0, 0])[1]++;
        }
        final ns = records.keys.toList()..sort((a, b) => records[a]![0] != records[b]![0] ? records[b]![0].compareTo(records[a]![0]) : records[a]![1] != records[b]![1] ? records[a]![1].compareTo(records[b]![1]) : a.compareTo(b));
        output.writeln('standings: ${ns.isEmpty ? 'none' : ns.map((n) => '$n ${pair(records[n]!)}').join(', ')}');
      } else {
        final m = matches[a[1]];
        if (m == null)
          fail('unknown match');
        if (op == 'UNDO')
          m.undo();
        else if (op == 'SCORE') output.writeln(m.state.score());
        else if (op == 'STATS') output.write(m.state.stats());
        else if (op == 'RESULT') output.writeln(m.state.result());
        else {
          if (op == 'POINT' && !m.rally || op == 'ROLL' && m.sport != 'BOWLING' || op == 'THROW' && m.sport != 'DARTS'
            || ['SUB', 'TIMEOUT'].contains(op) && m.sport != 'VOLLEYBALL')
            fail('wrong event');
          final raw = op == 'POINT' ? a[2].split('') : ['ROLL', 'THROW'].contains(op) ? a.sublist(2) : [''];
          for (final token in raw) {
            if (m.state.finished)
              fail('match over');
            Event event;
            if (op == 'POINT')
              event = Event(op, token == 'A' ? 0 : 1);
            else if (op == 'ROLL') event = Event(op, 0, int.parse(token));
            else if (op == 'THROW') {
              final index = darts.indexWhere((d) => d.name == token);
              if (index < 0)
                fail('invalid dart');
              event = Event(op, 0, index);
            } else event = Event(op, a[2] == 'A' ? 0 : 1, op == 'SUB' ? int.parse(a[3]) : 0, op == 'SUB' ? int.parse(a[4]) : 0);
            m.state.apply(event);
            m.history.add(event);
          }
        }
      }
    } on MatchError catch (error) {
      output.writeln('ERROR ${error.message}');
    }
  }
  stdout.write(output);
}
