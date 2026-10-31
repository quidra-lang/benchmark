part of 'main.dart';

class SearchNode {
  final List<Fraction?> lower, upper;
  final int depth, parent;
  final String branch;
  final Fraction parentValue;
  SearchNode(
    this.lower,
    this.upper, {
    this.depth = 0,
    this.parent = 0,
    this.branch = 'root',
    this.parentValue = zero,
  });
}

class ModelResult {
  String status = '';
  Fraction objective = zero;
  bool hasSolution = false;
  List<Fraction> solution = [];
  final List<LPResult> solves = [];
  late LPResult root;
  final List<String> tree = [];
}

bool better(Model m, Fraction a, Fraction b) =>
    m.direction == 'maximize' ? a.cmp(b) > 0 : a.cmp(b) < 0;
ModelResult branchBound(
  Model m,
  int limit,
  LPResult Function(List<Fraction?>, List<Fraction?>, int) solve,
) {
  final stack = [SearchNode(List.of(m.lower), List.of(m.upper))],
      r = ModelResult();
  var incumbents = 0, pruned = 0, infeasible = 0;
  while (stack.isNotEmpty) {
    if (r.solves.length == limit) {
      r.status = 'NODE_LIMIT';
      break;
    }
    final node = stack.removeLast(),
        number = r.solves.length + 1,
        lp = solve(node.lower, node.upper, number);
    r.solves.add(lp);
    if (number == 1) r.root = lp;
    var outcome = '';
    if (lp.status == 'INFEASIBLE') {
      outcome = 'infeasible';
      infeasible++;
    } else if (lp.status == 'UNBOUNDED') {
      outcome = 'unbounded';
      r.status = 'UNBOUNDED';
    } else if (r.hasSolution && !better(m, lp.objective, r.objective)) {
      outcome = 'pruned';
      pruned++;
    } else {
      var j = -1;
      for (var k = 0; k < m.integer.length; k++) {
        if (m.integer[k] && !lp.solution[k].whole) {
          j = k;
          break;
        }
      }
      if (j < 0) {
        r.hasSolution = true;
        r.objective = lp.objective;
        r.solution = List.of(lp.solution);
        outcome = 'incumbent';
        incumbents++;
      } else {
        final value = lp.solution[j],
            down = Fraction(value.floor()),
            up = Fraction(value.ceil()),
            lower = List<Fraction?>.of(node.lower),
            upper = List<Fraction?>.of(node.upper);
        lower[j] = up;
        upper[j] = down;
        stack.addAll([
          SearchNode(
            lower,
            List.of(node.upper),
            depth: node.depth + 1,
            parent: number,
            branch: '${m.variables[j]}>=$up',
            parentValue: lp.objective,
          ),
          SearchNode(
            List.of(node.lower),
            upper,
            depth: node.depth + 1,
            parent: number,
            branch: '${m.variables[j]}<=$down',
            parentValue: lp.objective,
          ),
        ]);
        outcome = 'branch ${m.variables[j]} $value';
      }
    }
    final parent = node.parent == 0 ? '-' : '${node.parent}',
        lpValue = lp.status == 'OPTIMAL'
            ? '${lp.objective}'
            : lp.status.toLowerCase();
    r.tree.add(
      'NODE $number depth ${node.depth} parent $parent branch ${node.branch} lp $lpValue pivots ${lp.pivots} action $outcome',
    );
    if (r.status == 'UNBOUNDED') break;
  }
  if (r.status.isEmpty) r.status = r.hasSolution ? 'OPTIMAL' : 'INFEASIBLE';
  Fraction? bound = r.hasSolution ? r.objective : null;
  if (r.status == 'NODE_LIMIT') {
    for (final node in stack.reversed) {
      r.tree.add(
        'OPEN parent ${node.parent} branch ${node.branch} bound ${node.parentValue}',
      );
      if (bound == null || better(m, node.parentValue, bound))
        bound = node.parentValue;
    }
  }
  final objective = r.hasSolution ? '${r.objective}' : '-',
      boundValue = bound?.toString() ?? '-';
  r.tree.add(
    'RESULT ${r.status} objective $objective nodes ${r.solves.length} incumbents $incumbents pruned $pruned infeasible $infeasible open ${stack.length} bound $boundValue',
  );
  return r;
}
