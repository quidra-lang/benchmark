import 'dart:io';
import 'dart:math';

part 'network_io.dart';
part 'learning.dart';
part 'factors.dart';
part 'elimination.dart';
part 'sampling.dart';

class Structure {
  final List<List<int>> children, ancestors, descendants, blankets, spouses;
  final List<int> topological = [], depth;
  int moralEdges = 0;
  Structure(int size)
    : children = List.generate(size, (_) => <int>[]),
      ancestors = List.generate(size, (_) => <int>[]),
      descendants = List.generate(size, (_) => <int>[]),
      blankets = List.generate(size, (_) => <int>[]),
      spouses = List.generate(size, (_) => <int>[]),
      depth = List.filled(size, 0);
}

class Posterior {
  List<int> relevant = [], eliminate = [];
  List<Factor> factors = [];
  late Plan minfill, given;
  late Factor finalFactor;
  List<double> probabilities = [];
  double z = 0;
  final Map<int, List<double>> marginals = {};
}

String format(double x) {
  final s = x.toStringAsFixed(4);
  return s == '-0.0000' ? '0.0000' : s;
}

void write(String path, StringBuffer s) =>
    File(path).writeAsStringSync(s.toString());
String yes(bool b) => b ? 'yes' : 'no';
List<int> allVariables(Network n) => [
  for (var i = 0; i < n.variables.length; i++) i,
];
String variableNames(List<int> vars, Network n) =>
    vars.isEmpty ? '-' : vars.map((v) => n.variables[v].name).join(' ');
String numbers(List<double> a) => a.map(format).join(' ');
String integers(List<int> a) => a.join(' ');
List<int> closure(List<int> start, List<List<int>> links) {
  final seen = start.toSet(), queue = List.of(start);
  for (var pos = 0; pos < queue.length; pos++) {
    for (final v in links[queue[pos]]) {
      if (seen.add(v)) queue.add(v);
    }
  }
  return queue..sort();
}

Structure structure(Network n) {
  final size = n.variables.length,
      s = Structure(n.variables.length),
      parents = [for (final v in n.variables) v.parents];
  for (var v = 0; v < size; v++) {
    for (final p in n.variables[v].parents) {
      s.children[p].add(v);
    }
  }
  final chosen = <int>{};
  while (s.topological.length < size) {
    for (var v = 0; v < size; v++) {
      if (chosen.contains(v)) continue;
      var ready = true, depth = 0;
      for (final p in n.variables[v].parents) {
        if (!chosen.contains(p)) {
          ready = false;
          break;
        }
        depth = max(depth, s.depth[p] + 1);
      }
      if (ready) {
        chosen.add(v);
        s.topological.add(v);
        s.depth[v] = depth;
        break;
      }
    }
  }
  final moral = <(int, int)>{};
  for (var v = 0; v < size; v++) {
    final variable = n.variables[v];
    s.ancestors[v] = without(closure([v], parents), {v});
    s.descendants[v] = without(closure([v], s.children), {v});
    final spouses = <int>{};
    for (final c in s.children[v]) {
      for (final p in parents[c]) {
        if (p != v && !parents[v].contains(p) && !s.children[v].contains(p))
          spouses.add(p);
      }
    }
    s.spouses[v] = spouses.toList()..sort();
    s.blankets[v] = variableUnion([parents[v], s.children[v], s.spouses[v]]);
    final family = variableUnion([
      [v],
      variable.parents,
    ]);
    for (var i = 0; i < family.length; i++) {
      for (final b in family.skip(i + 1)) {
        moral.add((family[i], b));
      }
    }
  }
  s.moralEdges = moral.length;
  return s;
}

List<int> evidenceVariables(List<Evidence> e) =>
    e.map((ev) => ev.v).toSet().toList()..sort();
List<int> ancestorClosure(List<int> vars, Network n) =>
    closure(vars, [for (final v in n.variables) v.parents]);
List<Factor> initialFactors(List<int> relevant, List<Evidence> e, Network n) =>
    [for (final v in relevant) reduce(cptFactor(v, n), e, n)];
(List<double>, double) normalize(Factor f) {
  var z = 0.0;
  for (final v in f.values) {
    z += v;
  }
  return (f.values.map((v) => v / z).toList(), z);
}

