import 'dart:io';
part 'rational.dart';
part 'lp_parser.dart';
part 'tableau.dart';
part 'simplex.dart';
part 'branch_bound.dart';

class Model {
  final String name, direction;
  final List<String> variables = [];
  List<Fraction> cost = [];
  final List<Constraint> constraints;
  List<Fraction?> lower = [], upper = [];
  List<bool> integer = [];
  ModelError? error;
  Model(RawModel raw)
    : name = raw.name,
      direction = raw.direction,
      constraints = raw.constraints,
      error = raw.error;
}

Model makeModel(RawModel raw) {
  final m = Model(raw);
  if (m.error != null) return m;
  final index = <String, int>{};
  void register(List<Term> terms) {
    for (final term in terms) {
      if (!index.containsKey(term.name)) {
        index[term.name] = m.variables.length;
        m.variables.add(term.name);
      }
    }
  }

  register(raw.objective);
  for (final c in m.constraints) {
    register(c.terms);
  }
  final n = m.variables.length;
  m.cost = List.filled(n, zero);
  m.lower = List<Fraction?>.filled(n, zero);
  m.upper = List<Fraction?>.filled(n, null);
  m.integer = List.filled(n, false);
  for (final term in raw.objective) {
    final j = index[term.name]!;
    m.cost[j] = m.cost[j].add(term.coefficient);
  }
  for (final c in m.constraints) {
    c.coefficients = List.filled(n, zero);
    for (final term in c.terms) {
      final j = index[term.name]!;
      c.coefficients[j] = c.coefficients[j].add(term.coefficient);
    }
  }
  final seen = <String>{};
  for (final c in m.constraints) {
    if (!seen.add(c.name)) {
      m.error = ModelError(c.line, 'duplicate constraint ${c.name}');
      return m;
    }
  }
  bool inconsistent(int j) {
    final lower = m.lower[j], upper = m.upper[j];
    return lower != null && upper != null && lower.cmp(upper) > 0;
  }

  for (final b in raw.bounds) {
    final j = index[b.name];
    if (j == null) {
      m.error = ModelError(b.line, 'unknown variable ${b.name}');
      return m;
    }
    if (b.kind == 'lower' || b.kind == 'both') m.lower[j] = b.lower;
    if (b.kind == 'upper' || b.kind == 'both') m.upper[j] = b.upper;
    if (inconsistent(j)) {
      m.error = ModelError(b.line, 'inconsistent bounds ${b.name}');
      return m;
    }
  }
  for (final d in raw.integers) {
    for (final name in d.names) {
      final j = index[name];
      if (j == null) {
        m.error = ModelError(d.line, 'unknown variable $name');
        return m;
      }
      m.integer[j] = true;
      final lower = m.lower[j], upper = m.upper[j];
      if (lower != null) m.lower[j] = Fraction(lower.ceil());
      if (upper != null) m.upper[j] = Fraction(upper.floor());
      if (inconsistent(j)) {
        m.error = ModelError(d.line, 'inconsistent bounds $name');
        return m;
      }
    }
  }
  for (final d in raw.binaries) {
    for (final name in d.names) {
      final j = index[name];
      if (j == null) {
        m.error = ModelError(d.line, 'unknown variable $name');
        return m;
      }
      m.integer[j] = true;
      m.lower[j] = zero;
      m.upper[j] = one;
    }
  }
  return m;
}

int integerCount(Model m) => m.integer.where((required) => required).length;

class VariableMap {
  final String kind;
  final Fraction offset;
  final List<int> columns;
  int upperRow = -1;
  VariableMap(this.kind, this.offset, this.columns);
}

class Standard {
  final List<String> columns = [], rows = [], comparisons = [];
  final List<int> columnVariable = [],
      directions = [],
      sigma = [],
      initial = [],
      slack = [];
  final List<bool> artificial = [];
  List<Fraction> costs1 = [], costs2 = [];
  final List<VariableMap> maps = [];
  Fraction constant = zero;
  final int sign;
  final Tableau tableau = Tableau();
  Standard(this.sign);
  List<Fraction> originalValues(List<Fraction> columns, bool direction) {
    final values = List.filled(maps.length, zero);
    for (var j = 0; j < maps.length; j++) {
      final mapping = maps[j];
      if (!direction) values[j] = mapping.offset;
      for (final k in mapping.columns) {
        values[j] = values[j].add(columns[k].mul(Fraction(directions[k])));
      }
    }
    return values;
  }

