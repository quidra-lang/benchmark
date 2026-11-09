import 'dart:io';
import 'dart:math' as math;
part 'cnf_io.dart';
part 'encoders.dart';
part 'preprocess.dart';
part 'dpll.dart';
part 'report.dart';

const commands = [
  'SOLVE',
  'ENUM',
  'CORE',
  'QUEENS',
  'PIGEON',
  'COLOR',
  'CHROMATIC',
];
const argumentTypes = {
  'SOLVE': ['file'],
  'ENUM': ['file', 'limit'],
  'CORE': ['file'],
  'QUEENS': ['small', 'limit'],
  'PIGEON': ['small', 'small', 'limit'],
  'COLOR': ['graph', 'color', 'limit'],
  'CHROMATIC': ['graph', 'color'],
};
final namePattern = RegExp(r'^[a-z0-9_]{1,20}$');
List<String> readLines(String path) => File(path).readAsLinesSync();

class Graph {
  final String name;
  final int vertices;
  final edges = <(int, int)>[];
  String? invalid;
  Graph(this.name, this.vertices);
}

Map<String, Graph> loadGraphs() {
  final graphs = <String, Graph>{}, lines = readLines('input/graphs.txt');
  Graph? current;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (current == null) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final tokens = line.split(' ');
      current = Graph(tokens[1], int.parse(tokens[2]));
      continue;
    }
    if (line == 'END') {
      current.edges.sort(
        (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
      );
      graphs[current.name] = current;
      current = null;
      continue;
    }
    if (current.invalid != null) continue;
    final tokens = line.split(' ');
    String? reason;
    if (tokens.length != 2 ||
        !validNumber(tokens[0]) ||
        !validNumber(tokens[1])) {
      reason = 'bad edge line';
    } else {
      final a = int.parse(tokens[0]), b = int.parse(tokens[1]);
      if (a < 1 || a > current.vertices || b < 1 || b > current.vertices) {
        reason = 'vertex out of range';
      } else if (a == b) {
        reason = 'self loop';
      } else {
        final edge = (math.min(a, b), math.max(a, b));
        if (current.edges.contains(edge)) {
          reason = 'duplicate edge';
        } else {
          current.edges.add(edge);
        }
      }
    }
    if (reason != null) current.invalid = '$reason at line ${index + 1}';
  }
  return graphs;
}

class Solution {
  final Formula formula;
  final Preparation preparation;
  final models = <List<bool>>[], trace = <String>[];
  final stats = SearchStats();
  String status = 'UNSAT', stop = 'limit';
  int rounds = 0, colors = 0;
  Solution(this.formula, this.preparation);
  int get removed => preparation.counts['removed'] ?? 0;
}

class ModelAnalysis {
  int failureModel = 0, failureClause = 0;
  final trueDistribution = <int>[],
      safe = <int>[],
      diversity = <int>[],
      backbone = <int>[];
}

class Core {
  final clauses = <int>[];
  int decisions = 0, conflicts = 0;
}

class Job {
  final int number;
  final String text, command;
  final List<String> args;
  String? error;
  Graph? graph;
  int colors = 0, chromatic = 0, aggregateRounds = 0, aggregateRemoved = 0;
  late final Solution solution;
  final attempts = <Solution>[], aggregate = SearchStats();
  ModelAnalysis? analysis;
  Core? core;
  Job(this.number, this.text, this.command, this.args);
}

List<Job> loadJobs() {
  final jobs = <Job>[];
  for (final line in readLines('input/jobs.txt')) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final tokens = line.split(' ');
    jobs.add(Job(jobs.length + 1, line, tokens[0], tokens.sublist(1)));
  }
  return jobs;
}

String? validateJob(Job j, Map<String, Graph> graphs) {
  final types = argumentTypes[j.command];
  if (types == null) return 'unknown command ${j.command}';
  if (j.args.length != types.length) return 'wrong argument count';
  for (var i = 0; i < types.length; i++) {
    final kind = types[i], argument = j.args[i];
    if (kind == 'file') {
      if (!argument.endsWith('.cnf') ||
          !namePattern.hasMatch(argument.substring(0, argument.length - 4)))
        return 'bad file name $argument';
    } else if (kind == 'graph') {
      final g = graphs[argument];
      if (g == null) return 'unknown graph $argument';
      if (g.invalid != null) return 'invalid graph $argument: ${g.invalid}';
    } else {
      if (!validNumber(argument)) return 'bad number $argument';
      final n = int.parse(argument),
          maximum = {'small': 8, 'color': 6, 'limit': 200}[kind]!;
      if (n < 1 || n > maximum) return 'out of range $argument';
    }
  }
  return null;
}

