part of 'main.dart';

const infinity = 1 << 60;

class Heuristic {
  int goalcount = 0, hmax = 0, hadd = 0, ff = 0, lmcount = 0;
  final List<int> relaxed = [], helpful = [];
  State landmarks = BigInt.zero;
  int value(String name) => switch (name) {
    'none' => 0,
    'goalcount' => goalcount,
    'hmax' => hmax,
    'hadd' => hadd,
    'ff' => ff,
    'lmcount' => lmcount,
    _ => throw StateError('unknown heuristic'),
  };
}

int aggregate(List<int> costs, State required, bool sum) {
  var value = 0;
  for (final p in numbers(required)) {
    if (costs[p] == infinity) return infinity;
    value = sum ? value + costs[p] : max(value, costs[p]);
  }
  return value;
}

List<int> relaxedCosts(GroundProblem g, State state, bool sum) {
  final costs = [
    for (var p = 0; p < g.facts.length; p++) has(state, p) ? 0 : infinity,
  ];
  while (true) {
    var changed = false;
    for (final action in g.actions) {
      final pre = aggregate(costs, action.pre, sum);
      if (pre == infinity) continue;
      final value = action.cost + pre;
      for (final p in numbers(action.add)) {
        if (value < costs[p]) {
          costs[p] = value;
          changed = true;
        }
      }
    }
    if (!changed) return costs;
  }
}

State reachableWithout(GroundProblem g, State state, int forbidden) {
  var reachable = state;
  while (true) {
    final previous = reachable;
    for (final a in g.actions) {
      if (!has(a.add, forbidden) && contains(reachable, a.pre))
        reachable |= a.add;
    }
    if (reachable == previous) return reachable;
  }
}

(List<int>, List<int>) planningLevels(GroundProblem g, State state) {
  final facts = [
        for (var p = 0; p < g.facts.length; p++) has(state, p) ? 0 : infinity,
      ],
      actions = List.filled(g.actions.length, infinity);
  for (var level = 0; ; level++) {
    var changed = false;
    for (var i = 0; i < g.actions.length; i++) {
      final a = g.actions[i];
      if (actions[i] != infinity || numbers(a.pre).any((p) => facts[p] > level))
        continue;
      actions[i] = level;
      for (final p in numbers(a.add)) {
        if (facts[p] == infinity) {
          facts[p] = level + 1;
          changed = true;
        }
      }
    }
    if (!changed) return (facts, actions);
  }
}

Heuristic heuristics(GroundProblem g, State state) {
  final cached = g.cache[state];
  if (cached != null) return cached;
  final h = Heuristic();
  h.goalcount = numbers(g.goal).where((p) => !has(state, p)).length;
  final cmax = relaxedCosts(g, state, false),
      cadd = relaxedCosts(g, state, true),
      achievers = List.generate(g.facts.length, (_) => <int>[]);
  h.hmax = aggregate(cmax, g.goal, false);
  h.hadd = aggregate(cadd, g.goal, true);
  for (var i = 0; i < g.actions.length; i++) {
    for (final p in numbers(g.actions[i].add)) {
      achievers[p].add(i);
    }
  }
  if (h.hadd == infinity) {
    h.ff = infinity;
  } else {
    final best = List.filled(g.facts.length, -1);
    for (var p = 0; p < best.length; p++) {
      if (has(state, p) || cadd[p] == infinity) continue;
      var minimum = infinity;
      for (final i in achievers[p]) {
        final a = g.actions[i], pre = aggregate(cadd, a.pre, true);
        if (pre != infinity && a.cost + pre < minimum) {
          minimum = a.cost + pre;
          best[p] = i;
        }
      }
    }
    final selected = List.filled(g.actions.length, false);
    void require(int p) {
      if (has(state, p)) return;
      final a = best[p];
      if (selected[a]) return;
      selected[a] = true;
      for (final q in numbers(g.actions[a].pre)) {
        require(q);
      }
    }

    for (final p in numbers(g.goal)) {
      require(p);
    }
    for (var i = 0; i < selected.length; i++) {
      if (!selected[i]) continue;
      h.relaxed.add(i);
      h.ff += g.actions[i].cost;
      if (applicable(g.actions[i], state)) h.helpful.add(i);
    }
  }
  final (factLevels, actionLevels) = planningLevels(g, state);
  if (numbers(g.goal).any((p) => factLevels[p] == infinity)) {
    h.lmcount = infinity;
  } else {
    h.landmarks = g.goal & ~state;
    final verified = <int, bool>{};
    while (true) {
      final previous = h.landmarks;
      for (final p in numbers(h.landmarks)) {
        State? common;
        for (final i in achievers[p]) {
          if (actionLevels[i] == factLevels[p] - 1)
            common = common == null
                ? g.actions[i].pre
                : common & g.actions[i].pre;
        }
        final candidates = (common ?? BigInt.zero) & ~state;
        for (final q in numbers(candidates)) {
          if (has(h.landmarks, q)) continue;
          final passes = verified.putIfAbsent(
            q,
            () => !contains(reachableWithout(g, state, q), g.goal),
          );
          if (passes) h.landmarks = put(h.landmarks, q);
        }
      }
      if (h.landmarks == previous) break;
    }
    h.lmcount = numbers(h.landmarks).length;
  }
  g.cache[state] = h;
  return h;
}
