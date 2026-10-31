part of 'main.dart';

typedef Mutex = Set<(int, int)>;
(int, int) mutexPair(int a, int b) => a < b ? (a, b) : (b, a);
bool mutexHas(Mutex mutex, int a, int b) =>
    a != b && mutex.contains(mutexPair(a, b));
bool compatible(Mutex mutex, State facts) {
  final values = numbers(facts);
  for (var i = 0; i < values.length; i++) {
    for (final b in values.skip(i + 1)) {
      if (mutexHas(mutex, values[i], b)) return false;
    }
  }
  return true;
}

class GraphElement {
  final int action, fact;
  final State pre, add, del;
  GraphElement(this.action, this.pre, this.add, this.del, {this.fact = -1});
}

class GraphPlanResult {
  String status = '';
  List<int> plan = [];
  List<List<int>> layers = [];
  int searched = 0, memoHits = 0, tried = 0;
  final List<String> logs = [];
  final int complementCount;
  GraphPlanResult(this.complementCount);
}

class PlanningGraph {
  final List<GraphElement> actions;
  final State goal;
  final List<State> factLevels;
  final List<Mutex> factMutex = [<(int, int)>{}], actionMutex = [];
  final List<List<GraphElement>> actionLevels = [];
  final Set<(int, State)> memo = {};
  final GraphPlanResult result;
  PlanningGraph(this.actions, State initial, this.goal, this.result)
    : factLevels = [initial];
  List<List<int>>? extract(int level, State goals) {
    if (level == 0) return [];
    final key = (level, goals);
    if (memo.contains(key)) {
      result.memoHits++;
      return null;
    }
    result.searched++;
    final values = numbers(goals),
        elements = actionLevels[level - 1],
        mutex = actionMutex[level - 1];
    List<List<int>>? assign(int at, List<int> chosen) {
      var covered = BigInt.zero;
      for (final i in chosen) {
        covered |= elements[i].add;
      }
      while (at < values.length && has(covered, values[at])) {
        at++;
      }
      if (at == values.length) {
        var pre = BigInt.zero;
        for (final i in chosen) {
          pre |= elements[i].pre;
        }
        final layers = extract(level - 1, pre);
        if (layers == null) return null;
        final actions = [
          for (final i in chosen)
            if (elements[i].action >= 0) elements[i].action,
        ]..sort();
        return [...layers, actions];
      }
      final fact = values[at],
          achievers = [
            for (var i = 0; i < elements.length; i++)
              if (elements[i].action < 0 && elements[i].fact == fact) i,
            for (var i = 0; i < elements.length; i++)
              if (elements[i].action >= 0 && has(elements[i].add, fact)) i,
          ];
      for (final i in achievers) {
        if (chosen.any((j) => mutexHas(mutex, i, j))) continue;
        result.tried++;
        final layers = assign(at + 1, [...chosen, i]);
        if (layers != null) return layers;
      }
      return null;
    }

    final layers = assign(0, []);
    if (layers == null) memo.add(key);
    return layers;
  }

  void expand() {
    final facts = factLevels.last,
        previousMutex = factMutex.last,
        elements = <GraphElement>[];
    var realActions = 0;
    for (final a in actions) {
      if (contains(facts, a.pre) && compatible(previousMutex, a.pre)) {
        elements.add(a);
        realActions++;
      }
    }
    for (final p in numbers(facts)) {
      final set = factSet([p]);
      elements.add(GraphElement(-1, set, set, BigInt.zero, fact: p));
    }
    final mutex = <(int, int)>{};
    for (var i = 0; i < elements.length; i++) {
      final a = elements[i];
      for (var j = i + 1; j < elements.length; j++) {
        final b = elements[j];
        var exclusive =
            intersects(a.del, b.pre | b.add) ||
            intersects(b.del, a.pre | a.add);
        if (!exclusive) {
          for (final p in numbers(a.pre)) {
            for (final q in numbers(b.pre)) {
              if (mutexHas(previousMutex, p, q)) {
                exclusive = true;
                break;
              }
            }
            if (exclusive) break;
          }
        }
        if (exclusive) mutex.add(mutexPair(i, j));
      }
    }
    result.logs.add(
      'action level ${actionLevels.length}: actions=$realActions noops=${numbers(facts).length} mutexes=${mutex.length}',
    );
    var next = BigInt.zero;
    final achievers = <int, List<int>>{};
    for (var i = 0; i < elements.length; i++) {
      next |= elements[i].add;
      for (final p in numbers(elements[i].add)) {
        achievers.putIfAbsent(p, () => []).add(i);
      }
    }
    final nextMutex = <(int, int)>{}, values = numbers(next);
    for (var i = 0; i < values.length; i++) {
      final p = values[i];
      for (final q in values.skip(i + 1)) {
        var exclusive = true;
        for (final x in achievers[p]!) {
          for (final y in achievers[q]!) {
            if (x == y || !mutexHas(mutex, x, y)) {
              exclusive = false;
              break;
            }
          }
          if (!exclusive) break;
        }
        if (exclusive) nextMutex.add(mutexPair(p, q));
      }
    }
    actionLevels.add(elements);
    actionMutex.add(mutex);
    factLevels.add(next);
    factMutex.add(nextMutex);
  }
}

GraphPlanResult graphPlan(
  List<GraphElement> actions,
  State initial,
  State goal,
  int complementCount,
  int limit,
) {
  final result = GraphPlanResult(complementCount),
      graph = PlanningGraph(actions, initial, goal, result);
  for (var level = 0; ; level++) {
    final facts = graph.factLevels[level], mutex = graph.factMutex[level];
    result.logs.add(
      'fact level $level: facts=${numbers(facts).length} mutexes=${mutex.length}',
    );
    final attempted = contains(facts, goal) && compatible(mutex, goal);
    if (attempted) {
      final searched = result.searched,
          hits = result.memoHits,
          layers = graph.extract(level, goal);
      result.logs.add(
        'extract level $level: ${layers == null ? 'fail' : 'success'} searched=${result.searched - searched} memo_hits=${result.memoHits - hits}',
      );
      if (layers != null) {
        result.status = 'solved';
        result.layers = layers;
        result.plan = [for (final layer in layers) ...layer];
        return result;
      }
    } else if (level >= 1 &&
        numbers(facts).length == numbers(graph.factLevels[level - 1]).length &&
        mutex.length == graph.factMutex[level - 1].length) {
      result.status = 'unreachable';
      return result;
    }
    if (level == limit) {
      result.status = 'level limit';
      return result;
    }
    graph.expand();
  }
}
