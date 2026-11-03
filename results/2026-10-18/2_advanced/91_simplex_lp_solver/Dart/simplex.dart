part of 'main.dart';

class PhaseResult {
  int iterations = 0, entering = -1;
  final List<String> lines = [];
}

PhaseResult phase(
  Tableau tableau,
  List<Fraction> cost,
  List<bool> candidates,
  List<String> columns,
  List<String> rows,
  Fraction Function(Fraction) objective,
) {
  final result = PhaseResult();
  while (true) {
    final (reduced, _) = tableau.reduced(cost);
    var q = -1;
    for (var k = 0; k < reduced.length; k++) {
      if (candidates[k] && reduced[k].n < 0) {
        q = k;
        break;
      }
    }
    if (q < 0) return result;
    var p = -1, ratio = zero;
    for (var i = 0; i < tableau.t.length; i++) {
      final row = tableau.t[i];
      if (row[q].n <= 0) continue;
      final value = tableau.beta[i].div(row[q]);
      if (p < 0 ||
          value.cmp(ratio) < 0 ||
          value.cmp(ratio) == 0 && tableau.basis[i] < tableau.basis[p]) {
        p = i;
        ratio = value;
      }
    }
    if (p < 0) {
      result.entering = q;
      return result;
    }
    final leave = tableau.basis[p], before = reduced[q];
    tableau.pivot(p, q);
    result.iterations++;
    final (_, z) = tableau.reduced(cost);
    result.lines.add(
      'PIVOT ${result.iterations} enter ${columns[q]} reduced $before leave ${columns[leave]} row ${rows[p]} ratio $ratio objective ${objective(z)}',
    );
  }
}
