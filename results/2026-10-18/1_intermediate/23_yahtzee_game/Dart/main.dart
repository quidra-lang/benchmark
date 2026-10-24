import 'dart:collection';
import 'dart:io';
import 'dart:math' show max;

const categories = ['ONES', 'TWOS', 'THREES', 'FOURS', 'FIVES', 'SIXES', 'THREEKIND', 'FOURKIND', 'FULLHOUSE', 'SMALL', 'LARGE', 'YAHTZEE', 'CHANCE'];
const powers = [1, 6, 36, 216, 1296, 7776];
const lowerMask = 0x1fc0;

enum Strategy {
  kind('KIND'), straight('STRAIGHT'), high('HIGH'), upper('UPPER');
  final String label;
  const Strategy(this.label);
}

enum JokerRule {
  forced('FORCED'), free('FREE'), off('OFF');
  final String label;
  const JokerRule(this.label);
}

class CommandError implements Exception {
  final String message;
  CommandError(this.message);
}

int sum(Iterable<int> values) => values.fold(0, (total, value) => total + value);

int positive(String word, int maximum) {
  if (word.codeUnitAt(0) < 49 || word.codeUnitAt(0) > 57 || word.codeUnits.any((c) => c < 48 || c > 57)) {
    throw CommandError('bad value $word');
  }
  final value = int.parse(word);
  if (value > maximum) throw CommandError('bad value $word');
  return value;
}

void checkName(String word) {
  if (word.length > 8 || word.codeUnits.any((c) => c < 65 || c > 90)) throw CommandError('bad name $word');
}

int parsePattern(String word) {
  if (word.length != 5 || word.codeUnits.any((c) => c != 48 && c != 49)) throw CommandError('bad pattern $word');
  return int.parse(word, radix: 2);
}

int parseCategory(String word) {
  final category = categories.indexOf(word);
  if (category < 0) throw CommandError('bad category $word');
  return category;
}

Strategy parseStrategy(String word) {
  for (final strategy in Strategy.values) {
    if (strategy.label == word) return strategy;
  }
  throw CommandError('bad strategy $word');
}

String fraction(int numerator, int denominator) {
  final divisor = numerator.gcd(denominator);
  numerator ~/= divisor;
  denominator ~/= divisor;
  return denominator == 1 ? '$numerator' : '$numerator/$denominator';
}

String average(int total, int count) {
  final value = count == 0 ? 0 : 100 * total ~/ count;
  return '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
}

bool isHeld(int mask, int die) => (mask & (1 << (4 - die))) != 0;
String patternText(int mask) => mask.toRadixString(2).padLeft(5, '0');

String facesText(List<int>? faces, [int mask = 31]) {
  final selected = <int>[];
  if (faces != null) {
    for (var i = 0; i < 5; i++) {
      if (isHeld(mask, i)) selected.add(faces[i]);
    }
  }
  return selected.isEmpty ? '-' : selected.join(' ');
}

List<int> faceCounts(List<int> faces) {
  final counts = List.filled(6, 0);
  for (final face in faces) counts[face - 1]++;
  return counts;
}

List<int> decode(int code) {
  final counts = List.filled(6, 0);
  for (var i = 0; i < 6; i++) { counts[i] = code % 6; code ~/= 6; }
  return counts;
}

int heldCode(List<int> faces, int mask) {
  var code = 0;
  for (var i = 0; i < 5; i++) {
    if (isHeld(mask, i)) code += powers[faces[i] - 1];
  }
  return code;
}

int mostFrequent(List<int> counts) {
  var face = 0;
  for (var i = 1; i < 6; i++) {
    if (counts[i] >= counts[face]) face = i;
  }
  return face;
}

int normalScore(int category, List<int> counts) {
  if (category < 6) return (category + 1) * counts[category];
  var total = 0, largest = 0, bits = 0;
  for (var i = 0; i < 6; i++) {
    total += (i + 1) * counts[i];
    largest = max(largest, counts[i]);
    if (counts[i] > 0) bits |= 1 << i;
  }
  return switch (category) {
    6 => largest >= 3 ? total : 0,
    7 => largest >= 4 ? total : 0,
    8 => counts.contains(3) && counts.contains(2) ? 25 : 0,
    9 => (bits & 15) == 15 || (bits & 30) == 30 || (bits & 60) == 60 ? 30 : 0,
    10 => bits == 31 || bits == 62 ? 40 : 0,
    11 => largest == 5 ? 50 : 0,
    _ => total,
  };
}