List<int> greedyColoring(Graph g) {
  final degree = List.filled(g.vertices + 1, 0),
      neighbors = List.generate(g.vertices + 1, (_) => <int>[]);
  for (final (a, b) in g.edges) {
    degree[a]++;
    degree[b]++;
    neighbors[a].add(b);
    neighbors[b].add(a);
  }
  final order = List.generate(g.vertices, (i) => i + 1)
    ..sort(
      (a, b) => degree[a] != degree[b]
          ? degree[b].compareTo(degree[a])
          : a.compareTo(b),
    );
  final colors = List.filled(g.vertices + 1, 0);
  for (final v in order) {
    final used = {
      for (final n in neighbors[v])
        if (colors[n] > 0) colors[n],
    };
    var c = 1;
    while (used.contains(c)) {
      c++;
    }
    colors[v] = c;
  }
  return colors.sublist(1);
}

Solution solveFormula(Formula f, int limit) {
  final prep = preprocess(f, limit == 1),
      s = Solution(f, prep),
      blocking = <List<int>>[];
  if (prep.emptyClause > 0) {
    s.stop = 'preprocess';
  } else {
    while (s.models.length < limit) {
      s.rounds++;
      final (model, events, stats) = runRound(f.variables, [
        ...prep.clauses,
        ...blocking,
      ]);
      if (s.rounds == 1) s.trace.addAll(events);
      s.stats.add(stats);
      if (model == null) {
        s.stop = 'all';
        break;
      }
      for (final entry in prep.fixed.entries) {
        model[entry.key] = entry.value;
      }
      s.models.add(model);
      blocking.add([for (final v in prep.active) model[v] ? -v : v]);
    }
  }
  s.status = s.models.isEmpty ? 'UNSAT' : 'SAT';
  return s;
}

bool trueLiteral(List<bool> model, int literal) =>
    literal > 0 ? model[literal] : !model[-literal];
bool satisfies(List<bool> model, List<List<int>> clauses) =>
    clauses.every((c) => c.any((lit) => trueLiteral(model, lit)));
ModelAnalysis? analyzeModels(Solution s) {
  if (s.models.isEmpty) return null;
  final a = ModelAnalysis();
  for (var mi = 0; mi < s.models.length; mi++) {
    for (var ci = 0; ci < s.formula.clauses.length; ci++) {
      if (!s.formula.clauses[ci].any((lit) => trueLiteral(s.models[mi], lit))) {
        a.failureModel = mi + 1;
        a.failureClause = ci + 1;
        break;
      }
    }
    if (a.failureModel > 0) break;
  }
  final first = s.models.first;
  for (final c in s.formula.clauses) {
    a.trueDistribution.add(c.where((lit) => trueLiteral(first, lit)).length);
  }
  for (var v = 1; v <= s.formula.variables; v++) {
    final inverted = [...first];
    inverted[v] = !inverted[v];
    if (satisfies(inverted, s.formula.clauses)) a.safe.add(v);
  }
  for (var i = 0; i < s.models.length; i++) {
    for (var j = i + 1; j < s.models.length; j++) {
      var distance = 0;
      for (var v = 1; v <= s.formula.variables; v++) {
        if (s.models[i][v] != s.models[j][v]) distance++;
      }
      a.diversity.add(distance);
    }
  }
  for (var v = 1; v <= s.formula.variables; v++) {
    if (s.models.every((m) => m[v] == first[v]))
      a.backbone.add(first[v] ? v : -v);
  }
  return a;
}