Posterior posterior(List<int> q, List<Evidence> e, Network n) {
  final r = Posterior(), ev = evidenceVariables(e);
  r.relevant = ancestorClosure(variableUnion([q, ev]), n);
  r.factors = initialFactors(r.relevant, e, n);
  r.eliminate = without(r.relevant, variableUnion([q, ev]).toSet());
  r.minfill = plan(r.factors, r.eliminate, 'minfill', n);
  r.given = plan(r.factors, r.eliminate, 'given', n);
  final used = n.settings.method == 'given' ? r.given : r.minfill;
  r.finalFactor = execute(r.factors, used, false, e, n).finalFactor;
  final (p, z) = normalize(r.finalFactor);
  r.probabilities = p;
  r.z = z;
  for (final v in q) {
    r.marginals[v] = List.filled(n.variables[v].states.length, 0.0);
  }
  var i = 0;
  assignments(r.finalFactor.variables, n, (a) {
    for (final v in q) {
      r.marginals[v]![a[v]] += r.probabilities[i];
    }
    i++;
  });
  return r;
}

bool agree(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 1e-9) return false;
  }
  return true;
}

double jointProbability(List<int> vars, List<int> a, Network n) {
  var value = 1.0;
  for (final v in vars) {
    final co = n.variables[v];
    value *= co.theta[parentCombination(co.parents, a, n)][a[v]];
  }
  return value;
}

(int, String) enumerateQuery(Posterior r, List<Evidence> e, Network n) {
  final u = without(r.relevant, evidenceVariables(e).toSet()),
      count = assignmentCount(u, n);
  if (count > n.settings.enumeration) return (count, 'skipped');
  final values = List.filled(r.probabilities.length, 0.0);
  assignments(u, n, (a) {
    for (final ev in e) {
      a[ev.v] = ev.s;
    }
    final i = factorIndex(r.finalFactor.variables, a, n);
    values[i] += jointProbability(r.relevant, a, n);
  });
  final (p, z) = normalize(Factor([], values));
  return (
    count,
    agree(p, r.probabilities) && (log(z) - log(r.z)).abs() <= 1e-9
        ? 'agree'
        : 'disagree',
  );
}

(int, String) enumerateMPE(
  List<int> elimination,
  List<Evidence> e,
  EliminationResult result,
  Network n,
) {
  final count = assignmentCount(elimination, n);
  if (count > n.settings.enumeration) return (count, 'skipped');
  var best = -1.0;
  var assignment = <int>[];
  final all = allVariables(n);
  assignments(elimination, n, (a) {
    for (final ev in e) {
      a[ev.v] = ev.s;
    }
    final value = jointProbability(all, a, n);
    if (value > best) {
      best = value;
      assignment = List.of(a);
    }
  });
  var same = true;
  for (var i = 0; i < assignment.length; i++) {
    if (result.assignment[i] != assignment[i]) same = false;
  }
  return (
    count,
    same && (log(best) - log(result.finalFactor.values[0])).abs() <= 1e-9
        ? 'agree'
        : 'disagree',
  );
}

Evidence evidence(String token, Network n) {
  final a = token.split('='), v = n.names[a[0]]!;
  return Evidence(v, n.variables[v].states.indexOf(a[1]));
}

String evidenceName(Evidence e, Network n) =>
    '${n.variables[e.v].name}=${n.variables[e.v].states[e.s]}';
(List<int>, List<Evidence>, List<int>) parseQuery(
  List<String> fields,
  Network n,
) {
  final q = <int>[], e = <Evidence>[], counts = <int>[];
  var observed = false;
  for (var i = 1; i < fields.length; i++) {
    final token = fields[i];
    if (token == 'COUNTS') {
      counts.addAll(fields.skip(i + 1).map(int.parse));
      break;
    }
    if (token == '|') {
      observed = true;
      continue;
    }
    if (observed) {
      e.add(evidence(token, n));
    } else {
      q.add(n.names[token]!);
    }
  }
  return (q, e, counts);
}

void reportPlan(StringBuffer s, String name, Plan p, Network n) {
  s.writeln('order $name');
  for (final step in p.steps) {
    s.writeln(
      'step ${n.variables[step.v].name} fill ${step.fill} scope ${variableNames(step.scope, n)} entries ${step.size}',
    );
  }
  s.writeln('cost max ${p.max} total ${p.total}');
}