class Player {
  final String name;
  Strategy strategy;
  final scores = List<int?>.filled(13, null);
  int yahtzeeBonus = 0;
  Player(this.name, [this.strategy = Strategy.kind]);
  int get upper => sum(scores.take(6).map((value) => value ?? 0));
  int get upperBonus => upper >= 63 ? 35 : 0;
  int get total => sum(scores.map((value) => value ?? 0)) + upperBonus + yahtzeeBonus;
  int get round => scores.where((value) => value != null).length + 1;
}

typedef Candidates = ({List<int> points, int allowed, bool joker, int best});

Candidates evaluate(Player player, List<int> counts, JokerRule rule) {
  var allowed = 0;
  for (var c = 0; c < 13; c++) {
    if (player.scores[c] == null) allowed |= 1 << c;
  }
  final joker = rule != JokerRule.off && counts.contains(5) && player.scores[11] != null;
  if (joker && rule == JokerRule.forced) {
    final upper = counts.indexOf(5);
    if ((allowed & (1 << upper)) != 0) {
      allowed = 1 << upper;
    } else if ((allowed & lowerMask) != 0) {
      allowed &= lowerMask;
    }
  }
  final points = List.filled(13, -1);
  var best = -1;
  for (var c = 0; c < 13; c++) {
    if (player.scores[c] != null) continue;
    points[c] = (allowed & (1 << c)) == 0 ? 0
        : joker && c >= 8 && c <= 10 ? const [25, 30, 40][c - 8] : normalScore(c, counts);
    if (best < 0 || points[c] > points[best]) best = c;
  }
  return (points: points, allowed: allowed, joker: joker, best: best);
}

typedef Outcome = ({int code, int weight});

List<List<Outcome>> makeOutcomes() {
  const factorial = [1, 1, 2, 6, 24, 120];
  final result = List.generate(6, (_) => <Outcome>[]);
  for (var size = 0; size <= 5; size++) {
    void add(int face, int remaining, int code, int divisor) {
      if (face == 6) {
        if (remaining == 0) result[size].add((code: code, weight: factorial[size] ~/ divisor));
        return;
      }
      for (var n = 0; n <= remaining; n++) {
        add(face + 1, remaining - n, code + n * powers[face], divisor * factorial[n]);
      }
    }
    add(0, size, 0, 1);
  }
  return result;
}

final outcomes = makeOutcomes();

class Turn {
  final int seat, rolls, hold;
  final List<int>? faces;
  final bool finished;
  Turn({this.seat = 0, this.rolls = 0, List<int>? faces, this.hold = 0, this.finished = false})
      : faces = faces == null ? null : List.unmodifiable(faces);
}

class ScoreEntry {
  final Turn before;
  final int category, points, bonus;
  final bool joker;
  ScoreEntry(this.before, this.category, this.points, this.bonus, this.joker);
}

typedef RedoEntry = ({Turn after, ScoreEntry entry});

class Game {
  final List<Player> players;
  int randomState;
  final int maxRolls;
  final JokerRule joker;
  final void Function(String)? output;
  final loaded = Queue<int>();
  final faceTotals = List.filled(6, 0);
  final entries = <ScoreEntry>[];
  final redoList = <RedoEntry>[];
  Turn state = Turn();
  Game(this.randomState, this.players, this.maxRolls, this.joker, [this.output]);
  Player get current => players[state.seat];
  void emit(String line) => output?.call(line);

  void checkTurn() {
    if (state.finished) throw CommandError('game over');
  }

  void checkRolled() {
    checkTurn();
    if (state.rolls == 0) throw CommandError('not rolled');
  }

  void checkRollsLeft() {
    checkRolled();
    if (state.rolls == maxRolls) throw CommandError('no rolls left');
  }

  void roll() {
    checkTurn();
    if (state.rolls == maxRolls) throw CommandError('no rolls left');
    if (state.hold == 31) throw CommandError('all dice held');
    redoList.clear();
    final faces = state.faces == null ? List.filled(5, 0) : List<int>.of(state.faces!);
    for (var i = 0; i < 5; i++) {
      if (state.rolls > 0 && isHeld(state.hold, i)) continue;
      if (loaded.isNotEmpty) {
        faces[i] = loaded.removeFirst();
      } else {
        randomState = 48271 * randomState % 2147483647;
        faces[i] = randomState % 6 + 1;
      }
      faceTotals[faces[i] - 1]++;
    }
    state = Turn(seat: state.seat, rolls: state.rolls + 1, faces: faces, hold: state.hold);
    emit('${current.name} roll ${state.rolls}: ${facesText(faces)}');
  }

