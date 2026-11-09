part of 'main.dart';

List<int> acyclic(int n, List<Edge> edges) {
  final remaining = List.filled(n, true), head = <int>[], tail = <int>[];
  for (var count = 0; count < n; count++) {
    final indegree = List.filled(n, 0), outdegree = List.filled(n, 0);
    for (final e in edges) {
      if (remaining[e.from] && remaining[e.to]) {
        outdegree[e.from]++;
        indegree[e.to]++;
      }
    }
    var chosen = -1, toTail = false;
    for (var v = 0; v < n; v++) {
      if (remaining[v] && outdegree[v] == 0) {
        chosen = v;
        toTail = true;
        break;
      }
    }
    if (chosen < 0) {
      for (var v = 0; v < n; v++) {
        if (remaining[v] && indegree[v] == 0) {
          chosen = v;
          break;
        }
      }
    }
    if (chosen < 0) {
      for (var v = 0; v < n; v++) {
        if (remaining[v] &&
            (chosen < 0 ||
                outdegree[v] - indegree[v] >
                    outdegree[chosen] - indegree[chosen]))
          chosen = v;
      }
    }
    remaining[chosen] = false;
    if (toTail) {
      tail.insert(0, chosen);
    } else {
      head.add(chosen);
    }
  }
  return [...head, ...tail];
}

class Promotion {
  final int round, node, diff;
  Promotion(this.round, this.node, this.diff);
}

class LayeringResult {
  List<int> height;
  final List<int> labels;
  int dummiesBefore = 0, rounds = 0;
  final List<Promotion> promotions = [];
  LayeringResult(int n)
    : height = List.filled(n, 0),
      labels = List.filled(n, 0);
}

LayeringResult assignLayers(
  int n,
  List<List<int>> predecessors,
  List<List<int>> successors,
  Settings settings,
) {
  final r = LayeringResult(n);
  if (settings.layering == 'longest') {
    final known = List.filled(n, false);
    int height(int v) {
      if (known[v]) return r.height[v];
      for (final w in successors[v]) {
        r.height[v] = max(r.height[v], height(w) + 1);
      }
      known[v] = true;
      return r.height[v];
    }

    for (var v = 0; v < n; v++) {
      height(v);
    }
  } else {
    for (var label = 1; label <= n; label++) {
      var chosen = -1;
      List<int>? best;
      for (var v = 0; v < n; v++) {
        if (r.labels[v] != 0 || predecessors[v].any((p) => r.labels[p] == 0))
          continue;
        final key = [for (final p in predecessors[v]) r.labels[p]]
          ..sort((a, b) => b.compareTo(a));
        if (chosen < 0 || compareInts(key, best!) < 0) {
          chosen = v;
          best = key;
        }
      }
      r.labels[chosen] = label;
    }
    r.height = List.filled(n, -1);
    var current = 0, count = 0;
    for (var k = 0; k < n; k++) {
      var chosen = -1;
      for (var v = 0; v < n; v++) {
        if (r.height[v] < 0 &&
            !successors[v].any((s) => r.height[s] < 0) &&
            (chosen < 0 || r.labels[v] > r.labels[chosen]))
          chosen = v;
      }
      if (count == settings.width ||
          successors[chosen].any((s) => r.height[s] == current)) {
        current++;
        count = 0;
      }
      r.height[chosen] = current;
      count++;
    }
  }
  for (var v = 0; v < n; v++) {
    for (final w in successors[v]) {
      r.dummiesBefore += r.height[v] - r.height[w] - 1;
    }
  }
  if (settings.promotion == 'on') {
    int promote(int v) {
      var diff = 0;
      for (final u in predecessors[v]) {
        if (r.height[u] == r.height[v] + 1) diff += promote(u);
      }
      r.height[v]++;
      return diff + successors[v].length - predecessors[v].length;
    }

    while (true) {
      r.rounds++;
      var accepted = 0;
      for (var v = 0; v < n; v++) {
        if (predecessors[v].isEmpty) continue;
        final saved = List<int>.of(r.height), diff = promote(v);
        if (diff < 0) {
          accepted++;
          r.promotions.add(Promotion(r.rounds, v, diff));
        } else {
          r.height = saved;
        }
      }
      if (accepted == 0) break;
    }
  }
  return r;
}