  List<Fraction> solution() {
    final values = List.filled(columns.length, zero);
    for (var i = 0; i < tableau.basis.length; i++) {
      values[tableau.basis[i]] = tableau.beta[i];
    }
    return originalValues(values, false);
  }
}

Standard standardForm(Model m, List<Fraction?> lower, List<Fraction?> upper) {
  final s = Standard(m.direction == 'maximize' ? -1 : 1);
  int addVariableColumn(String name, int j, int direction) {
    final k = s.columns.length;
    s.columns.add(name);
    s.columnVariable.add(j);
    s.directions.add(direction);
    s.artificial.add(false);
    return k;
  }

  for (var j = 0; j < m.variables.length; j++) {
    final name = m.variables[j], lo = lower[j], up = upper[j];
    VariableMap mapping;
    if (lo != null) {
      mapping = VariableMap('shift', lo, [addVariableColumn(name, j, 1)]);
    } else if (up != null) {
      mapping = VariableMap('reflect', up, [
        addVariableColumn("$name'", j, -1),
      ]);
    } else {
      mapping = VariableMap('split', zero, [
        addVariableColumn('$name+', j, 1),
        addVariableColumn('$name-', j, -1),
      ]);
    }
    s.constant = s.constant.add(m.cost[j].mul(mapping.offset));
    s.maps.add(mapping);
  }
  final decisionColumns = s.columns.length, t = s.tableau;
  for (final c in m.constraints) {
    final row = List.filled(decisionColumns, zero, growable: true);
    var rhs = c.rhs;
    for (var j = 0; j < s.maps.length; j++) {
      final mapping = s.maps[j];
      rhs = rhs.sub(c.coefficients[j].mul(mapping.offset));
      for (final k in mapping.columns) {
        row[k] = c.coefficients[j].mul(Fraction(s.directions[k]));
      }
    }
    t.t.add(row);
    t.beta.add(rhs);
    s.rows.add(c.name);
    s.comparisons.add(c.comparison);
  }
  for (var j = 0; j < s.maps.length; j++) {
    final mapping = s.maps[j], up = upper[j];
    if (mapping.kind == 'shift' && up != null) {
      final row = List.filled(decisionColumns, zero, growable: true);
      row[mapping.columns.first] = one;
      mapping.upperRow = s.rows.length;
      s.rows.add('${m.variables[j]}.ub');
      s.comparisons.add('<=');
      t.t.add(row);
      t.beta.add(up.sub(lower[j]!));
    }
  }
  for (var i = 0; i < s.rows.length; i++) {
    var sigma = 1;
    if (t.beta[i].n < 0) {
      sigma = -1;
      t.beta[i] = t.beta[i].neg();
      for (var k = 0; k < t.t[i].length; k++) {
        t.t[i][k] = t.t[i][k].neg();
      }
      if (s.comparisons[i] == '<=') {
        s.comparisons[i] = '>=';
      } else if (s.comparisons[i] == '>=') {
        s.comparisons[i] = '<=';
      }
    }
    s.sigma.add(sigma);
    s.slack.add(-1);
    s.initial.add(-1);
  }
  int addExtra(String name, int row, Fraction value, bool artificial) {
    final k = s.columns.length;
    s.columns.add(name);
    s.columnVariable.add(-1);
    s.directions.add(0);
    s.artificial.add(artificial);
    for (final r in t.t) {
      r.add(zero);
    }
    t.t[row][k] = value;
    return k;
  }

  for (var i = 0; i < s.rows.length; i++) {
    final comparison = s.comparisons[i];
    if (comparison != '=') {
      s.slack[i] = addExtra(
        's:${s.rows[i]}',
        i,
        Fraction(comparison == '<=' ? 1 : -1),
        false,
      );
      if (comparison == '<=') s.initial[i] = s.slack[i];
    }
  }
  for (var i = 0; i < s.rows.length; i++) {
    if (s.comparisons[i] != '<=')
      s.initial[i] = addExtra('a:${s.rows[i]}', i, one, true);
  }
  s.costs1 = List.filled(s.columns.length, zero);
  s.costs2 = List.filled(s.columns.length, zero);
  for (var k = 0; k < s.columns.length; k++) {
    final j = s.columnVariable[k];
    if (j >= 0) s.costs2[k] = m.cost[j].mul(Fraction(s.sign * s.directions[k]));
    if (s.artificial[k]) s.costs1[k] = one;
  }
  t.basis = List.of(s.initial);
  return s;
}