  void hold(int mask) {
    checkRollsLeft();
    redoList.clear();
    state = Turn(seat: state.seat, rolls: state.rolls, faces: state.faces, hold: mask);
    emit('${current.name} holds ${patternText(mask)}: ${facesText(state.faces, mask)}');
  }

  void keep(List<int> values) {
    checkRollsLeft();
    var mask = 0;
    for (final value in values) {
      var die = -1;
      for (var i = 0; i < 5; i++) {
        if (!isHeld(mask, i) && state.faces![i] == value) { die = i; break; }
      }
      if (die < 0) throw CommandError('not showing $value');
      mask |= 1 << (4 - die);
    }
    hold(mask);
  }

  void score(int category, {bool preview = false}) {
    checkRolled();
    final player = current;
    if (player.scores[category] != null) throw CommandError('${categories[category]} already used');
    final counts = faceCounts(state.faces!);
    final candidates = evaluate(player, counts, joker);
    if ((candidates.allowed & (1 << category)) == 0) {
      final upper = counts.indexOf(5);
      throw CommandError('joker requires ${player.scores[upper] == null ? categories[upper] : 'lower box'}');
    }
    final points = candidates.points[category];
    final bonus = counts.contains(5) && player.scores[11] == 50 ? 100 : 0;
    final upperBonus = category < 6 && player.upper < 63 && player.upper + points >= 63 ? 35 : 0;
    var line = '${player.name} ${preview ? 'would score' : 'scores'} $points in ${categories[category]}';
    if (candidates.joker) line += ' joker';
    if (bonus != 0) line += ' ybonus 100';
    if (upperBonus != 0) line += ' ubonus 35';
    line += ' total ${player.total + points + bonus + upperBonus}';
    if (preview) { emit(line); return; }
    redoList.clear();
    entries.add(ScoreEntry(state, category, points, bonus, candidates.joker));
    player.scores[category] = points;
    player.yahtzeeBonus += bonus;
    state = entries.length == 13 * players.length ? Turn(finished: true) : Turn(seat: (state.seat + 1) % players.length);
    emit(line);
    emit(state.finished ? 'game over' : 'turn ${current.round} ${current.name}');
  }

  void undo() {
    if (entries.isEmpty) throw CommandError('nothing to undo');
    final entry = entries.removeLast();
    redoList.add((after: state, entry: entry));
    final player = players[entry.before.seat];
    player.scores[entry.category] = null;
    player.yahtzeeBonus -= entry.bonus;
    state = entry.before;
    emit('undo ${player.name} ${categories[entry.category]} ${entry.points}');
  }

  void redo() {
    if (redoList.isEmpty) throw CommandError('nothing to redo');
    final saved = redoList.removeLast();
    final entry = saved.entry;
    final player = players[entry.before.seat];
    player.scores[entry.category] = entry.points;
    player.yahtzeeBonus += entry.bonus;
    entries.add(entry);
    state = saved.after;
    emit('redo ${player.name} ${categories[entry.category]} ${entry.points}');
  }

  int botHold(Strategy strategy) {
    final faces = state.faces!, counts = faceCounts(faces);
    final frequent = mostFrequent(counts);
    var mask = 0;
    if (strategy == Strategy.straight) {
      var bestStart = 0, bestLength = 0;
      for (var start = 0; start < 6; start++) {
        var end = start;
        while (end < 6 && counts[end] > 0) end++;
        if (end - start >= bestLength) { bestStart = start; bestLength = end - start; }
      }
      if (bestLength >= 3) {
        for (var face = bestStart + 1; face <= bestStart + bestLength; face++) {
          mask |= 1 << (4 - faces.indexOf(face));
        }
        return mask;
      }
    }
    for (var i = 0; i < 5; i++) {
      if (strategy == Strategy.high ? faces[i] >= 5 : faces[i] == frequent + 1) mask |= 1 << (4 - i);
    }
    return mask;
  }