Core unsatCore(Formula f) {
  final remaining = List.filled(f.clauses.length, true), core = Core();
  for (var remove = 0; remove < f.clauses.length; remove++) {
    final clauses = [
          for (var i = 0; i < f.clauses.length; i++)
            if (remaining[i] && i != remove) f.clauses[i],
        ],
        test = solveFormula(Formula(f.variables, clauses), 1);
    core.decisions += test.stats.decisions;
    core.conflicts += test.stats.conflicts;
    if (test.status == 'UNSAT') remaining[remove] = false;
  }
  core.clauses.addAll([
    for (var i = 0; i < remaining.length; i++)
      if (remaining[i]) i + 1,
  ]);
  return core;
}

void executeJobs(List<Job> jobs, Map<String, Graph> graphs) {
  for (final j in jobs) {
    j.error = validateJob(j, graphs);
    if (j.error != null) continue;
    final args = j.args;
    try {
      if (j.command == 'CHROMATIC') {
        j.graph = graphs[args[0]];
        Solution? last;
        for (var colors = 1; colors <= int.parse(args[1]); colors++) {
          final s = solveFormula(coloring(j.graph!, colors), 1);
          s.colors = colors;
          j.attempts.add(s);
          j.aggregate.add(s.stats);
          j.aggregateRounds += s.rounds;
          j.aggregateRemoved += s.removed;
          last = s;
          j.colors = colors;
          if (s.status == 'SAT') {
            j.chromatic = colors;
            break;
          }
        }
        j.solution = last!;
      } else {
        late Formula f;
        var limit = 1;
        switch (j.command) {
          case 'SOLVE' || 'ENUM' || 'CORE':
            f = readDimacs(args[0]);
            if (j.command == 'ENUM') limit = int.parse(args[1]);
          case 'QUEENS':
            f = queens(int.parse(args[0]));
            limit = int.parse(args[1]);
          case 'PIGEON':
            f = pigeon(int.parse(args[0]), int.parse(args[1]));
            limit = int.parse(args[2]);
          case 'COLOR':
            j.graph = graphs[args[0]];
            j.colors = int.parse(args[1]);
            f = coloring(j.graph!, j.colors);
            limit = int.parse(args[2]);
        }
        final s = solveFormula(f, limit);
        j.solution = s;
        j.aggregate.add(s.stats);
        j.aggregateRounds = s.rounds;
        j.aggregateRemoved = s.removed;
        if (j.command == 'CORE' && s.status == 'UNSAT') j.core = unsatCore(f);
      }
    } on CnfError catch (e) {
      j.error = e.message;
      continue;
    }
    j.analysis = analyzeModels(j.solution);
  }
}

int sum(Iterable<int> values) =>
    values.fold(0, (total, value) => total + value);
String formulaSummary(Formula f) {
  final lengths = f.clauses.map((c) => c.length).toList();
  return 'variables=${f.variables} clauses=${f.clauses.length} literals=${sum(lengths)} lengths=${frequency(lengths)}';
}

String graphSummary(Graph g) {
  final degrees = List.filled(g.vertices + 1, 0);
  for (final (a, b) in g.edges) {
    degrees[a]++;
    degrees[b]++;
  }
  final greedy = greedyColoring(g);
  return 'vertices=${g.vertices} edges=${g.edges.length} max_degree=${degrees.reduce(math.max)} greedy=${greedy.reduce(math.max)}';
}

List<String> preprocessingReport(Preparation p) {
  final c = p.counts, r = p.records;
  final lines = [
    'preprocess pure=${p.pure ? 'on' : 'off'} tautologies=${c['tautologies'] ?? 0} duplicate_literals=${c['duplicate_literals'] ?? 0} unit_fixed=${c['unit_fixed'] ?? 0} unit_removed=${c['unit_removed'] ?? 0} subsumed=${c['subsumed'] ?? 0} pure_fixed=${c['pure_fixed'] ?? 0} pure_removed=${c['pure_removed'] ?? 0} removed=${c['removed'] ?? 0}',
    'removed_clauses tautology=${numberList(r['tautology'] ?? [])} unit=${numberList(r['unit'] ?? [])} subsumed=${numberList(r['subsumed'] ?? [])} pure=${numberList(r['pure'] ?? [])}',
  ];
  if (p.emptyClause > 0)
    return [...lines, 'simplified empty_clause=${p.emptyClause}'];
  final lengths = p.clauses.map((c) => c.length).toList(),
      variables = p.fixed.keys.toList()..sort();
  lines.addAll([
    'simplified clauses=${p.clauses.length} literals=${sum(lengths)} lengths=${frequency(lengths)} fixed=${p.fixed.length} active=${p.active.length}',
    'fixed literals=${numberList(variables.map((v) => p.fixed[v]! ? v : -v).toList())}',
  ]);
  return lines;
}