class LPResult {
  String status = '';
  Fraction objective = zero, w = zero, rate = zero;
  final Standard standard;
  List<Fraction> solution = [], farkas = [], ray = [];
  int phase1 = 0, phase2 = 0, drives = 0, redundant = 0;
  final List<String> log = [];
  int get pivots => phase1 + phase2 + drives;
  LPResult(this.standard);
}

LPResult solveLP(
  Model m,
  List<Fraction?> lower,
  List<Fraction?> upper,
  int number,
  int level,
) {
  final s = standardForm(m, lower, upper),
      r = LPResult(s),
      artificials = s.artificial.where((a) => a).length;
  void emit(int required, String line) {
    if (required <= level) r.log.add(line);
  }

  void display(String heading, List<Fraction> cost, bool firstPhase) {
    if (level < 2) return;
    r.log.addAll(
      s.tableau.display(
        heading,
        s.columns,
        s.rows,
        cost,
        firstPhase ? zero : s.constant,
        firstPhase ? 1 : s.sign,
      ),
    );
  }

  emit(
    0,
    'SOLVE node $number rows ${s.rows.length} columns ${s.columns.length} artificials $artificials',
  );
  for (var j = 0; j < s.maps.length; j++) {
    final mapping = s.maps[j];
    var line = 'MAP ${m.variables[j]} ${mapping.kind}';
    if (mapping.kind != 'split') line += ' ${mapping.offset}';
    if (mapping.kind == 'shift' && upper[j] != null)
      line += ' upper ${upper[j]}';
    emit(1, line);
  }
  for (var i = 0; i < s.sigma.length; i++) {
    if (s.sigma[i] < 0) emit(1, 'FLIP ${s.rows[i]}');
  }
  final all = List.filled(s.columns.length, true),
      real = [for (final art in s.artificial) !art];
  LPResult finish() {
    emit(
      0,
      'RESULT ${r.status} objective ${r.status == 'OPTIMAL' ? r.objective : '-'} phase1 ${r.phase1} phase2 ${r.phase2} drives ${r.drives} redundant ${r.redundant}',
    );
    return r;
  }

  if (artificials > 0) {
    emit(1, 'PHASE 1');
    display('phase 1 start', s.costs1, true);
    final p = phase(s.tableau, s.costs1, all, s.columns, s.rows, (v) => v);
    r.phase1 = p.iterations;
    for (final line in p.lines) {
      emit(1, line);
    }
    final (reduced, w) = s.tableau.reduced(s.costs1);
    r.w = w;
    emit(1, 'PHASE 1 END objective $w iterations ${r.phase1}');
    if (w.n > 0) {
      r.status = 'INFEASIBLE';
      for (var i = 0; i < s.initial.length; i++) {
        final k = s.initial[i];
        r.farkas.add(s.costs1[k].sub(reduced[k]).mul(Fraction(s.sigma[i])));
      }
      display('final', s.costs1, true);
      return finish();
    }
    for (var i = 0; i < s.tableau.basis.length; i++) {
      final k = s.tableau.basis[i];
      if (!s.artificial[k]) continue;
      var q = -1;
      for (var column = 0; column < s.columns.length; column++) {
        if (!s.artificial[column] && s.tableau.t[i][column].n != 0) {
          q = column;
          break;
        }
      }
      if (q < 0) {
        r.redundant++;
        emit(1, 'REDUNDANT row ${s.rows[i]}');
      } else {
        emit(
          1,
          'DRIVE row ${s.rows[i]} enter ${s.columns[q]} leave ${s.columns[k]}',
        );
        s.tableau.pivot(i, q);
        r.drives++;
      }
    }
  }
  Fraction objective(Fraction v) => s.constant.add(v.mul(Fraction(s.sign)));
  emit(1, 'PHASE 2');
  display('phase 2 start', s.costs2, false);
  final p = phase(s.tableau, s.costs2, real, s.columns, s.rows, objective);
  r.phase2 = p.iterations;
  for (final line in p.lines) {
    emit(1, line);
  }
  final (_, z) = s.tableau.reduced(s.costs2);
  r.objective = objective(z);
  r.solution = s.solution();
  r.status = 'OPTIMAL';
  if (p.entering >= 0) {
    r.status = 'UNBOUNDED';
    emit(1, 'UNBOUNDED enter ${s.columns[p.entering]}');
    final delta = List.filled(s.columns.length, zero);
    delta[p.entering] = one;
    for (var i = 0; i < s.tableau.basis.length; i++) {
      delta[s.tableau.basis[i]] = s.tableau.t[i][p.entering].neg();
    }
    r.ray = s.originalValues(delta, true);
    for (var j = 0; j < r.ray.length; j++) {
      r.rate = r.rate.add(m.cost[j].mul(r.ray[j]));
    }
  }
  emit(1, 'PHASE 2 END objective ${r.objective} iterations ${r.phase2}');
  display('final', s.costs2, false);
  return finish();
}

