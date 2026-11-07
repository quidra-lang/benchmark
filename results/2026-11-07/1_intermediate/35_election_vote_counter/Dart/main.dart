import 'dart:io';

final class CommandError implements Exception {
  final String reason;
  const CommandError(this.reason);
  @override
  String toString() => 'ERROR $reason';
}

enum Method {
  plurality, runoff, irv, coombs, bucklin, borda, baldwin, nanson,
  black, veto, condorcet, copeland, minimax, schulze, rankedPairs,
  kemeny, approval, stv,
}
enum MinimaxKind { winning, margin, opposition }
enum ScoreKind { first, last, borda }

final class MethodSpec {
  final Method kind;
  final int parameter;
  final MinimaxKind minimax;
  const MethodSpec(this.kind, [this.parameter = 0, this.minimax = MinimaxKind.winning]);
  bool get rankable => kind != Method.condorcet && kind != Method.stv;
  @override
  String toString() => switch (kind) {
    Method.minimax => 'MINIMAX ${minimax.name.toUpperCase()}',
    Method.approval || Method.stv => '${kind.name.toUpperCase()} $parameter',
    _ => kind.name.toUpperCase(),
  };
  factory MethodSpec.parse(List<String> words, [int start = 0]) {
    final kind = Method.values.firstWhere((m) => m.name.toUpperCase() == words[start]);
    return switch (kind) {
      Method.minimax => MethodSpec(kind, 0,
          MinimaxKind.values.firstWhere((m) => m.name.toUpperCase() == words[start + 1])),
      Method.approval || Method.stv => MethodSpec(kind, int.parse(words[start + 1])),
      _ => MethodSpec(kind),
    };
  }
}

final class Ballot {
  final int votes;
  final List<int> ranking;
  Ballot(this.votes, this.ranking);
}

final class TallyResult {
  final List<int> standings;
  final bool tie;
  final List<String> lines;
  final List<String> exhaustion;
  TallyResult(this.standings, this.tie, this.lines, [this.exhaustion = const []]);
}

int sum(Iterable<int> values) => values.fold(0, (a, b) => a + b);
int minimum(Iterable<int> values) => values.reduce((a, b) => a < b ? a : b);
int maximum(Iterable<int> values) => values.reduce((a, b) => a > b ? a : b);

final class Election {
  final int number;
  final List<String> names;
  final List<bool> withdrawn;
  List<int> tieOrder;
  final List<List<Ballot>> entries = [];
  Election(this.number, this.names)
      : withdrawn = List.filled(names.length, false),
        tieOrder = List.generate(names.length, (i) => i)
          ..sort((a, b) => names[a].compareTo(names[b]));
  List<int> get active => [for (var i = 0; i < names.length; i++) if (!withdrawn[i]) i];
  Iterable<Ballot> get groups => entries.expand((entry) => entry);
  int get total => sum(groups.map((group) => group.votes));
  int candidate(String name) {
    final index = names.indexOf(name);
    if (index < 0) throw CommandError('unknown candidate $name');
    return index;
  }
  List<int> checkNames(Iterable<String> words) {
    final result = <int>[];
    for (final name in words) {
      final index = candidate(name);
      if (result.contains(index)) throw CommandError('duplicate candidate $name');
      result.add(index);
    }
    return result;
  }
  String nameList(Iterable<int> candidates) => candidates.map((c) => names[c]).join(', ');
}

final class Tally {
  final Election election;
  final List<int> field;
  late final List<int> priority;
  late final List<Ballot> groups;
  late final List<List<int>> pairwise;
  late final int total;
  int get candidateCount => election.names.length;
  Tally(this.election, [List<int>? candidates]) : field = candidates ?? election.active {
    priority = List.filled(candidateCount, 0);
    for (var i = 0; i < election.tieOrder.length; i++) {
      priority[election.tieOrder[i]] = i;
    }
    final included = field.toSet();
    groups = [for (final group in election.groups)
      Ballot(group.votes, group.ranking.where(included.contains).toList())];
    total = sum(groups.map((group) => group.votes));
    pairwise = List.generate(candidateCount, (_) => List.filled(candidateCount, 0));
    for (final group in groups) {
      final ranks = List.filled(candidateCount, field.length);
      for (var i = 0; i < group.ranking.length; i++) {
        ranks[group.ranking[i]] = i;
      }
      for (final x in field) {
        for (final y in field) {
          if (ranks[x] < ranks[y]) pairwise[x][y] += group.votes;
        }
      }
    }
  }

