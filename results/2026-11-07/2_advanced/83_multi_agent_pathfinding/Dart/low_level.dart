part of 'main.dart';

class Prohibitions {
  final Set<(int, int)> states = {};
  final Set<(int, int, int)> moves = {};
  final Map<int, int> permanent = {};
  bool allowed(int u, int v, int t) {
    if (states.contains((v, t))) return false;
    final at = permanent[v];
    if (at != null && at <= t) return false;
    return u == v || !moves.contains((u, v, t));
  }

  int arrival(int goal) {
    var r = 0;
    for (final s in states) {
      if (s.$1 == goal) r = max(r, s.$2 + 1);
    }
    return r;
  }

  void reserve(List<int> path, int start, bool forever) {
    for (var k = 0; k < path.length; k++) {
      final c = path[k];
      states.add((c, start + k));
      if (k > 0 && c != path[k - 1]) moves.add((c, path[k - 1], start + k));
    }
    if (forever) {
      final goal = path.last, at = start + path.length - 1;
      permanent[goal] = min(permanent[goal] ?? at, at);
    }
  }
}

Prohibitions constraintProhibitions(List<Constraint> cs) {
  final b = Prohibitions();
  for (final c in cs) {
    if (c.edge) {
      b.moves.add((c.u, c.v, c.time));
    } else {
      b.states.add((c.v, c.time));
    }
  }
  return b;
}

class Counters {
  int searches = 0, expansions = 0;
  final int limit;
  bool aborted = false;
  Counters(this.limit);
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
      final p = (i - 1) ~/ 2;
      if (compare(values[p], value) <= 0) break;
      values[i] = values[p];
      i = p;
    }
    values[i] = value;
  }

  T remove() {
    final first = values.first, last = values.removeLast();
    if (values.isNotEmpty) {
      var i = 0;
      while (i * 2 + 1 < values.length) {
        var c = i * 2 + 1;
        if (c + 1 < values.length && compare(values[c + 1], values[c]) < 0) c++;
        if (compare(last, values[c]) <= 0) break;
        values[i] = values[c];
        i = c;
      }
      values[i] = last;
    }
    return first;
  }
}

class SearchState {
  final int cell, time, f, g, serial, parent;
  SearchState(this.cell, this.time, this.f, this.g, this.serial, this.parent);
}

List<int>? lowLevel(
  Grid grid,
  int agent,
  int start,
  int t0,
  int tmax,
  Prohibitions b,
  bool window,
  Counters counter,
) {
  counter.searches++;
  final r = b.arrival(grid.agents[agent].goal),
      states = [SearchState(start, t0, grid.distances[agent][start], 0, 0, -1)],
      generated = {(start, t0)};
  final open = MinHeap<int>((i, j) {
    final a = states[i], b = states[j];
    var c = a.f.compareTo(b.f);
    if (c != 0) return c;
    c = b.g.compareTo(a.g);
    return c != 0 ? c : a.serial.compareTo(b.serial);
  });
  open.add(0);
  while (open.isNotEmpty) {
    var index = open.remove();
    final s = states[index];
    counter.expansions++;
    if (counter.expansions > counter.limit) {
      counter.aborted = true;
      return null;
    }
    if ((s.cell == grid.agents[agent].goal && s.time >= r) ||
        (window && s.time == tmax)) {
      final out = <int>[];
      while (index >= 0) {
        out.add(states[index].cell);
        index = states[index].parent;
      }
      return out.reversed.toList();
    }
    if (s.time == tmax) continue;
    for (final v in grid.destinations(s.cell)) {
      final key = (v, s.time + 1);
      if (grid.distances[agent][v] < 0 ||
          generated.contains(key) ||
          !b.allowed(s.cell, v, s.time + 1))
        continue;
      generated.add(key);
      final serial = states.length, distance = s.time + 1 - t0;
      states.add(
        SearchState(
          v,
          s.time + 1,
          distance + grid.distances[agent][v],
          distance,
          serial,
          index,
        ),
      );
      open.add(serial);
    }
  }
  return null;
}
