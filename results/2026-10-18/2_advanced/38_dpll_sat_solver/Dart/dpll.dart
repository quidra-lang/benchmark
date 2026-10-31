part of 'main.dart';

class SearchStats {
  int decisions = 0, propagations = 0, conflicts = 0, maxDepth = 0;
  void add(SearchStats other) {
    decisions += other.decisions;
    propagations += other.propagations;
    conflicts += other.conflicts;
    maxDepth = math.max(maxDepth, other.maxDepth);
  }
}

(List<bool>?, List<String>, SearchStats) runRound(
  int variables,
  List<List<int>> received,
) {
  final clauses = received.map((c) => [...c]).toList(),
      assignment = List.filled(variables + 1, 0),
      watches = <int, List<int>>{},
      trail = <(int, String)>[],
      trace = <String>[],
      stats = SearchStats();
  var queueHead = 0;
  int value(int literal) =>
      literal > 0 ? assignment[literal] : -assignment[-literal];
  void assign(int literal, String kind) {
    assignment[literal.abs()] = literal > 0 ? 1 : -1;
    trail.add((literal, kind));
    trace.add('$kind$literal');
  }

  void conflict() {
    stats.conflicts++;
    trace.add('C');
  }

  for (var i = 0; i < clauses.length; i++) {
    final c = clauses[i];
    if (c.length >= 2) {
      watches.putIfAbsent(c[0], () => []).add(i);
      watches.putIfAbsent(c[1], () => []).add(i);
    }
  }
  for (final c in clauses) {
    if (c.isEmpty) {
      conflict();
      return (null, trace, stats);
    }
    if (c.length == 1) {
      final literal = c[0], truth = value(literal);
      if (truth < 0) {
        conflict();
        return (null, trace, stats);
      }
      if (truth == 0) {
        assign(literal, 'P');
        stats.propagations++;
      }
    }
  }
  while (true) {
    var foundConflict = false;
    while (queueHead < trail.length) {
      final falseLiteral = -trail[queueHead++].$1,
          watchList = watches.putIfAbsent(falseLiteral, () => []);
      var index = 0;
      while (index < watchList.length) {
        final id = watchList[index], c = clauses[id];
        if (c[0] == falseLiteral) {
          final temp = c[0];
          c[0] = c[1];
          c[1] = temp;
        }
        final other = c[0];
        if (value(other) > 0) {
          index++;
          continue;
        }
        var substitute = -1;
        for (var j = 2; j < c.length; j++) {
          if (value(c[j]) >= 0) {
            substitute = j;
            break;
          }
        }
        if (substitute >= 0) {
          final temp = c[1];
          c[1] = c[substitute];
          c[substitute] = temp;
          watchList.removeAt(index);
          watches.putIfAbsent(c[1], () => []).add(id);
          continue;
        }
        final truth = value(other);
        if (truth < 0) {
          conflict();
          foundConflict = true;
          break;
        }
        if (truth == 0) {
          assign(other, 'P');
          stats.propagations++;
        }
        index++;
      }
      if (foundConflict) break;
    }
    if (foundConflict) {
      while (trail.isNotEmpty && trail.last.$2 != 'D') {
        final entry = trail.removeLast();
        assignment[entry.$1.abs()] = 0;
      }
      if (trail.isEmpty) return (null, trace, stats);
      final decision = trail.removeLast().$1;
      assignment[decision.abs()] = 0;
      assign(-decision, 'F');
      queueHead = trail.length - 1;
      continue;
    }
    final counts = <int, int>{};
    for (final c in clauses) {
      if (c.any((lit) => value(lit) > 0)) continue;
      for (final lit in c) {
        if (value(lit) == 0) counts[lit] = (counts[lit] ?? 0) + 1;
      }
    }
    if (counts.isEmpty)
      return ([for (final v in assignment) v > 0], trace, stats);
    var best = 0;
    for (final entry in counts.entries) {
      final lit = entry.key, count = entry.value;
      if (best == 0 ||
          count > counts[best]! ||
          count == counts[best] &&
              (lit.abs() < best.abs() || lit.abs() == best.abs() && lit > best))
        best = lit;
    }
    assign(best, 'D');
    stats.decisions++;
    stats.maxDepth = math.max(
      stats.maxDepth,
      trail.where((entry) => entry.$2 == 'D' || entry.$2 == 'F').length,
    );
  }
}