void reportElimination(
  StringBuffer s,
  List<int> relevant,
  List<int> elimination,
  Plan minfill,
  Plan given,
  bool agreement,
  int count,
  String enumeration,
  Network n,
) {
  s.writeln('relevant ${variableNames(relevant, n)}');
  s.writeln(
    'pruned ${variableNames(without(allVariables(n), relevant.toSet()), n)}',
  );
  s.writeln('eliminate ${variableNames(elimination, n)}');
  reportPlan(s, 'minfill', minfill, n);
  reportPlan(s, 'given', given, n);
  s.writeln('used ${n.settings.method}');
  s.writeln('orders_agree ${yes(agreement)}');
  s.writeln('enumeration $count $enumeration');
}

(List<int>, bool) bayesBall(
  List<int> x,
  List<int> y,
  List<int> z,
  Network n,
  Structure s,
) {
  final observed = z.toSet(),
      ancestors = ancestorClosure(z, n).toSet(),
      xset = x.toSet(),
      queue = <(int, int)>[],
      seen = <(int, int)>{};
  void push((int, int) b) {
    if (seen.add(b)) queue.add(b);
  }

  for (final v in x) {
    push((v, 0));
  }
  final reachable = <int>{};
  for (var pos = 0; pos < queue.length; pos++) {
    final (v, direction) = queue[pos];
    if (!observed.contains(v) && !xset.contains(v)) reachable.add(v);
    if (direction == 0 && !observed.contains(v)) {
      for (final p in n.variables[v].parents) {
        push((p, 0));
      }
      for (final c in s.children[v]) {
        push((c, 1));
      }
    }
    if (direction == 1) {
      if (!observed.contains(v)) {
        for (final c in s.children[v]) {
          push((c, 1));
        }
      }
      if (ancestors.contains(v)) {
        for (final p in n.variables[v].parents) {
          push((p, 0));
        }
      }
    }
  }
  final result = reachable.toList()..sort();
  return (result, !y.any(reachable.contains));
}

List<int> decodeAssignment(List<int> vars, int index, Network n) {
  final a = List.filled(n.variables.length, 0);
  for (final v in vars.reversed) {
    a[v] = index % n.variables[v].states.length;
    index ~/= n.variables[v].states.length;
  }
  return a;
}

(double, int) conditionalInformation(
  List<int> x,
  List<int> y,
  List<int> z,
  Network n,
) {
  final w = variableUnion([x, y, z]),
      xz = variableUnion([x, z]),
      yz = variableUnion([y, z]),
      cw = <int, int>{},
      cxz = <int, int>{},
      cyz = <int, int>{},
      cz = <int, int>{};
  void increment(Map<int, int> counts, int key) {
    counts[key] = (counts[key] ?? 0) + 1;
  }

  for (final a in n.samples) {
    increment(cw, factorIndex(w, a, n));
    increment(cxz, factorIndex(xz, a, n));
    increment(cyz, factorIndex(yz, a, n));
    increment(cz, factorIndex(z, a, n));
  }
  final keys = cw.keys.toList()..sort();
  var cmi = 0.0;
  for (final key in keys) {
    final a = decodeAssignment(w, key, n), count = cw[key]!;
    final num = count * cz[factorIndex(z, a, n)]!,
        den = cxz[factorIndex(xz, a, n)]! * cyz[factorIndex(yz, a, n)]!;
    cmi += count / n.samples.length * log(num.toDouble() / den.toDouble());
  }
  final df =
      (assignmentCount(x, n) - 1) *
      (assignmentCount(y, n) - 1) *
      assignmentCount(z, n);
  return (cmi, df);
}

List<int> path(int a, int b, int ignoreX, int ignoreY, Structure s) {
  final queue = [a], predecessor = {a: -1};
  for (var pos = 0; pos < queue.length; pos++) {
    final v = queue[pos];
    for (final c in s.children[v]) {
      if (v == ignoreX && c == ignoreY) continue;
      if (predecessor.containsKey(c)) continue;
      predecessor[c] = v;
      if (c == b) {
        final result = <int>[];
        for (var x = b; x >= 0; x = predecessor[x]!) {
          result.add(x);
        }
        return result.reversed.toList();
      }
      queue.add(c);
    }
  }
  return [];
}