String searchReport(SearchStats s) =>
    'search ${named([('decisions', s.decisions), ('propagations', s.propagations), ('conflicts', s.conflicts), ('max_depth', s.maxDepth)])}';
List<String> verificationReport(Solution s, ModelAnalysis? a) {
  if (a == null) return [];
  return [
    a.failureModel > 0
        ? 'verify failed model=${a.failureModel} clause=${a.failureClause}'
        : 'verify ok models=${s.models.length} clauses=${s.formula.clauses.length} true_literals=${frequency(a.trueDistribution)}',
  ];
}

String safeFlipReport(ModelAnalysis a) =>
    'flips safe=${a.safe.length} variables=${numberList(a.safe)}';
List<String> analysisReport(Solution s, ModelAnalysis? a) => a == null
    ? []
    : [
        safeFlipReport(a),
        if (a.diversity.isNotEmpty)
          'diversity pairs=${a.diversity.length} min_distance=${a.diversity.reduce(math.min)} max_distance=${a.diversity.reduce(math.max)}',
        if (s.stop == 'all')
          'backbone size=${a.backbone.length} literals=${numberList(a.backbone)}',
      ];
String traceReport(List<String> events) => events.isEmpty
    ? 'trace -'
    : 'trace ${events.take(12).join(' ')}${events.length > 12 ? ' +${events.length - 12}' : ''}';
List<String> standardResult(Job j) {
  final s = j.solution, core = j.core;
  return [
    heading(j),
    if (j.command == 'COLOR') 'graph ${graphSummary(j.graph!)}',
    'formula ${formulaSummary(s.formula)}',
    ...preprocessingReport(s.preparation),
    'result ${s.status} models=${s.models.length} rounds=${s.rounds} stop=${s.stop}',
    searchReport(s.stats),
    if (s.rounds > 0) traceReport(s.trace),
    ...verificationReport(s, j.analysis),
    ...analysisReport(s, j.analysis),
    if (core != null)
      'core size=${core.clauses.length} decisions=${core.decisions} conflicts=${core.conflicts} clauses=${numberList(core.clauses)}',
  ];
}

List<String> chromaticResult(Job j) => [
  heading(j),
  'graph ${graphSummary(j.graph!)}',
  for (final s in j.attempts)
    'attempt k=${s.colors} clauses=${s.formula.clauses.length} removed=${s.removed} result=${s.status} stop=${s.stop} decisions=${s.stats.decisions} propagations=${s.stats.propagations} conflicts=${s.stats.conflicts} max_depth=${s.stats.maxDepth}',
  'result ${j.solution.status} chromatic=${j.chromatic == 0 ? '-' : j.chromatic} attempts=${j.attempts.length}',
  searchReport(j.aggregate),
  if (j.solution.status == 'SAT') ...[
    ...verificationReport(j.solution, j.analysis),
    safeFlipReport(j.analysis!),
  ],
];
List<Job> validJobs(List<Job> jobs) =>
    jobs.where((j) => j.error == null).toList();