  void botTurn() {
    final strategy = current.strategy;
    if (state.rolls == 0) roll();
    while (state.rolls < maxRolls) {
      final mask = botHold(strategy);
      if (mask == 31) break;
      hold(mask);
      roll();
    }
    final counts = faceCounts(state.faces!);
    final candidates = evaluate(current, counts, joker);
    final frequent = mostFrequent(counts);
    final category = strategy == Strategy.upper && counts[frequent] >= 3 && (candidates.allowed & (1 << frequent)) != 0
        ? frequent : candidates.best;
    score(category);
  }

  List<int> ranking() => List.generate(players.length, (i) => i)
    ..sort((a, b) {
      final difference = players[b].total.compareTo(players[a].total);
      return difference == 0 ? a.compareTo(b) : difference;
    });
}

class Adviser {
  final Player player;
  final JokerRule rule;
  final values = <(int, int), int>{};
  final expectations = <(int, int), int>{};
  Adviser(this.player, this.rule);

  // Depth j uses the common denominator 7776^j throughout the dynamic program.
  int value(int code, int depth) {
    final key = (depth, code);
    final cached = values[key];
    if (cached != null) return cached;
    final counts = decode(code);
    var best = -1;
    if (depth == 0) {
      final candidates = evaluate(player, counts, rule);
      best = candidates.points[candidates.best];
    } else {
      void search(int face, int held) {
        if (face == 6) { best = max(best, expected(held, depth)); return; }
        for (var n = 0; n <= counts[face]; n++) search(face + 1, held + n * powers[face]);
      }
      search(0, 0);
    }
    values[key] = best;
    return best;
  }

  int expected(int held, int depth) {
    final key = (depth, held);
    final cached = expectations[key];
    if (cached != null) return cached;
    final rerolled = 5 - sum(decode(held));
    var total = 0;
    for (final outcome in outcomes[rerolled]) total += outcome.weight * value(held + outcome.code, depth - 1);
    final result = total * powers[5 - rerolled];
    expectations[key] = result;
    return result;
  }
}

class GameRecord {
  int games = 0, wins = 0, best = 0, sum = 0;
}

class SimulationTotal {
  int wins = 0, sum = 0, best = 0, bonus = 0, yahtzee = 0;
}

class Program {
  int rolls = 3;
  JokerRule joker = JokerRule.forced;
  Game? game;
  final records = <String, GameRecord>{};
  final output = StringBuffer();
  void emit(String line) => output.writeln(line);
  Game table() => game ?? (throw CommandError('no game'));

  void odds(Game table, int mask) {
    table.checkRollsLeft();
    final held = heldCode(table.state.faces!, mask), rerolled = 5 - sum(decode(held));
    final count = powers[rerolled];
    final totals = List.filled(13, 0), chances = List.filled(13, 0);
    var best = 0;
    for (final outcome in outcomes[rerolled]) {
      final candidates = evaluate(table.current, decode(held + outcome.code), table.joker);
      for (var c = 0; c < 13; c++) {
        if (candidates.points[c] < 0) continue;
        totals[c] += outcome.weight * candidates.points[c];
        if (candidates.points[c] > 0) chances[c] += outcome.weight;
      }
      best += outcome.weight * candidates.points[candidates.best];
    }
    emit('odds ${patternText(mask)} outcomes $count');
    for (var c = 0; c < 13; c++) {
      if (table.current.scores[c] == null) emit('${categories[c]} expect ${fraction(totals[c], count)} chance ${fraction(chances[c], count)}');
    }
    emit('best expect ${fraction(best, count)}');
  }

  void advise(Game table) {
    table.checkRollsLeft();
    final depth = table.maxRolls - table.state.rolls;
    var chosen = 0, best = -1, denominator = 1;
    for (var i = 0; i < depth; i++) denominator *= 7776;
    final adviser = Adviser(table.current, table.joker);
    for (var mask = 0; mask < 32; mask++) {
      final value = adviser.expected(heldCode(table.state.faces!, mask), depth);
      if (value > best) { best = value; chosen = mask; }
    }
    emit('advise ${patternText(chosen)}: ${facesText(table.state.faces, chosen)} expect ${fraction(best, denominator)}');
  }

  void card(Game table) {
    void row(String heading, String Function(Player) cell) {
      var line = heading.padRight(9);
      for (final player in table.players) line += ' ${cell(player).padLeft(max(4, player.name.length))}';
      emit(line);
    }
    row('CATEGORY', (p) => p.name);
    for (var c = 0; c < 13; c++) row(categories[c], (p) => p.scores[c]?.toString() ?? '-');
    row('UPPER', (p) => '${p.upper}');
    row('BONUS', (p) => '${p.upperBonus}');
    row('YBONUS', (p) => '${p.yahtzeeBonus}');
    row('TOTAL', (p) => '${p.total}');
  }

