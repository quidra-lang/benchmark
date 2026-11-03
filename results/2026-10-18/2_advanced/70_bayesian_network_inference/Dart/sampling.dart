part of 'main.dart';

class Generator {
  int state;
  Generator(this.state);
  double next() {
    state = 48271 * state % 2147483647;
    return state / 2147483647;
  }

  (List<int>, double) weightedSample(
    List<Evidence> evidence,
    List<int> topological,
    Network n,
  ) {
    final observed = {for (final e in evidence) e.v: e.s},
        a = List.filled(n.variables.length, 0);
    var weight = 1.0;
    for (final v in topological) {
      final variable = n.variables[v],
          row = parentCombination(variable.parents, a, n),
          state = observed[v];
      if (state != null) {
        a[v] = state;
        weight *= variable.theta[row][state];
      } else {
        a[v] = selectState(variable.theta[row], next());
      }
    }
    return (a, weight);
  }
}

int selectState(List<double> probs, double u) {
  var c = 0.0;
  for (var s = 0; s < probs.length; s++) {
    c += probs[s];
    if (u < c) return s;
  }
  return probs.length - 1;
}
