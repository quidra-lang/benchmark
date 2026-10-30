part of 'main.dart';

bool applicable(GroundAction action, State state) =>
    contains(state, action.pre) && !intersects(state, action.neg);
State apply(GroundAction action, State state) =>
    (state & ~action.del) | action.add;
bool goal(GroundProblem problem, State state) => contains(state, problem.goal);

class SearchSettings {
  final String algorithm, heuristic;
  SearchSettings(this.algorithm, this.heuristic);
  String get tag => '$algorithm $heuristic';
}

class SearchResult {
  String status = '';
  List<int> plan = [];
  int expanded = 0, generated = 0;
}

class SearchNode {
  final State state;
  final int cost, depth, h, f, serial, action;
  final SearchNode? parent;
  SearchNode(
    this.state,
    this.cost,
    this.depth,
    this.h,
    this.f,
    this.serial, {
    this.parent,
    this.action = -1,
  });
}

class MinHeap<T> {
  final int Function(T, T) compare;
  final List<T> values = [];
  MinHeap(this.compare);
  bool get isNotEmpty => values.isNotEmpty;
  void add(T value) {
    values.add(value);
    var i = values.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (compare(values[parent], value) <= 0) break;
      values[i] = values[parent];
      i = parent;
    }
    values[i] = value;
  }

  T remove() {
    final first = values.first, last = values.removeLast();
    if (values.isNotEmpty) {
      var i = 0;
      while (i * 2 + 1 < values.length) {
        var child = i * 2 + 1;
        if (child + 1 < values.length &&
            compare(values[child + 1], values[child]) < 0)
          child++;
        if (compare(last, values[child]) <= 0) break;
        values[i] = values[child];
        i = child;
      }
      values[i] = last;
    }
    return first;
  }
}

SearchResult bestFirst(
  GroundProblem g,
  State start,
  SearchSettings settings,
  int budget,
  int weight,
) {
  final result = SearchResult(),
      initialH = heuristics(g, start).value(settings.heuristic);
  if (initialH == infinity) {
    result.status = 'dead end';
    return result;
  }
  int fValue(int cost, int depth, int h) => switch (settings.algorithm) {
    'bfs' => depth,
    'ucs' => cost,
    'gbfs' => h,
    'astar' => cost + h,
    'wastar' => cost + weight * h,
    _ => throw StateError('unknown algorithm'),
  };
  final open = MinHeap<SearchNode>((a, b) {
    var c = a.f.compareTo(b.f);
    if (c != 0) return c;
    c = a.h.compareTo(b.h);
    return c != 0 ? c : a.serial.compareTo(b.serial);
  });
  var serial = 0;
  open.add(SearchNode(start, 0, 0, initialH, fValue(0, 0, initialH), 0));
  final table = <State, int>{start: 0},
      costBased = ['ucs', 'astar', 'wastar'].contains(settings.algorithm);
  while (open.isNotEmpty) {
    final node = open.remove();
    if (costBased && node.cost > table[node.state]!) continue;
    if (goal(g, node.state)) {
      result.status = 'solved';
      var cursor = node;
      while (cursor.parent != null) {
        result.plan.add(cursor.action);
        cursor = cursor.parent!;
      }
      result.plan = result.plan.reversed.toList();
      return result;
    }
    if (result.expanded == budget) {
      result.status = 'budget';
      return result;
    }
    result.expanded++;
    for (var i = 0; i < g.actions.length; i++) {
      final a = g.actions[i];
      if (!applicable(a, node.state)) continue;
      result.generated++;
      final next = apply(a, node.state),
          cost = node.cost + a.cost,
          previous = table[next];
      if (previous != null && (!costBased || previous <= cost)) continue;
      table[next] = cost;
      final h = heuristics(g, next).value(settings.heuristic);
      if (h == infinity) continue;
      open.add(
        SearchNode(
          next,
          cost,
          node.depth + 1,
          h,
          fValue(cost, node.depth + 1, h),
          ++serial,
          parent: node,
          action: i,
        ),
      );
    }
  }
  result.status = 'exhausted';
  return result;
}

class LocalNode {
  final State state;
  final List<int> plan;
  LocalNode(this.state, this.plan);
}

SearchResult enforcedHillClimbing(
  GroundProblem g,
  State start,
  SearchSettings settings,
  int budget,
) {
  final result = SearchResult();
  var current = start, hc = heuristics(g, start).value(settings.heuristic);
  if (hc == infinity) {
    result.status = 'dead end';
    return result;
  }
  while (true) {
    if (goal(g, current)) {
      result.status = 'solved';
      return result;
    }
    final queue = [LocalNode(current, [])], visited = {current};
    var improved = false;
    for (var head = 0; head < queue.length && !improved; head++) {
      final node = queue[head];
      if (result.expanded == budget) {
        result.status = 'budget';
        return result;
      }
      result.expanded++;
      for (final i in heuristics(g, node.state).helpful) {
        result.generated++;
        final next = apply(g.actions[i], node.state);
        if (!visited.add(next)) continue;
        final h = heuristics(g, next).value(settings.heuristic);
        if (h == infinity) continue;
        final path = [...node.plan, i];
        if (h < hc) {
          result.plan.addAll(path);
          current = next;
          hc = h;
          improved = true;
          break;
        }
        queue.add(LocalNode(next, path));
      }
    }
    if (!improved) {
      result.status = 'stuck';
      return result;
    }
  }
}

SearchResult search(
  GroundProblem g,
  State start,
  SearchSettings settings,
  int budget,
  int weight,
) => settings.algorithm == 'ehc'
    ? enforcedHillClimbing(g, start, settings, budget)
    : bestFirst(g, start, settings, budget, weight);