void reportQuery(
  StringBuffer answer,
  StringBuffer eliminationOut,
  List<int> q,
  List<Evidence> e,
  Network n,
) {
  final r = posterior(q, e, n);
  answer.writeln('log_evidence ${format(log(r.z))}');
  if (e.isNotEmpty) {
    var conflict = 0.0;
    for (final ev in e) {
      conflict += log(posterior([], [ev], n).z);
    }
    conflict -= log(r.z);
    answer.writeln('conflict ${format(conflict)}');
  }
  if (q.length >= 2) {
    var index = 0;
    assignments(r.finalFactor.variables, n, (a) {
      final names = [
        for (final v in r.finalFactor.variables)
          evidenceName(Evidence(v, a[v]), n),
      ];
      answer.writeln(
        'joint ${names.join(' ')} ${format(r.probabilities[index])}',
      );
      index++;
    });
  }
  for (final v in q) {
    final parts = ['marginal', n.variables[v].name];
    for (var state = 0; state < n.variables[v].states.length; state++) {
      parts
        ..add(n.variables[v].states[state])
        ..add(format(r.marginals[v]![state]));
    }
    answer.writeln(parts.join(' '));
  }
  for (var j = 0; j < e.length; j++) {
    final rest = [
          for (var i = 0; i < e.length; i++)
            if (i != j) e[i],
        ],
        dropped = posterior(q, rest, n);
    var shift = 0.0;
    for (final v in q) {
      for (var state = 0; state < r.marginals[v]!.length; state++) {
        shift = max(
          shift,
          (r.marginals[v]![state] - dropped.marginals[v]![state]).abs(),
        );
      }
    }
    answer.writeln('drop ${evidenceName(e[j], n)} shift ${format(shift)}');
  }
  final (a, za) = normalize(
    execute(r.factors, r.minfill, false, e, n).finalFactor,
  );
  final (b, zb) = normalize(
    execute(r.factors, r.given, false, e, n).finalFactor,
  );
  final agreement = agree(a, b) && (log(za) - log(zb)).abs() <= 1e-9;
  final (count, enumeration) = enumerateQuery(r, e, n);
  reportElimination(
    eliminationOut,
    r.relevant,
    r.eliminate,
    r.minfill,
    r.given,
    agreement,
    count,
    enumeration,
    n,
  );
}

void reportMPE(
  StringBuffer answer,
  StringBuffer eliminationOut,
  List<Evidence> e,
  Network n,
) {
  final all = allVariables(n),
      elim = without(all, evidenceVariables(e).toSet());
  final initial = initialFactors(all, e, n),
      minfill = plan(initial, elim, 'minfill', n),
      given = plan(initial, elim, 'given', n);
  final a = execute(initial, minfill, true, e, n),
      b = execute(initial, given, true, e, n);
  final result = n.settings.method == 'given' ? b : a;
  final assignment = [
        for (final v in all) evidenceName(Evidence(v, result.assignment[v]), n),
      ],
      m = result.finalFactor.values[0],
      z = e.isEmpty ? 1.0 : posterior([], e, n).z;
  answer.writeln('assignment ${assignment.join(' ')}');
  answer.writeln('log_joint ${format(log(m))}');
  answer.writeln('log_evidence ${format(log(z))}');
  answer.writeln('posterior ${format(m / z)}');
  for (final v in elim) {
    final keep = without(elim, {v}),
        p = plan(initial, keep, n.settings.method, n);
    final f = execute(initial, p, true, e, n).finalFactor;
    var second = -1, best = -1.0;
    for (var state = 0; state < f.values.length; state++) {
      final value = f.values[state];
      if (state != result.assignment[v] && value > best) {
        best = value;
        second = state;
      }
    }
    answer.writeln(
      'margin ${n.variables[v].name} ${n.variables[v].states[second]} ${format(log(m) - log(best))}',
    );
  }
  var agreement =
      (log(a.finalFactor.values[0]) - log(b.finalFactor.values[0])).abs() <=
      1e-9;
  for (var i = 0; i < a.assignment.length; i++) {
    if (a.assignment[i] != b.assignment[i]) agreement = false;
  }
  final (count, enumeration) = enumerateMPE(elim, e, result, n);
  reportElimination(
    eliminationOut,
    all,
    elim,
    minfill,
    given,
    agreement,
    count,
    enumeration,
    n,
  );
}