List<String> resultsSummary(List<Job> jobs) {
  final valid = validJobs(jobs), totals = SearchStats();
  var sat = 0, models = 0, rounds = 0, removed = 0;
  for (final j in valid) {
    if (j.solution.status == 'SAT') sat++;
    models += j.solution.models.length;
    rounds += j.aggregateRounds;
    removed += j.aggregateRemoved;
    totals.add(j.aggregate);
  }
  final lines = [
    'SUMMARY jobs=${jobs.length} sat=$sat unsat=${valid.length - sat} error=${jobs.length - valid.length}',
    'totals models=$models rounds=$rounds decisions=${totals.decisions} propagations=${totals.propagations} conflicts=${totals.conflicts} removed_clauses=$removed',
  ];
  for (final command in commands) {
    final members = valid.where((j) => j.command == command).toList();
    if (members.isEmpty) continue;
    final counters = SearchStats();
    var sat = 0;
    for (final j in members) {
      counters.add(j.aggregate);
      if (j.solution.status == 'SAT') sat++;
    }
    lines.add(
      'command $command jobs=${members.length} sat=$sat unsat=${members.length - sat} decisions=${counters.decisions} propagations=${counters.propagations} conflicts=${counters.conflicts}',
    );
  }
  if (valid.isNotEmpty) {
    for (final kind in ['hardest', 'deepest', 'busiest']) {
      final key = kind == 'hardest'
          ? 'conflicts'
          : kind == 'deepest'
          ? 'max_depth'
          : 'propagations';
      int value(Job j) => kind == 'hardest'
          ? j.aggregate.conflicts
          : kind == 'deepest'
          ? j.aggregate.maxDepth
          : j.aggregate.propagations;
      var best = valid.first;
      for (final j in valid.skip(1)) {
        if (value(j) > value(best)) best = j;
      }
      lines.add('$kind job=${best.number} $key=${value(best)}');
    }
  }
  return lines;
}

List<List<String>> resultParagraphs(List<Job> jobs) => [
  for (final j in jobs)
    j.error != null
        ? [heading(j), 'error ${j.error}']
        : j.command == 'CHROMATIC'
        ? chromaticResult(j)
        : standardResult(j),
  resultsSummary(jobs),
];
List<List<String>> modelParagraphs(List<Job> jobs) => [
  for (final j in validJobs(jobs))
    if (j.solution.models.isNotEmpty)
      [
        heading(j),
        for (var i = 0; i < j.solution.models.length; i++) ...[
          'model ${i + 1}',
          ...modelLines(j.solution.models[i]),
        ],
      ],
];
bool sequenceLess(List<int> a, List<int> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return a[i] < b[i];
  }
  return false;
}

(List<int>, int) queensCanonical(List<int> columns) {
  final n = columns.length,
      variants = List.generate(8, (_) => List.filled(columns.length, 0));
  for (var row = 0; row < n; row++) {
    final r = row + 1,
        c = columns[row],
        transforms = [
          (r, c),
          (c, n + 1 - r),
          (n + 1 - r, n + 1 - c),
          (n + 1 - c, r),
          (r, n + 1 - c),
          (n + 1 - r, c),
          (c, r),
          (n + 1 - c, n + 1 - r),
        ];
    for (var i = 0; i < 8; i++) {
      final (r, c) = transforms[i];
      variants[i][r - 1] = c;
    }
  }
  var best = variants.first;
  final distinct = <String>{};
  for (final v in variants) {
    distinct.add(numberList(v));
    if (sequenceLess(v, best)) best = v;
  }
  return (best, distinct.length);
}

List<int> canonicalColoring(List<int> colors) {
  final numbers = <int, int>{}, result = <int>[];
  for (final c in colors) {
    final number = numbers.putIfAbsent(c, () => numbers.length + 1);
    result.add(number);
  }
  return result;
}

class ModelClass {
  final int number, first, orbit;
  final List<int> canonical;
  int found = 0;
  ModelClass(this.number, this.first, this.orbit, this.canonical);
}

(List<(List<int>, ModelClass, bool)>, List<ModelClass>) classesForModels(
  List<List<int>> columns,
  bool queen,
) {
  final table = <String, ModelClass>{},
      classes = <ModelClass>[],
      assignments = <(List<int>, ModelClass, bool)>[];
  for (var i = 0; i < columns.length; i++) {
    final value = columns[i];
    final (canonical, orbit) = queen
        ? queensCanonical(value)
        : (canonicalColoring(value), 0);
    final key = numberList(canonical);
    var group = table[key];
    if (group == null) {
      group = ModelClass(classes.length + 1, i + 1, orbit, canonical);
      table[key] = group;
      classes.add(group);
    }
    group.found++;
    assignments.add((value, group, i + 1 == group.first));
  }
  return (assignments, classes);
}