String rangeText(Fraction base, Fraction? limit, bool lower) =>
    limit == null ? boundText(null, lower) : base.add(limit).toString();
List<String> sensitivity(Model m, LPResult root) {
  final s = root.standard, t = s.tableau;
  final (reduced, _) = t.reduced(s.costs2);
  final basic = List.filled(s.columns.length, false), basis = <String>[];
  var primal = 0, dual = 0;
  for (var i = 0; i < t.basis.length; i++) {
    final k = t.basis[i];
    basic[k] = true;
    basis.add(s.columns[k]);
    if (!s.artificial[k] && t.beta[i].n == 0) primal++;
  }
  for (var k = 0; k < reduced.length; k++) {
    if (!basic[k] && !s.artificial[k] && reduced[k].n == 0) dual++;
  }
  final prices = List.filled(m.constraints.length, zero),
      variableReduced = List<Fraction>.of(m.cost);
  var dualObjective = zero;
  for (var i = 0; i < m.constraints.length; i++) {
    final c = m.constraints[i];
    prices[i] = reduced[s.initial[i]].mul(Fraction(-s.sign * s.sigma[i]));
    dualObjective = dualObjective.add(prices[i].mul(c.rhs));
    for (var j = 0; j < c.coefficients.length; j++) {
      variableReduced[j] = variableReduced[j].sub(
        prices[i].mul(c.coefficients[j]),
      );
    }
  }
  for (var j = 0; j < root.solution.length; j++) {
    dualObjective = dualObjective.add(variableReduced[j].mul(root.solution[j]));
  }
  final mode = integerCount(m) > 0 ? 'relaxation' : 'lp',
      out = [
        'MODEL ${m.name} $mode objective ${root.objective}',
        'BASIS ${basis.join(' ')}',
        'DEGENERACY primal $primal dual $dual',
        'DUAL objective $dualObjective',
      ];
  for (var i = 0; i < m.constraints.length; i++) {
    final c = m.constraints[i];
    Fraction? lower, upper;
    var fixed = false;
    for (var row = 0; row < t.basis.length; row++) {
      final rho = t.t[row][s.initial[i]].mul(Fraction(s.sigma[i]));
      if (rho.n == 0) continue;
      if (s.artificial[t.basis[row]]) {
        fixed = true;
        break;
      }
      final limit = t.beta[row].neg().div(rho);
      if (rho.n > 0) {
        if (lower == null || limit.cmp(lower) > 0) lower = limit;
      } else if (upper == null || limit.cmp(upper) < 0) {
        upper = limit;
      }
    }
    final low = fixed ? '${c.rhs}' : rangeText(c.rhs, lower, true),
        high = fixed ? '${c.rhs}' : rangeText(c.rhs, upper, false);
    out.add(
      'CONSTRAINT ${c.name} price ${prices[i]} rhs ${c.rhs} range $low $high',
    );
  }
  for (var j = 0; j < m.variables.length; j++) {
    final mapping = s.maps[j];
    var status = 'basic';
    switch (mapping.kind) {
      case 'split':
        if (!basic[mapping.columns[0]] && !basic[mapping.columns[1]])
          status = 'zero';
        break;
      case 'reflect':
        if (!basic[mapping.columns.first]) status = 'upper';
        break;
      case 'shift':
        if (!basic[mapping.columns.first]) {
          status = 'lower';
        } else if (mapping.upperRow >= 0 && !basic[s.slack[mapping.upperRow]]) {
          status = 'upper';
        }
        break;
    }
    final h = List.filled(s.columns.length, zero);
    for (final k in mapping.columns) {
      h[k] = Fraction(s.sign * s.directions[k]);
    }
    Fraction? lower, upper;
    for (var k = 0; k < s.columns.length; k++) {
      if (basic[k] || s.artificial[k]) continue;
      var eta = h[k];
      for (var row = 0; row < t.basis.length; row++) {
        eta = eta.sub(h[t.basis[row]].mul(t.t[row][k]));
      }
      if (eta.n == 0) continue;
      final limit = reduced[k].neg().div(eta);
      if (eta.n > 0) {
        if (lower == null || limit.cmp(lower) > 0) lower = limit;
      } else if (upper == null || limit.cmp(upper) < 0) {
        upper = limit;
      }
    }
    out.add(
      'VARIABLE ${m.variables[j]} $status value ${root.solution[j]} reduced ${variableReduced[j]} cost ${m.cost[j]} range ${rangeText(m.cost[j], lower, true)} ${rangeText(m.cost[j], upper, false)}',
    );
  }
  return out;
}