void reportSample(
  StringBuffer answer,
  StringBuffer csv,
  int queryNumber,
  List<int> q,
  List<Evidence> e,
  List<int> counts,
  Generator generator,
  Structure s,
  Network n,
) {
  final exact = posterior(q, e, n);
  for (final v in q) {
    final parts = ['exact', n.variables[v].name];
    for (var state = 0; state < n.variables[v].states.length; state++) {
      parts
        ..add(n.variables[v].states[state])
        ..add(format(exact.marginals[v]![state]));
    }
    answer.writeln(parts.join(' '));
  }
  final weighted = {
    for (final v in q) v: List.filled(n.variables[v].states.length, 0.0),
  };
  var weight = 0.0, squared = 0.0, target = 0;
  for (var count = 1; count <= counts.last; count++) {
    final (a, w) = generator.weightedSample(e, s.topological, n);
    weight += w;
    squared += w * w;
    for (final v in q) {
      weighted[v]![a[v]] += w;
    }
    if (count != counts[target]) continue;
    var maximumError = 0.0;
    for (final v in q) {
      for (var state = 0; state < n.variables[v].states.length; state++) {
        final estimate = weighted[v]![state] / weight,
            truth = exact.marginals[v]![state];
        final error = (estimate - truth).abs();
        maximumError = max(maximumError, error);
        csv.writeln(
          '$queryNumber,$count,${n.variables[v].name},${n.variables[v].states[state]},${format(estimate)},${format(truth)},${format(error)}',
        );
      }
    }
    answer.writeln(
      'after $count weight ${format(weight)} ess ${format(weight * weight / squared)} max_error ${format(maximumError)}',
    );
    target++;
  }
}

void reportPrediction(StringBuffer answer, int v, Structure s, Network n) {
  final k = n.variables[v].states.length,
      confusion = List.generate(
        n.variables[v].states.length,
        (_) => List.filled(n.variables[v].states.length, 0),
      );
  var loss = 0.0;
  for (final sample in n.samples) {
    final a = List.of(sample), values = List.filled(k, 0.0);
    var total = 0.0;
    for (var state = 0; state < k; state++) {
      a[v] = state;
      final co = n.variables[v];
      var g = co.theta[parentCombination(co.parents, a, n)][state];
      for (final c in s.children[v]) {
        final child = n.variables[c];
        g *= child.theta[parentCombination(child.parents, a, n)][a[c]];
      }
      values[state] = g;
      total += g;
    }
    var prediction = 0, best = -1.0;
    for (var state = 0; state < k; state++) {
      final p = values[state] / total;
      if (p > best) {
        best = p;
        prediction = state;
      }
    }
    final actual = sample[v];
    confusion[actual][prediction]++;
    loss += log(values[actual] / total);
  }
  var correct = 0;
  for (var state = 0; state < k; state++) {
    correct += confusion[state][state];
  }
  answer.writeln('blanket ${variableNames(s.blankets[v], n)}');
  answer.writeln(
    'accuracy $correct/${n.samples.length} ${format(correct / n.samples.length)}',
  );
  answer.writeln('log_loss ${format(-loss / n.samples.length)}');
  answer.writeln('predicted ${n.variables[v].states.join(' ')}');
  for (var state = 0; state < k; state++) {
    answer.writeln(
      'actual ${n.variables[v].states[state]} ${integers(confusion[state])}',
    );
  }
}

List<int> namedVariables(List<String> names, Network n) =>
    variableUnion([names.map((s) => n.names[s]!).toList()]);