  void simulate(int seed, int count, List<Strategy> strategies) {
    final totals = List.generate(strategies.length, (_) => SimulationTotal());
    var state = seed;
    for (var n = 0; n < count; n++) {
      final players = List.generate(strategies.length, (i) => Player('BOT${i + 1}', strategies[i]));
      final table = Game(state, players, rolls, joker);
      while (!table.state.finished) table.botTurn();
      state = table.randomState;
      totals[table.ranking().first].wins++;
      for (var i = 0; i < players.length; i++) {
        final player = players[i];
        final total = totals[i];
        total.sum += player.total;
        total.best = max(total.best, player.total);
        if (player.upperBonus == 35) total.bonus++;
        if (player.scores[11] == 50) total.yahtzee++;
      }
    }
    emit('sim seed $seed games $count players ${strategies.length}');
    for (var i = 0; i < strategies.length; i++) {
      final total = totals[i];
      emit('seat ${i + 1} ${strategies[i].label} wins ${total.wins} average ${average(total.sum, count)} best ${total.best} bonus ${total.bonus} yahtzee ${total.yahtzee}');
    }
  }

  void execute(List<String> words) {
    switch (words[0]) {
      case 'RULE':
        if (words[1] != 'ROLLS' && words[1] != 'JOKER') throw CommandError('unknown rule ${words[1]}');
        var newRolls = rolls;
        var newJoker = joker;
        if (words[1] == 'ROLLS') {
          newRolls = positive(words[2], 4);
        } else {
          newJoker = switch (words[2]) {
            'FORCED' => JokerRule.forced, 'FREE' => JokerRule.free, 'OFF' => JokerRule.off,
            _ => throw CommandError('bad value ${words[2]}'),
          };
        }
        if (game != null) throw CommandError('game in progress');
        rolls = newRolls; joker = newJoker;
        emit('rule ${words[1]} ${words[2]}');
        return;
      case 'GAME':
        final seed = positive(words[1], 2147483646);
        final names = words.sublist(2);
        for (final name in names) checkName(name);
        if (names.length > 6) throw CommandError('too many players');
        if (game != null) throw CommandError('game in progress');
        final seen = <String>{};
        for (final name in names) {
          if (!seen.add(name)) throw CommandError('duplicate name $name');
        }
        game = Game(seed, names.map((name) => Player(name)).toList(), rolls, joker, emit);
        emit('game seed $seed players ${names.join(' ')}');
        emit('turn 1 ${names.first}');
        return;
      case 'BOT':
        checkName(words[1]);
        final strategy = parseStrategy(words[2]);
        final table = this.table();
        final seat = table.players.indexWhere((player) => player.name == words[1]);
        if (seat < 0) throw CommandError('no player ${words[1]}');
        table.players[seat].strategy = strategy;
        emit('bot ${words[1]} ${words[2]}');
        return;
      case 'LOAD':
      case 'KEEP':
        final values = words.skip(1).map((word) => positive(word, 6)).toList();
        final table = this.table();
        if (words[0] == 'KEEP') {
          table.keep(values);
        } else {
          table.loaded.addAll(values);
          emit('loaded ${table.loaded.length}');
        }
        return;
      case 'ROLL': table().roll(); return;
      case 'HOLD':
      case 'ODDS':
        final mask = parsePattern(words[1]);
        final table = this.table();
        if (words[0] == 'HOLD') { table.hold(mask); } else { odds(table, mask); }
        return;
      case 'SCORE':
      case 'WHATIF':
        final category = parseCategory(words[1]);
        table().score(category, preview: words[0] == 'WHATIF');
        return;
      case 'UNDO': table().undo(); return;
      case 'REDO': table().redo(); return;
      case 'SUGGEST':
        final table = this.table();
        table.checkRolled();
        final candidates = evaluate(table.current, faceCounts(table.state.faces!), table.joker);
        var line = 'suggest';
        for (var c = 0; c < 13; c++) {
          if (candidates.points[c] >= 0) line += ' ${categories[c]} ${candidates.points[c]}';
        }
        emit('$line best ${categories[candidates.best]} ${candidates.points[candidates.best]}');
        return;
      case 'ADVISE': advise(table()); return;
      case 'AUTO':
        final count = positive(words[1], 100);
        final table = this.table();
        table.checkTurn();
        table.redoList.clear();
        for (var i = 0; i < count && !table.state.finished; i++) table.botTurn();
        return;
      case 'STATUS':
        final table = this.table();
        final turn = table.state;
        emit(turn.finished ? 'status game over'
            : 'status round ${table.current.round} player ${table.current.name} rolls ${turn.rolls} dice ${facesText(turn.faces)} holds ${patternText(turn.hold)}');
        return;
      case 'CARD': card(table()); return;
      case 'BONUS':
        for (final player in table().players) {
          var maximum = player.upper;
          for (var c = 0; c < 6; c++) {
            if (player.scores[c] == null) maximum += 5 * (c + 1);
          }
          final status = player.upper >= 63 ? 'made' : maximum < 63 ? 'lost' : 'open';
          emit('bonus ${player.name} upper ${player.upper} need ${max(63 - player.upper, 0)} max $maximum $status');
        }
        return;
      case 'STATS':
        final table = this.table();
        for (var i = 0; i < table.players.length; i++) {
          final entries = table.entries.where((entry) => entry.before.seat == i).toList();
          emit('stats ${table.players[i].name} turns ${entries.length} rolls ${sum(entries.map((e) => e.before.rolls))} zeros ${entries.where((e) => e.points == 0).length} yahtzees ${entries.where((e) => faceCounts(e.before.faces!).contains(5)).length} average ${average(sum(entries.map((e) => e.points)), entries.length)}');
        }
        return;
      case 'LOG':
        final table = this.table();
        for (var i = 0; i < table.entries.length; i++) {
          final entry = table.entries[i];
          var line = 'log ${i + 1} ${table.players[entry.before.seat].name} ${facesText(entry.before.faces)} ${categories[entry.category]} ${entry.points}';
          if (entry.joker) line += ' joker';
          if (entry.bonus != 0) line += ' ybonus 100';
          emit(line);
        }
        if (table.entries.isEmpty) emit('no scores');
        return;
      case 'FACES':
        final counts = table().faceTotals;
        final total = sum(counts);
        final numerator = 6 * sum(counts.map((c) => c * c)) - total * total;
        emit('faces ${counts.join(' ')} total $total chi2 ${fraction(numerator, total == 0 ? 1 : total)}');
        return;
      case 'STANDINGS':
      case 'END':
        final table = this.table();
        final ranking = table.ranking();
        final end = words[0] == 'END';
        if (end) emit(table.state.finished ? 'end final' : 'end abandoned');
        for (var rank = 0; rank < ranking.length; rank++) {
          final player = table.players[ranking[rank]];
          if (!end) {
            emit('standing ${rank + 1} ${player.name} ${player.total} behind ${table.players[ranking.first].total - player.total}');
          } else {
            emit('rank ${rank + 1} ${player.name} ${player.total}');
            if (table.state.finished) {
              final record = records.putIfAbsent(player.name, GameRecord.new);
              record.games++; record.sum += player.total; record.best = max(record.best, player.total);
              if (rank == 0) record.wins++;
            }
          }
        }
        if (end) game = null;
        return;
      case 'RECORDS':
        final names = records.keys.toList()..sort((a, b) {
          final first = records[a]!, second = records[b]!;
          if (first.wins != second.wins) return second.wins.compareTo(first.wins);
          if (first.best != second.best) return second.best.compareTo(first.best);
          return a.compareTo(b);
        });
        for (final name in names) {
          final record = records[name]!;
          emit('record $name games ${record.games} wins ${record.wins} best ${record.best} average ${average(record.sum, record.games)}');
        }
        if (names.isEmpty) emit('no records');
        return;
      case 'SIM':
        final seed = positive(words[1], 2147483646), count = positive(words[2], 50);
        final strategies = words.skip(3).map(parseStrategy).toList();
        if (strategies.length > 6) throw CommandError('too many players');
        simulate(seed, count, strategies);
        return;
      default: throw CommandError('unknown command ${words[0]}');
    }
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final program = Program();
  for (var i = 0; i < count; i++) {
    final words = stdin.readLineSync()!.split(' ');
    try { program.execute(words); }
    on CommandError catch (error) { program.emit('error: ${error.message}'); }
  }
  stdout.write(program.output);
}