  String name(int c) => election.names[c];
  String names(Iterable<int> candidates) => election.nameList(candidates);
  String ranking(Iterable<int> order) => order.map(name).join(' > ');
  static String amount(int value) => '${value ~/ 100}.${(value % 100).toString().padLeft(2, '0')}';
  String values(Iterable<int> candidates, List<int> scores, [bool amounts = false]) =>
      candidates.map((c) => '${name(c)} ${amounts ? amount(scores[c]) : scores[c]}').join(', ');

  List<int> scores(List<int> candidates, ScoreKind kind) {
    final result = List.filled(candidateCount, 0);
    final included = candidates.toSet();
    for (final group in groups) {
      final ranked = group.ranking.where(included.contains).toList();
      switch (kind) {
        case ScoreKind.first:
          if (ranked.isNotEmpty) result[ranked.first] += group.votes;
        case ScoreKind.last:
          if (ranked.length < candidates.length) {
            for (final candidate in candidates) {
              if (!ranked.contains(candidate)) result[candidate] += group.votes;
            }
          } else {
            result[ranked.last] += group.votes;
          }
        case ScoreKind.borda:
          for (var i = 0; i < ranked.length; i++) {
            result[ranked[i]] += group.votes * (candidates.length - i - 1);
          }
      }
    }
    return result;
  }
  List<int> approval(int depth) {
    final result = List.filled(candidateCount, 0);
    for (final group in groups) {
      for (final candidate in group.ranking.take(depth)) {
        result[candidate] += group.votes;
      }
    }
    return result;
  }
  List<int> order(Iterable<int> candidates, List<int> scores, [bool descending = true]) =>
      candidates.toList()..sort((a, b) {
        final difference = descending ? scores[b].compareTo(scores[a]) : scores[a].compareTo(scores[b]);
        return difference != 0 ? difference : priority[a].compareTo(priority[b]);
      });
  List<int> priorityOrder(Iterable<int> candidates) => candidates.toList()
      ..sort((a, b) => priority[a].compareTo(priority[b]));
  bool topTie(List<int> order, List<int> scores) => order.length > 1 && scores[order[0]] == scores[order[1]];
  (int, bool) eliminate(List<int> candidates, List<int> values, List<List<int>> history) {
    final low = minimum(candidates.map((c) => values[c]));
    var pool = candidates.where((c) => values[c] == low).toList();
    final tie = pool.length > 1;
    for (final previous in history.reversed) {
      final previousLow = minimum(pool.map((c) => previous[c]));
      pool = pool.where((c) => previous[c] == previousLow).toList();
    }
    return (priorityOrder(pool).last, tie);
  }
  TallyResult finish(List<int> order, bool tie, List<String> lines, [List<String> exhaustion = const []]) {
    lines.add('winner: ${name(order.first)}${tie ? ' (tie)' : ''}');
    return TallyResult(order, tie, lines, exhaustion);
  }
  TallyResult scored(List<int> scores, String label, [bool descending = true]) {
    final standings = order(field, scores, descending);
    return finish(standings, topTie(standings, scores), ['$label: ${values(field, scores)}']);
  }
  int condorcet([bool loser = false]) {
    for (final x in field) {
      if (field.every((y) => x == y || (loser ? pairwise[x][y] < pairwise[y][x] : pairwise[x][y] > pairwise[y][x]))) {
        return x;
      }
    }
    return -1;
  }
  List<String> pairLines([List<List<int>>? table]) {
    final counts = table ?? pairwise;
    final lines = <String>[];
    for (var i = 0; i < field.length; i++) {
      for (var j = i + 1; j < field.length; j++) {
        final x = field[i], y = field[j];
        final winner = counts[x][y] > counts[y][x] ? name(x) : counts[x][y] < counts[y][x] ? name(y) : 'tie';
        lines.add('${name(x)} vs ${name(y)}: ${counts[x][y]}-${counts[y][x]} ($winner)');
      }
    }
    return lines;
  }
  TallyResult runoff() {
    final first = scores(field, ScoreKind.first);
    final standings = order(field, first);
    final lines = ['round 1: ${values(field, first)}'];
    if (2 * first[standings.first] > sum(first)) return finish(standings, false, lines);
    final finalists = field.where(standings.take(2).contains).toList();
    final advanceTie = field.length > 2 && first[standings[1]] == first[standings[2]];
    final second = scores(finalists, ScoreKind.first);
    final finalOrder = finalists.toList()..sort((a, b) {
      var difference = second[b].compareTo(second[a]);
      if (difference == 0) difference = first[b].compareTo(first[a]);
      return difference != 0 ? difference : priority[a].compareTo(priority[b]);
    });
    lines.add('finalists: ${names(finalists)}${advanceTie ? ' (tie)' : ''}');
    lines.add('round 2: ${values(finalists, second)}');
    return finish([...finalOrder, ...standings.skip(2)], second[finalists[0]] == second[finalists[1]], lines);
  }
  TallyResult instantRunoff([bool coombs = false]) {
    final remaining = field.toList();
    final removed = <int>[], history = <List<int>>[];
    final lines = <String>[], exhaustion = <String>[];
    var round = 0;
    while (true) {
      final first = scores(remaining, ScoreKind.first);
      final active = sum(first);
      var line = 'round ${++round}: ${values(remaining, first)}';
      exhaustion.add('round $round: active $active, exhausted ${total - active}');
      if (remaining.length == 1 || remaining.any((c) => 2 * first[c] > active)) {
        lines.add(line);
        return finish([...order(remaining, first), ...removed.reversed], false, lines, exhaustion);
      }
      int loser;
      bool tie;
      if (coombs) {
        final last = scores(remaining, ScoreKind.last);
        final high = maximum(remaining.map((c) => last[c]));
        var pool = remaining.where((c) => last[c] == high).toList();
        tie = pool.length > 1;
        final low = minimum(pool.map((c) => first[c]));
        pool = pool.where((c) => first[c] == low).toList();
        loser = priorityOrder(pool).last;
        line += '; last ${values(remaining, last)}';
      } else {
        (loser, tie) = eliminate(remaining, first, history);
      }
      lines.add('$line; eliminated ${name(loser)}${tie ? ' (tie)' : ''}');
      removed.add(loser);
      history.add(first);
      remaining.remove(loser);
    }
  }
  TallyResult bucklin() {
    final majority = sum(groups.where((g) => g.ranking.isNotEmpty).map((g) => g.votes)) ~/ 2 + 1;
    final rounds = <List<int>>[], lines = ['majority: $majority'];
    for (var round = 1; round <= field.length; round++) {
      final current = approval(round);
      rounds.add(current);
      lines.add('round $round: ${values(field, current)}');
      if (field.any((c) => current[c] >= majority)) break;
    }
    final standings = field.toList()..sort((a, b) {
      for (final round in rounds.reversed) {
        final difference = round[b].compareTo(round[a]);
        if (difference != 0) return difference;
      }
      return priority[a].compareTo(priority[b]);
    });
    return finish(standings, topTie(standings, rounds.last), lines);
  }
  TallyResult bordaElimination(bool nanson) {
    var remaining = field.toList();
    final removed = <List<int>>[], history = <List<int>>[];
    final lines = <String>[];
    var round = 0;
    while (remaining.length > 1) {
      final current = scores(remaining, ScoreKind.borda);
      var line = 'round ${++round}: ${values(remaining, current)}';
      List<int> losers;
      if (nanson) {
        final total = sum(current);
        losers = remaining.where((c) => current[c] * remaining.length < total).toList();
        if (losers.isEmpty) { lines.add(line); break; }
        line += '; eliminated ${names(losers)}';
      } else {
        final (loser, tie) = eliminate(remaining, current, history);
        losers = [loser];
        line += '; eliminated ${name(loser)}${tie ? ' (tie)' : ''}';
      }
      lines.add(line);
      history.add(current);
      removed.add(order(losers, current));
      remaining = remaining.where((c) => !losers.contains(c)).toList();
    }
    return finish([...priorityOrder(remaining), ...removed.reversed.expand((group) => group)], nanson && remaining.length > 1, lines);
  }
  TallyResult black() {
    final winner = condorcet(), current = scores(field, ScoreKind.borda);
    var standings = order(field, current);
    final tie = winner < 0 && topTie(standings, current);
    if (winner >= 0) standings = [winner, ...standings.where((c) => c != winner)];
    return finish(standings, tie, ['condorcet: ${winner < 0 ? 'NONE' : name(winner)}', 'scores: ${values(field, current)}']);
  }
  TallyResult condorcetReport() {
    final weak = List.generate(candidateCount, (_) => List.filled(candidateCount, false));
    final strong = List.generate(candidateCount, (_) => List.filled(candidateCount, false));
    for (final x in field) {
      for (final y in field) {
        weak[x][y] = x == y || pairwise[x][y] >= pairwise[y][x];
        strong[x][y] = x != y && pairwise[x][y] > pairwise[y][x];
      }
    }
    for (final via in field) {
      for (final x in field) {
        for (final y in field) {
          weak[x][y] = weak[x][y] || weak[x][via] && weak[via][y];
          strong[x][y] = strong[x][y] || strong[x][via] && strong[via][y];
        }
      }
    }
    final winner = condorcet(), loser = condorcet(true);
    return TallyResult([], false, [
      'winner: ${winner < 0 ? 'NONE' : name(winner)}',
      'loser: ${loser < 0 ? 'NONE' : name(loser)}',
      'smith: ${names(field.where((x) => field.every((y) => weak[x][y])))}',
      'schwartz: ${names(field.where((x) => field.every((y) => !strong[y][x] || strong[x][y])))}',
    ]);
  }
  TallyResult copeland() {
    final current = List.filled(candidateCount, 0), items = <String>[];
    for (final x in field) {
      var wins = 0, draws = 0, losses = 0;
      for (final y in field) {
        if (x == y) continue;
        if (pairwise[x][y] > pairwise[y][x]) { wins++; }
        else if (pairwise[x][y] == pairwise[y][x]) { draws++; }
        else { losses++; }
      }
      current[x] = 2 * wins + draws;
      items.add('${name(x)} ${current[x] ~/ 2}.${current[x].isEven ? 0 : 5} ($wins-$draws-$losses)');
    }
    final standings = order(field, current);
    return finish(standings, topTie(standings, current), ['scores: ${items.join(', ')}']);
  }
  TallyResult minimax(MinimaxKind kind) {
    final current = List.filled(candidateCount, 0);
    for (final x in field) {
      for (final y in field) {
        if (x == y || kind != MinimaxKind.opposition && pairwise[y][x] <= pairwise[x][y]) continue;
        final value = kind == MinimaxKind.margin ? pairwise[y][x] - pairwise[x][y] : pairwise[y][x];
        if (value > current[x]) current[x] = value;
      }
    }
    return scored(current, 'scores', false);
  }
  (List<int>, bool) dominanceOrder(bool Function(int, int) dominates) {
    final remaining = field.toList(), standings = <int>[];
    var tie = false;
    while (remaining.isNotEmpty) {
      final eligible = remaining.where((x) => remaining.every((y) => x == y || !dominates(y, x))).toList();
      if (standings.isEmpty) tie = eligible.length > 1;
      final next = priorityOrder(eligible).first;
      standings.add(next);
      remaining.remove(next);
    }
    return (standings, tie);
  }
  TallyResult schulze() {
    final paths = List.generate(candidateCount, (_) => List.filled(candidateCount, 0));
    for (final x in field) {
      for (final y in field) {
        if (x != y && pairwise[x][y] > pairwise[y][x]) paths[x][y] = pairwise[x][y];
      }
    }
    for (final via in field) {
      for (final x in field) {
        if (x == via) continue;
        for (final y in field) {
          if (y == via || y == x) continue;
          final strength = paths[x][via] < paths[via][y] ? paths[x][via] : paths[via][y];
          if (strength > paths[x][y]) paths[x][y] = strength;
        }
      }
    }
    final (standings, tie) = dominanceOrder((y, x) => paths[y][x] > paths[x][y]);
    return finish(standings, tie, [...pairLines(paths), 'ranking: ${ranking(standings)}']);
  }
  TallyResult rankedPairs() {
    final pairs = <(int, int)>[
      for (final x in field) for (final y in field) if (pairwise[x][y] > pairwise[y][x]) (x, y),
    ]..sort((a, b) {
      var difference = pairwise[b.$1][b.$2].compareTo(pairwise[a.$1][a.$2]);
      if (difference == 0) difference = pairwise[a.$2][a.$1].compareTo(pairwise[b.$2][b.$1]);
      if (difference == 0) difference = priority[a.$1].compareTo(priority[b.$1]);
      return difference != 0 ? difference : priority[a.$2].compareTo(priority[b.$2]);
    });
    final locked = List.generate(candidateCount, (_) => List.filled(candidateCount, false));
    bool reachable(int from, int target) {
      final seen = <int>{}, pending = [from];
      while (pending.isNotEmpty) {
        final point = pending.removeLast();
        if (point == target) return true;
        if (!seen.add(point)) continue;
        for (final next in field) {
          if (locked[point][next]) pending.add(next);
        }
      }
      return false;
    }
    final lines = <String>[];
    for (final (x, y) in pairs) {
      final skip = reachable(y, x);
      if (!skip) locked[x][y] = true;
      lines.add('${skip ? 'skip' : 'lock'} ${name(x)}>${name(y)} ${pairwise[x][y]}-${pairwise[y][x]}');
    }
    final (standings, tie) = dominanceOrder((y, x) => locked[y][x]);
    return finish(standings, tie, lines);
  }
  TallyResult kemeny() {
    final candidates = priorityOrder(field), path = <int>[], firsts = <int>{};
    final used = List.filled(candidateCount, false);
    var best = -1, optimal = 0;
    var standings = <int>[];
    void visit(int score) {
      if (path.length == field.length) {
        if (score > best) {
          best = score;
          optimal = 0;
          firsts.clear();
          standings = path.toList();
        }
        if (score == best) { optimal++; firsts.add(path.first); }
        return;
      }
      for (final next in candidates) {
        if (used[next]) continue;
        final additional = sum(path.map((before) => pairwise[before][next]));
        path.add(next);
        used[next] = true;
        visit(score + additional);
        used[next] = false;
        path.removeLast();
      }
    }
    visit(0);
    return finish(standings, firsts.length > 1, ['score: $best', 'optimal: $optimal', 'ranking: ${ranking(standings)}']);
  }
  TallyResult stv(int seats) {
    final ballots = groups.where((group) => group.ranking.isNotEmpty).toList();
    final perVote = List.filled(ballots.length, 100);
    final quota = sum(ballots.map((group) => group.votes)) * 100 ~/ (seats + 1) + 1;
    final remaining = field.toList(), elected = <int>[];
    final history = <List<int>>[], lines = ['quota: ${amount(quota)}'];
    var round = 0;
    while (true) {
      final current = List.filled(candidateCount, 0);
      final assignments = List.filled(ballots.length, -1);
      var exhausted = 0;
      for (var i = 0; i < ballots.length; i++) {
        for (final candidate in ballots[i].ranking) {
          if (remaining.contains(candidate)) { assignments[i] = candidate; break; }
        }
        final value = ballots[i].votes * perVote[i];
        if (assignments[i] < 0) { exhausted += value; }
        else { current[assignments[i]] += value; }
      }
      var line = 'round ${++round}: ${values(remaining, current, true)}; exhausted ${amount(exhausted)}';
      if (remaining.length == seats - elected.length) {
        final added = order(remaining, current);
        elected.addAll(added);
        lines.add('$line; elected ${names(added)}');
        break;
      }
      final eligible = order(remaining.where((c) => current[c] >= quota), current);
      if (eligible.isNotEmpty) {
        final winner = eligible.first, surplus = current[winner] - quota;
        elected.add(winner);
        remaining.remove(winner);
        for (var i = 0; i < ballots.length; i++) {
          if (assignments[i] == winner) perVote[i] = perVote[i] * surplus ~/ current[winner];
        }
        line += '; elected ${name(winner)} (surplus ${amount(surplus)})';
      } else {
        final (loser, tie) = eliminate(remaining, current, history);
        remaining.remove(loser);
        line += '; excluded ${name(loser)}${tie ? ' (tie)' : ''}';
      }
      lines.add(line);
      history.add(current);
      if (elected.length == seats) break;
    }
    lines.add('elected: ${names(elected)}');
    return TallyResult([], false, lines);
  }
  TallyResult run(MethodSpec method) => switch (method.kind) {
    Method.plurality => scored(scores(field, ScoreKind.first), 'votes'),
    Method.runoff => runoff(),
    Method.irv => instantRunoff(),
    Method.coombs => instantRunoff(true),
    Method.bucklin => bucklin(),
    Method.borda => scored(scores(field, ScoreKind.borda), 'scores'),
    Method.baldwin => bordaElimination(false),
    Method.nanson => bordaElimination(true),
    Method.black => black(),
    Method.veto => scored(scores(field, ScoreKind.last), 'vetoes', false),
    Method.condorcet => condorcetReport(),
    Method.copeland => copeland(),
    Method.minimax => minimax(method.minimax),
    Method.schulze => schulze(),
    Method.rankedPairs => rankedPairs(),
    Method.kemeny => kemeny(),
    Method.approval => scored(approval(method.parameter), 'approvals'),
    Method.stv => stv(method.parameter),
  };
  List<String> ballots() {
    final counts = <String, int>{};
    var blank = 0;
    for (final group in groups) {
      final text = group.ranking.isEmpty ? '-' : group.ranking.map(name).join('>');
      counts[text] = (counts[text] ?? 0) + group.votes;
      if (group.ranking.isEmpty) blank += group.votes;
    }
    final ranked = counts.keys.toList()..sort((a, b) {
      final difference = counts[b]!.compareTo(counts[a]!);
      return difference != 0 ? difference : a.compareTo(b);
    });
    return ['total $total, blank $blank, distinct ${counts.length}', for (final text in ranked) '${counts[text]} $text'];
  }
  List<String> profile() => [for (final candidate in field) _profileRow(candidate)];
  String _profileRow(int candidate) {
    final positions = List.filled(field.length, 0);
    var unranked = 0;
    for (final group in groups) {
      final index = group.ranking.indexOf(candidate);
      if (index < 0) { unranked += group.votes; }
      else { positions[index] += group.votes; }
    }
    return '${name(candidate)}: ${positions.join(' ')} unranked $unranked';
  }
}

