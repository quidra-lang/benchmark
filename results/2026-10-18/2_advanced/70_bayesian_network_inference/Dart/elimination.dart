part of 'main.dart';

class Step {
  final int v, fill, size;
  final List<int> scope;
  Step(this.v, this.fill, this.size, this.scope);
}

class Plan {
  final List<Step> steps = [];
  int max = 0, total = 0, width = 0;
}

class EliminationResult {
  final Factor finalFactor;
  final List<int> assignment;
  EliminationResult(this.finalFactor, this.assignment);
}

Plan plan(
  List<Factor> factors,
  List<int> elimination,
  String method,
  Network n,
) {
  final size = n.variables.length,
      edges = List.generate(
        n.variables.length,
        (_) => List.filled(n.variables.length, false),
      ),
      active = List.filled(n.variables.length, false);
  for (final f in factors) {
    for (final a in f.variables) {
      active[a] = true;
      for (final b in f.variables) {
        if (a != b) edges[a][b] = true;
      }
    }
  }
  final remaining = elimination.toSet(),
      orderRank = {
        for (var i = 0; i < n.settings.order.length; i++)
          n.settings.order[i]: i,
      },
      result = Plan();
  while (remaining.isNotEmpty) {
    var chosen = -1, chosenFill = 0, chosenDegree = 0;
    var neighbors = <int>[];
    for (var v = 0; v < size; v++) {
      if (!remaining.contains(v)) continue;
      final ns = [
        for (var u = 0; u < size; u++)
          if (active[u] && edges[v][u]) u,
      ];
      var fill = 0;
      for (var i = 0; i < ns.length; i++) {
        for (final b in ns.skip(i + 1)) {
          if (!edges[ns[i]][b]) fill++;
        }
      }
      var better = chosen < 0;
      if (!better) {
        better = method == 'given'
            ? orderRank[v]! < orderRank[chosen]!
            : fill < chosenFill ||
                  (fill == chosenFill &&
                      (ns.length < chosenDegree ||
                          (ns.length == chosenDegree && v < chosen)));
      }
      if (better) {
        chosen = v;
        chosenFill = fill;
        chosenDegree = ns.length;
        neighbors = ns;
      }
    }
    final scope = variableUnion([
          [chosen],
          neighbors,
        ]),
        entries = assignmentCount(scope, n);
    result.steps.add(Step(chosen, chosenFill, entries, scope));
    result.max = max(result.max, entries);
    result.total += entries;
    result.width = max(result.width, scope.length - 1);
    for (final a in neighbors) {
      for (final b in neighbors) {
        if (a != b) edges[a][b] = true;
      }
    }
    active[chosen] = false;
    remaining.remove(chosen);
  }
  return result;
}

EliminationResult execute(
  List<Factor> initial,
  Plan p,
  bool maximum,
  List<Evidence> evidence,
  Network n,
) {
  var factors = List.of(initial);
  final products = <int, Factor>{};
  for (final step in p.steps) {
    final bucket = <Factor>[], remaining = <Factor>[];
    for (final f in factors) {
      (f.variables.contains(step.v) ? bucket : remaining).add(f);
    }
    final f = product(bucket, n);
    products[step.v] = f;
    factors = [...remaining, eliminate(f, step.v, maximum, n)];
  }
  final assignment = <int>[];
  if (maximum) {
    assignment.addAll(List.filled(n.variables.length, 0));
    for (final e in evidence) {
      assignment[e.v] = e.s;
    }
    for (final step in p.steps.reversed) {
      final v = step.v;
      var best = -1.0, bestState = 0;
      for (var state = 0; state < n.variables[v].states.length; state++) {
        assignment[v] = state;
        final value = products[v]!.value(assignment, n);
        if (value > best) {
          best = value;
          bestState = state;
        }
      }
      assignment[v] = bestState;
    }
  }
  return EliminationResult(product(factors, n), assignment);
}