String coefficientStats(Model m) {
  final sets = List.generate(4, (_) => <Fraction>[]);
  var nonzeros = 0;
  for (final c in m.constraints) {
    for (final v in c.coefficients) {
      if (v.n != 0) {
        sets[0].add(v.abs());
        nonzeros++;
      }
    }
    if (c.rhs.n != 0) sets[2].add(c.rhs.abs());
  }
  for (final v in m.cost) {
    if (v.n != 0) sets[1].add(v.abs());
  }
  for (var j = 0; j < m.variables.length; j++) {
    for (final v in [m.lower[j], m.upper[j]]) {
      if (v != null && v.n != 0) sets[3].add(v.abs());
    }
  }
  var line = 'STATS nonzeros $nonzeros';
  final names = ['matrix', 'objective', 'rhs', 'bounds'];
  for (var i = 0; i < sets.length; i++) {
    var low = '-', high = '-';
    if (sets[i].isNotEmpty) {
      var minimum = sets[i].first, maximum = minimum;
      for (final v in sets[i].skip(1)) {
        if (v.cmp(minimum) < 0) minimum = v;
        if (v.cmp(maximum) > 0) maximum = v;
      }
      low = '$minimum';
      high = '$maximum';
    }
    line += ' ${names[i]} $low $high';
  }
  return line;
}

List<String> constraintValues(Model m, List<Fraction> solution) {
  final out = <String>[];
  for (final c in m.constraints) {
    var value = zero;
    for (var j = 0; j < c.coefficients.length; j++) {
      value = value.add(c.coefficients[j].mul(solution[j]));
    }
    final margin = c.comparison == '<=' ? c.rhs.sub(value) : value.sub(c.rhs);
    out.add('ROW ${c.name} $value $margin');
  }
  return out;
}