List<String> queensBoards(Job j) {
  final n = int.parse(j.args[0]),
      columns = [for (final model in j.solution.models) positions(model, n, n)];
  final (assignments, classes) = classesForModels(columns, true);
  return [
    'QUEENS job=${j.number} n=$n',
    for (var i = 0; i < assignments.length; i++) ...[
      'solution ${i + 1} columns=${numberList(assignments[i].$1)} class=${assignments[i].$2.number}',
      if (assignments[i].$3) ...queensBoard(assignments[i].$1),
    ],
    for (final g in classes)
      'class ${g.number} orbit=${g.orbit} found=${g.found} first=${g.first} canonical=${numberList(g.canonical)}',
    'summary solutions=${j.solution.models.length} stop=${j.solution.stop} classes=${classes.length}',
  ];
}

List<String> pigeonBoards(Job j) {
  final p = int.parse(j.args[0]),
      h = int.parse(j.args[1]),
      lines = [
        'PIGEON job=${j.number} pigeons=${j.args[0]} holes=${j.args[1]}',
      ];
  for (var i = 0; i < j.solution.models.length; i++) {
    final places = positions(j.solution.models[i], p, h),
        empty = [
          for (var hole = 1; hole <= h; hole++)
            if (!places.contains(hole)) hole,
        ];
    lines.add(
      'assignment ${i + 1} holes=${numberList(places)} empty=${numberList(empty)}',
    );
  }
  var expected = 1;
  if (p > h) {
    expected = 0;
  } else {
    for (var value = h; value > h - p; value--) {
      expected *= value;
    }
  }
  lines.add(
    'summary assignments=${j.solution.models.length} stop=${j.solution.stop} expected=$expected',
  );
  return lines;
}

List<String> coloringBoards(Job j) {
  final g = j.graph!,
      k = j.colors,
      decoded = [
        for (final model in j.solution.models) positions(model, g.vertices, k),
      ];
  final (assignments, classes) = classesForModels(decoded, false);
  final greedy = greedyColoring(g),
      lines = [
        '${j.command} job=${j.number} graph=${g.name} vertices=${g.vertices} edges=${g.edges.length} colors=$k',
        'greedy used=${greedy.reduce(math.max)} colors=${numberList(greedy)}',
      ];
  for (var i = 0; i < assignments.length; i++) {
    final (value, group, _) = assignments[i];
    final sizes = [
      for (var color = 1; color <= k; color++)
        value.where((c) => c == color).length,
    ];
    lines.add(
      'coloring ${i + 1} colors=${numberList(value)} used=${value.toSet().length} sizes=${numberList(sizes)} class=${group.number}',
    );
  }
  for (final g in classes) {
    lines.add(
      'class ${g.number} found=${g.found} first=${g.first} canonical=${numberList(g.canonical)}',
    );
  }
  lines.add(
    'summary colorings=${j.solution.models.length} stop=${j.solution.stop} classes=${classes.length}',
  );
  return lines;
}

List<List<String>> boardsParagraphs(List<Job> jobs) => [
  for (final j in validJobs(jobs))
    if (j.command == 'QUEENS')
      queensBoards(j)
    else if (j.command == 'PIGEON')
      pigeonBoards(j)
    else if (j.command == 'COLOR' || j.command == 'CHROMATIC')
      coloringBoards(j),
];
List<String> statsLines(List<Job> jobs) => [
  'job,command,status,variables,clauses,removed_clauses,decisions,propagations,conflicts,max_depth,models,rounds',
  for (final j in validJobs(jobs))
    '${j.number},${j.command},${j.solution.status},${j.solution.formula.variables},${j.solution.formula.clauses.length},${j.aggregateRemoved},${j.aggregate.decisions},${j.aggregate.propagations},${j.aggregate.conflicts},${j.aggregate.maxDepth},${j.solution.models.length},${j.aggregateRounds}',
];
void main() {
  final graphs = loadGraphs(), jobs = loadJobs();
  executeJobs(jobs, graphs);
  Directory('output').createSync(recursive: true);
  saveParagraphs('results.txt', resultParagraphs(jobs));
  saveParagraphs('models.txt', modelParagraphs(jobs));
  saveParagraphs('boards.txt', boardsParagraphs(jobs));
  saveLines('stats.csv', statsLines(jobs));
}