const summaryMethods = [
  MethodSpec(Method.plurality), MethodSpec(Method.runoff), MethodSpec(Method.irv),
  MethodSpec(Method.coombs), MethodSpec(Method.bucklin), MethodSpec(Method.borda),
  MethodSpec(Method.baldwin), MethodSpec(Method.nanson), MethodSpec(Method.black),
  MethodSpec(Method.veto), MethodSpec(Method.copeland), MethodSpec(Method.minimax),
  MethodSpec(Method.schulze), MethodSpec(Method.rankedPairs), MethodSpec(Method.kemeny),
];

final class Counter {
  Election? current;
  int electionCount = 0;
  List<String> execute(String line) {
    final words = line.split(' '), command = words.first;
    if (command == 'CANDIDATES') {
      final names = words.skip(1).toList();
      if (names.length < 2) throw const CommandError('too few candidates');
      final seen = <String>{};
      for (final name in names) {
        if (!seen.add(name)) throw CommandError('duplicate candidate $name');
      }
      final election = Election(electionCount + 1, names);
      current = election;
      electionCount++;
      return ['election $electionCount: ${names.length} candidates'];
    }
    final election = current;
    if (election == null) throw const CommandError('no election');
    switch (command) {
      case 'BALLOT':
        final ranking = words[2] == '-' ? <int>[] : election.checkNames(words[2].split('>'));
        election.entries.add([Ballot(int.parse(words[1]), ranking)]);
        return [];
      case 'RANDOM':
        var state = int.parse(words[2]);
        int draw() => state = 48271 * state % 2147483647;
        final groups = <Ballot>[];
        for (var count = int.parse(words[1]); count > 0; count--) {
          final ranking = election.active;
          for (var i = ranking.length - 1; i > 0; i--) {
            final j = draw() % (i + 1), saved = ranking[i];
            ranking[i] = ranking[j];
            ranking[j] = saved;
          }
          final length = draw() % ranking.length + 1;
          groups.add(Ballot(1, ranking.sublist(0, length)));
        }
        election.entries.add(groups);
        return [];
      case 'UNDO':
        if (election.entries.isEmpty) throw const CommandError('nothing to undo');
        election.entries.removeLast();
        return [];
      case 'WITHDRAW':
      case 'RESTORE':
        final candidate = election.candidate(words[1]);
        if (command == 'WITHDRAW') {
          if (election.withdrawn[candidate]) throw CommandError('already withdrawn ${words[1]}');
          if (election.active.length <= 2) throw const CommandError('too few candidates');
          election.withdrawn[candidate] = true;
        } else {
          if (!election.withdrawn[candidate]) throw CommandError('not withdrawn ${words[1]}');
          election.withdrawn[candidate] = false;
        }
        return [];
      case 'TIEBREAK':
        final order = election.checkNames(words.skip(1));
        if (order.length != election.names.length) throw const CommandError('incomplete tiebreak');
        election.tieOrder = order;
        return [];
      case 'STATUS':
        final withdrawn = [for (var i = 0; i < election.names.length; i++) if (election.withdrawn[i]) i];
        return ['[$line]', 'election ${election.number}', 'active: ${election.nameList(election.active)}',
          'withdrawn: ${withdrawn.isEmpty ? 'none' : election.nameList(withdrawn)}',
          'tiebreak: ${election.nameList(election.tieOrder)}', 'ballots: ${election.total} in ${election.entries.length} entries'];
    }
    if (election.entries.isEmpty) throw const CommandError('no ballots');
    final tally = Tally(election);
    List<String> lines;
    if (command == 'RANKING' || command == 'SPOILERS') {
      final method = MethodSpec.parse(words, 1);
      if (!method.rankable) throw const CommandError('not rankable');
      if (command == 'SPOILERS' && tally.field.length < 3) throw const CommandError('too few candidates');
      final standings = tally.run(method).standings;
      if (command == 'RANKING') {
        lines = [tally.ranking(standings)];
      } else {
        final winner = standings.first;
        lines = ['winner: ${tally.name(winner)}'];
        for (final excluded in tally.field) {
          if (excluded == winner) continue;
          final trial = Tally(election, tally.field.where((c) => c != excluded).toList());
          final result = trial.run(method).standings.first;
          lines.add('without ${tally.name(excluded)}: ${tally.name(result)}${result != winner ? ' (changed)' : ''}');
        }
      }
    } else if (command == 'COMPARE') {
      final first = election.candidate(words[1]);
      if (election.withdrawn[first]) throw CommandError('withdrawn candidate ${words[1]}');
      final second = election.candidate(words[2]);
      if (election.withdrawn[second]) throw CommandError('withdrawn candidate ${words[2]}');
      if (first == second) throw const CommandError('same candidate');
      final ahead = <String>[], behind = <String>[];
      for (final method in summaryMethods) {
        final standings = tally.run(method).standings;
        (standings.indexOf(first) < standings.indexOf(second) ? ahead : behind).add(method.toString());
      }
      final firstVotes = tally.pairwise[first][second], secondVotes = tally.pairwise[second][first];
      lines = ['${tally.name(first)} $firstVotes, ${tally.name(second)} $secondVotes, neither ${tally.total - firstVotes - secondVotes}',
        '${tally.name(first)} ahead: ${ahead.isEmpty ? 'none' : ahead.join(', ')}',
        '${tally.name(second)} ahead: ${behind.isEmpty ? 'none' : behind.join(', ')}'];
    } else if (command == 'SUMMARY') {
      final wins = List.filled(election.names.length, 0);
      lines = [];
      for (final method in summaryMethods) {
        final winner = tally.run(method).standings.first;
        wins[winner]++;
        lines.add('$method: ${tally.name(winner)}');
      }
      lines.add('wins: ${tally.values(tally.field, wins)}');
    } else {
      lines = switch (command) {
        'BALLOTS' => tally.ballots(),
        'PROFILE' => tally.profile(),
        'PAIRWISE' => tally.pairLines(),
        'EXHAUSTED' => tally.instantRunoff().exhaustion,
        _ => _methodLines(tally, MethodSpec.parse(words)),
      };
    }
    return ['[$line]', ...lines];
  }
  List<String> _methodLines(Tally tally, MethodSpec method) {
    if (method.kind == Method.stv && method.parameter >= tally.field.length) throw const CommandError('too many seats');
    return tally.run(method).lines;
  }
}

void main() {
  final count = int.parse(stdin.readLineSync()!);
  final counter = Counter();
  for (var i = 0; i < count; i++) {
    final line = stdin.readLineSync()!;
    try {
      for (final row in counter.execute(line)) {
        stdout.writeln(row);
      }
    } on CommandError catch (error) {
      stdout.writeln(error);
    }
  }
}