void writeLines(String path, List<String> lines) => File(
  'output/$path',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void main() {
  final settings = readSettings(),
      iterations = <String>[],
      solutions = <String>[],
      sensitivities = <String>[],
      tree = <String>[],
      summary = ['model,status,objective,approx,relaxation,nodes,pivots'],
      statuses = <String, int>{},
      models = readModels();
  var solves = 0,
      p1 = 0,
      p2 = 0,
      drives = 0,
      analyzed = 0,
      integerModels = 0,
      integerNodes = 0,
      integerLimits = 0;
  for (final raw in models) {
    final m = makeModel(raw), error = m.error;
    if (error != null) {
      statuses['ERROR'] = (statuses['ERROR'] ?? 0) + 1;
      iterations.add('MODEL ${m.name} error');
      solutions.addAll([
        'MODEL ${m.name}',
        'STATUS ERROR line ${error.line} ${error.message}',
      ]);
      sensitivities.add('MODEL ${m.name} skipped ERROR');
      summary.add('${m.name},ERROR,-,-,-,0,0');
      continue;
    }
    final level = settings.logs[m.name] ?? settings.level,
        limit = settings.limits[m.name] ?? settings.limit;
    iterations.add('MODEL ${m.name} level $level');
    LPResult solve(List<Fraction?> lower, List<Fraction?> upper, int number) =>
        solveLP(m, lower, upper, number, level);
    ModelResult result;
    final integerVariables = integerCount(m);
    if (integerVariables > 0) {
      result = branchBound(m, limit, solve);
      integerModels++;
      integerNodes += result.solves.length;
      if (result.status == 'NODE_LIMIT') integerLimits++;
      tree.add(
        'MODEL ${m.name} ${m.direction} integers $integerVariables node_limit $limit',
      );
      tree.addAll(result.tree);
    } else {
      final root = solve(m.lower, m.upper, 1);
      result = ModelResult();
      result.status = root.status;
      result.root = root;
      result.solves.add(root);
      if (root.status == 'OPTIMAL') {
        result.hasSolution = true;
        result.objective = root.objective;
        result.solution = List.of(root.solution);
      }
    }
    var pivots = 0;
    for (final lp in result.solves) {
      iterations.addAll(lp.log);
      solves++;
      p1 += lp.phase1;
      p2 += lp.phase2;
      drives += lp.drives;
      pivots += lp.pivots;
    }
    statuses[result.status] = (statuses[result.status] ?? 0) + 1;
    solutions.addAll([
      'MODEL ${m.name} ${m.direction} variables ${m.variables.length} constraints ${m.constraints.length} integers $integerVariables',
      coefficientStats(m),
      'STATUS ${result.status}',
    ]);
    var objective = '-', approx = '-', relaxation = '-';
    if (result.hasSolution) {
      objective = '${result.objective}';
      approx = result.objective.approx();
      solutions.add('OBJECTIVE $objective approx $approx');
    }
    final root = result.root;
    if (root.status == 'OPTIMAL') {
      relaxation = '${root.objective}';
      if (integerVariables > 0)
        solutions.add(
          'RELAXATION $relaxation approx ${root.objective.approx()}',
        );
      sensitivities.addAll(sensitivity(m, root));
      analyzed++;
    } else {
      sensitivities.add('MODEL ${m.name} skipped ${root.status}');
    }
    if (root.status == 'INFEASIBLE') {
      solutions.add('INFEASIBILITY ${root.w}');
      for (var i = 0; i < root.farkas.length; i++) {
        solutions.add('FARKAS ${root.standard.rows[i]} ${root.farkas[i]}');
      }
    }
    if (result.hasSolution || result.status == 'UNBOUNDED') {
      final values = result.hasSolution ? result.solution : root.solution;
      for (var j = 0; j < values.length; j++) {
        solutions.add('VALUE ${m.variables[j]} ${values[j]}');
      }
    }
    if (result.status == 'UNBOUNDED') {
      for (var j = 0; j < root.ray.length; j++) {
        solutions.add('RAY ${m.variables[j]} ${root.ray[j]}');
      }
      solutions.add('RATE ${root.rate}');
    }
    if (result.hasSolution)
      solutions.addAll(constraintValues(m, result.solution));
    if (integerVariables > 0) solutions.add('NODES ${result.solves.length}');
    solutions.add('PIVOTS $pivots');
    summary.add(
      '${m.name},${result.status},$objective,$approx,$relaxation,${result.solves.length},$pivots',
    );
  }
  iterations.add(
    'TOTAL solves $solves phase1 $p1 phase2 $p2 drives $drives pivots ${p1 + p2 + drives}',
  );
  solutions.add(
    'SUMMARY models ${models.length} optimal ${statuses['OPTIMAL'] ?? 0} infeasible ${statuses['INFEASIBLE'] ?? 0} unbounded ${statuses['UNBOUNDED'] ?? 0} node_limit ${statuses['NODE_LIMIT'] ?? 0} error ${statuses['ERROR'] ?? 0}',
  );
  sensitivities.add(
    'SUMMARY analyzed $analyzed skipped ${models.length - analyzed}',
  );
  tree.add(
    'SUMMARY models $integerModels nodes $integerNodes node_limit $integerLimits',
  );
  Directory('output').createSync(recursive: true);
  writeLines('iterations.txt', iterations);
  writeLines('solutions.txt', solutions);
  writeLines('sensitivity.txt', sensitivities);
  writeLines('bnb_tree.txt', tree);
  writeLines('summary.csv', summary);
}