void reportStructureQuery(
  StringBuffer out,
  String query,
  List<String> fields,
  Network n,
  Structure s,
) {
  if (fields[0] == 'DSEP') {
    final parts = query.split(' | '),
        x = namedVariables(parts[0].split(' ').skip(1).toList(), n),
        y = namedVariables(parts[1].split(' '), n);
    final z = parts.length == 3
        ? namedVariables(parts[2].split(' '), n)
        : <int>[];
    final (reachable, separated) = bayesBall(x, y, z, n, s);
    out.writeln('result ${separated ? 'separated' : 'connected'}');
    out.writeln('reachable ${variableNames(reachable, n)}');
    final (cmi, df) = conditionalInformation(x, y, z, n);
    out.writeln(
      'data cmi ${format(cmi)} g2 ${format(2 * n.samples.length * cmi)} df $df',
    );
  } else if (fields[0] == 'BLANKET') {
    final v = n.names[fields[1]]!,
        rest = without(
          allVariables(n),
          variableUnion([
            [n.names[fields[1]]!],
            s.blankets[n.names[fields[1]]!],
          ]).toSet(),
        );
    final (_, separated) = bayesBall([v], rest, s.blankets[v], n, s);
    out.writeln('parents ${variableNames(n.variables[v].parents, n)}');
    out.writeln('children ${variableNames(s.children[v], n)}');
    out.writeln('spouses ${variableNames(s.spouses[v], n)}');
    out.writeln('blanket ${variableNames(s.blankets[v], n)}');
    out.writeln('rest ${variableNames(rest, n)}');
    out.writeln('rest_separated ${yes(separated)}');
  } else {
    final operation = fields[1],
        x = n.names[fields[2]]!,
        y = n.names[fields[3]]!;
    final exists = n.variables[y].parents.contains(x);
    if (operation == 'ADD' && exists) {
      out.writeln('result exists');
      return;
    }
    if (operation != 'ADD' && !exists) {
      out.writeln('result missing');
      return;
    }
    var cycle = <int>[];
    if (operation == 'ADD') {
      final p = path(y, x, -1, -1, s);
      if (p.isNotEmpty) cycle = [x, ...p];
    }
    if (operation == 'REVERSE') {
      final p = path(x, y, x, y, s);
      if (p.isNotEmpty) cycle = [y, ...p];
    }
    if (cycle.isNotEmpty) {
      out.writeln(
        'result cycle ${cycle.map((v) => n.variables[v].name).join(' -> ')}',
      );
      return;
    }
    out.writeln('result ok');
    final parentsY = variableUnion([n.variables[y].parents]),
        beforeY = familyScore(y, parentsY, n);
    var afterParentsY = without(parentsY, {x});
    if (operation == 'ADD')
      afterParentsY = variableUnion([
        parentsY,
        [x],
      ]);
    final afterY = familyScore(y, afterParentsY, n);
    out.writeln(
      'family ${n.variables[y].name} before ${format(beforeY)} after ${format(afterY)}',
    );
    var change = afterY - beforeY;
    if (operation == 'REVERSE') {
      final parentsX = variableUnion([n.variables[x].parents]),
          beforeX = familyScore(x, parentsX, n);
      final afterX = familyScore(
        x,
        variableUnion([
          parentsX,
          [y],
        ]),
        n,
      );
      out.writeln(
        'family ${n.variables[x].name} before ${format(beforeX)} after ${format(afterX)}',
      );
      change += (afterX - beforeX);
    }
    out.writeln(
      'delta ${format(change)} ${change > 0 ? 'improves' : 'worsens'}',
    );
  }
}

