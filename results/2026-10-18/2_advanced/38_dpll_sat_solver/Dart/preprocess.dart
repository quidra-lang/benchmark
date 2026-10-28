part of 'main.dart';

class Preparation {
  final clauses = <List<int>>[], fixed = <int, bool>{}, active = <int>[];
  final counts = <String, int>{}, records = <String, List<int>>{};
  final bool pure;
  int emptyClause = 0;
  Preparation(this.pure);
  void increment(String name, [int amount = 1]) {
    counts[name] = (counts[name] ?? 0) + amount;
  }

  void record(String name, int number) {
    records.putIfAbsent(name, () => []).add(number);
  }
}

Preparation preprocess(Formula f, bool usePure) {
  final p = Preparation(usePure);
  var working = <(int, List<int>)>[];
  for (var i = 0; i < f.clauses.length; i++) {
    final clause = f.clauses[i], present = clause.toSet();
    if (clause.any((lit) => present.contains(-lit))) {
      p.increment('tautologies');
      p.record('tautology', i + 1);
      continue;
    }
    final seen = <int>{}, reduced = <int>[];
    for (final lit in clause) {
      if (seen.add(lit)) {
        reduced.add(lit);
      } else {
        p.increment('duplicate_literals');
      }
    }
    working.add((i + 1, reduced));
  }
  while (true) {
    for (final (number, clause) in working) {
      if (clause.isEmpty) {
        p.emptyClause = number;
        break;
      }
    }
    if (p.emptyClause > 0) break;
    int? unit;
    for (final (_, clause) in working) {
      if (clause.length == 1) {
        unit = clause[0];
        break;
      }
    }
    if (unit == null) break;
    p.fixed[unit.abs()] = unit > 0;
    p.increment('unit_fixed');
    final surviving = <(int, List<int>)>[];
    for (final (number, clause) in working) {
      if (clause.contains(unit)) {
        p.record('unit', number);
        p.increment('unit_removed');
      } else {
        surviving.add((number, clause.where((lit) => lit != -unit!).toList()));
      }
    }
    working = surviving;
  }
  if (p.emptyClause == 0) {
    final remove = <int>{},
        sets = working.map((pair) => pair.$2.toSet()).toList();
    for (var bi = 0; bi < working.length; bi++) {
      for (var ai = 0; ai < working.length; ai++) {
        if (ai != bi &&
            (working[ai].$2.length < working[bi].$2.length || ai < bi) &&
            sets[bi].containsAll(working[ai].$2)) {
          remove.add(bi);
          break;
        }
      }
    }
    final surviving = <(int, List<int>)>[];
    for (var i = 0; i < working.length; i++) {
      if (remove.contains(i)) {
        p.record('subsumed', working[i].$1);
        p.increment('subsumed');
      } else {
        surviving.add(working[i]);
      }
    }
    working = surviving;
    if (usePure) {
      while (true) {
        final present = {for (final (_, clause) in working) ...clause};
        final pure = present.where((lit) => !present.contains(-lit)).toSet();
        if (pure.isEmpty) break;
        for (final lit in pure) {
          p.fixed[lit.abs()] = lit > 0;
        }
        p.increment('pure_fixed', pure.length);
        final remaining = <(int, List<int>)>[];
        for (final (number, clause) in working) {
          if (clause.any(pure.contains)) {
            p.record('pure', number);
            p.increment('pure_removed');
          } else {
            remaining.add((number, clause));
          }
        }
        working = remaining;
      }
    }
  }
  p.counts['removed'] = [
    'tautologies',
    'unit_removed',
    'subsumed',
    'pure_removed',
  ].fold(0, (total, name) => total + (p.counts[name] ?? 0));
  p.clauses.addAll(working.map((pair) => pair.$2));
  p.active.addAll([
    for (var v = 1; v <= f.variables; v++)
      if (!p.fixed.containsKey(v)) v,
  ]);
  for (final records in p.records.values) {
    records.sort();
  }
  return p;
}