void main() {
  final n = readInput();
  for (var v = 0; v < n.variables.length; v++) {
    final f = learn(v, n.variables[v].parents, n), co = n.variables[v];
    co.counts = f.counts;
    co.learned = f.learned;
    co.theta = co.source == 'GIVEN' ? co.given : co.learned;
  }
  final s = structure(n), all = allVariables(n);
  final initial = initialFactors(all, [], n),
      minfill = plan(initial, all, 'minfill', n),
      given = plan(initial, all, 'given', n);
  final cpts = StringBuffer(),
      structureOut = StringBuffer(),
      answers = StringBuffer(),
      eliminationOut = StringBuffer(),
      samplingCSV = StringBuffer(
        'query,samples,variable,state,estimate,exact,abs_error\n',
      );
  var ll = 0.0, parameters = 0;
  for (var v = 0; v < n.variables.length; v++) {
    final co = n.variables[v];
    cpts.writeln('variable ${co.name} source ${co.source}');
    cpts.writeln('states ${co.states.join(' ')}');
    cpts.writeln('parents ${variableNames(co.parents, n)}');
    var row = 0;
    assignments(co.parents, n, (a) {
      final combination = [
            for (final p in co.parents) evidenceName(Evidence(p, a[p]), n),
          ],
          name = combination.isEmpty ? '-' : combination.join(' ');
      cpts.writeln(
        'row $name counts ${integers(co.counts[row])} probs ${numbers(co.theta[row])}',
      );
      row++;
    });
    final localLL = logLikelihood(co.counts, co.theta),
        d = (co.states.length - 1) * co.counts.length;
    ll += localLL;
    parameters += d;
    cpts.writeln(
      'loglik ${format(localLL)} parameters $d bic ${format(localLL - d * log(n.samples.length) / 2)}',
    );
    final marginal = posterior([v], [], n).marginals[v]!,
        frequencies = List.filled(co.states.length, 0.0);
    for (final a in n.samples) {
      frequencies[a[v]]++;
    }
    for (var i = 0; i < frequencies.length; i++) {
      frequencies[i] /= n.samples.length;
    }
    cpts.writeln(
      'marginal model ${numbers(marginal)} data ${numbers(frequencies)}',
    );
    if (co.source == 'LEARNED') {
      var difference = '-';
      if (co.given.isNotEmpty) {
        var value = 0.0;
        for (var r = 0; r < co.learned.length; r++) {
          for (var state = 0; state < co.learned[r].length; state++) {
            value = max(
              value,
              (co.learned[r][state] - co.given[r][state]).abs(),
            );
          }
        }
        difference = format(value);
      }
      cpts.writeln('given_difference $difference');
    }
    cpts.writeln();
  }
  cpts.writeln(
    'network samples ${n.samples.length} pseudocount ${format(n.settings.alpha)} loglik ${format(ll)} parameters $parameters bic ${format(ll - parameters * log(n.samples.length) / 2)}',
  );
  var edges = 0;
  final roots = <int>[], leaves = <int>[];
  for (var v = 0; v < n.variables.length; v++) {
    final co = n.variables[v];
    edges += co.parents.length;
    if (co.parents.isEmpty) roots.add(v);
    if (s.children[v].isEmpty) leaves.add(v);
  }
  structureOut.writeln('variables ${all.length} edges $edges');
  structureOut.writeln('topological_order ${variableNames(s.topological, n)}');
  structureOut.writeln('roots ${variableNames(roots, n)}');
  structureOut.writeln('leaves ${variableNames(leaves, n)}');
  structureOut.writeln(
    'moral_edges ${s.moralEdges} width minfill ${minfill.width} given ${given.width}',
  );
  for (var v = 0; v < n.variables.length; v++) {
    final co = n.variables[v];
    structureOut.writeln(
      'variable ${co.name} states ${co.states.length} parents ${co.parents.length} children ${s.children[v].length} depth ${s.depth[v]} ancestors ${s.ancestors[v].length} descendants ${s.descendants[v].length} blanket ${s.blankets[v].length}',
    );
  }
  final generator = Generator(n.settings.seed);
  var answerBlocks = 0, eliminationBlocks = 0;
  for (var index = 0; index < n.queries.length; index++) {
    final query = n.queries[index],
        fields = query.split(' '),
        number = index + 1;
    if (fields[0] == 'DSEP' || fields[0] == 'BLANKET' || fields[0] == 'EDGE') {
      structureOut.writeln();
      structureOut.writeln('query $number $query');
      reportStructureQuery(structureOut, query, fields, n, s);
      continue;
    }
    if (answerBlocks > 0) answers.writeln();
    answerBlocks++;
    answers.writeln('query $number $query');
    if (fields[0] == 'QUERY') {
      if (eliminationBlocks > 0) eliminationOut.writeln();
      eliminationBlocks++;
      eliminationOut.writeln('query $number $query');
      final (q, e, _) = parseQuery(fields, n);
      reportQuery(answers, eliminationOut, q, e, n);
    } else if (fields[0] == 'MPE') {
      if (eliminationBlocks > 0) eliminationOut.writeln();
      eliminationBlocks++;
      eliminationOut.writeln('query $number $query');
      final e = fields.skip(1).map((token) => evidence(token, n)).toList();
      reportMPE(answers, eliminationOut, e, n);
    } else if (fields[0] == 'SAMPLE') {
      final (q, e, counts) = parseQuery(fields, n);
      reportSample(answers, samplingCSV, number, q, e, counts, generator, s, n);
    } else {
      reportPrediction(answers, n.names[fields[1]]!, s, n);
    }
  }
  Directory('output').createSync(recursive: true);
  final outputs = {
    'cpts.txt': cpts,
    'structure.txt': structureOut,
    'answers.txt': answers,
    'elimination.txt': eliminationOut,
    'sampling.csv': samplingCSV,
  };
  for (final entry in outputs.entries) {
    write('output/${entry.key}', entry.value);
  }
}
