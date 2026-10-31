import 'dart:io';
import 'dart:math';
part 'pddl_parser.dart';
part 'grounding.dart';
part 'heuristics.dart';
part 'search.dart';
part 'graphplan.dart';

class Settings {
  int budget = 0, weight = 0, levelLimit = 0;
  final List<SearchSettings> runs = [];
  late SearchSettings repair;
}

class Step {
  final String name;
  final List<String> arguments;
  Step(this.name, this.arguments);
  String text() => Atom(name, arguments).text();
}

class CandidatePlan {
  final String problem, label;
  final List<Step> steps = [];
  CandidatePlan(this.problem, this.label);
}

Settings readSettings() {
  final s = Settings();
  for (final line in lines('input/params.txt')) {
    if (line.isEmpty || line.startsWith('#')) continue;
    final a = line.split(' ');
    switch (a[0]) {
      case 'budget':
        s.budget = int.parse(a[1]);
        break;
      case 'weight':
        s.weight = int.parse(a[1]);
        break;
      case 'graphplan':
        s.levelLimit = int.parse(a[1]);
        break;
      case 'run':
        s.runs.add(SearchSettings(a[1], a[2]));
        break;
      case 'repair':
        s.repair = SearchSettings(a[1], a[2]);
        break;
    }
  }
  return s;
}

List<CandidatePlan> readCandidates() {
  final out = <CandidatePlan>[];
  for (final line in lines('input/candidates.txt')) {
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.startsWith('plan ')) {
      final a = line.split(' ');
      out.add(CandidatePlan(a[1], a[2]));
    } else if (line != 'end') {
      final a = line.substring(1, line.length - 1).split(' ');
      out.last.steps.add(Step(a[0], a.sublist(1)));
    }
  }
  return out;
}

String argumentCheck(
  Domain d,
  List<String> args,
  List<String> expected,
  Map<String, String> types,
  String noun,
) {
  if (args.length != expected.length)
    return 'expected ${expected.length} arguments, got ${args.length}';
  for (var i = 0; i < args.length; i++) {
    final actual = types[args[i]];
    if (actual == null) return 'unknown $noun ${args[i]}';
    if (!subtype(d, actual, expected[i]))
      return 'argument ${i + 1} (${args[i]}) is not of type ${expected[i]}';
  }
  return '';
}

void validateDomain(Domain d) {
  final kept = <Schema>[];
  for (final schema in d.actions) {
    var reason = '';
    final types = <String, String>{};
    for (final p in schema.parameters) {
      types[p.name] = p.type;
      if (!d.types.contains(p.type) && reason.isEmpty)
        reason = 'unknown type ${p.type}';
    }
    if (reason.isEmpty) {
      for (final literal in [...schema.conditions, ...schema.effects]) {
        final a = literal.atom;
        List<String> expected;
        if (a.predicate == '=') {
          expected = ['object', 'object'];
        } else {
          final index = d.predicateIndex[a.predicate];
          if (index == null) {
            reason = '${a.text()}: unknown predicate ${a.predicate}';
            break;
          }
          expected = d.predicates[index].types;
        }
        final error = argumentCheck(d, a.terms, expected, types, 'variable');
        if (error.isNotEmpty) {
          reason = '${a.text()}: $error';
          break;
        }
      }
    }
    if (reason.isNotEmpty) {
      d.diagnostics.add('error: action ${schema.name}: $reason');
    } else {
      kept.add(schema);
    }
  }
  d.actions = kept;
  final used = {
    for (final schema in d.actions)
      for (final literal in [...schema.conditions, ...schema.effects])
        literal.atom.predicate,
  };
  for (final p in d.predicates) {
    if (!used.contains(p.name))
      d.diagnostics.add(
        'warning: predicate ${p.name} is not used by any action',
      );
  }
  classify(d);
}

void validateProblem(Domain d, Problem p) {
  final types = objectTypes(p);
  List<Atom> check(List<Atom> atoms, String side) {
    final kept = <Atom>[], seen = <String>{};
    for (final a in atoms) {
      var reason = '';
      final index = d.predicateIndex[a.predicate];
      if (index == null) {
        reason = 'unknown predicate ${a.predicate}';
      } else {
        reason = argumentCheck(
          d,
          a.terms,
          d.predicates[index].types,
          types,
          'object',
        );
      }
      if (reason.isEmpty && seen.contains(a.text())) reason = 'duplicate';
      if (reason.isNotEmpty) {
        p.diagnostics.add('warning: $side ${a.text()}: $reason');
      } else {
        seen.add(a.text());
        kept.add(a);
      }
    }
    return kept;
  }

  p.initial = check(p.initial, 'init');
  p.goals = check(p.goals, 'goal');
}

String heading(String text, List<String> items) =>
    '$text ${items.isEmpty ? '-' : items.join(' ')}';
String numberList(State state) {
  final values = numbers(state);
  return values.isEmpty ? '-' : values.join(',');
}

int compareInts(List<int> a, List<int> b) {
  for (var i = 0; i < min(a.length, b.length); i++) {
    final c = a[i].compareTo(b[i]);
    if (c != 0) return c;
  }
  return a.length.compareTo(b.length);
}

List<String> domainLines(Domain d) {
  final out = ['== domain ${d.name} ==', ...d.diagnostics];
  for (var type in d.types) {
    final chain = [type];
    while (type != 'object') {
      type = d.parents[type]!;
      chain.add(type);
    }
    out.add('type ${chain.join(' < ')}');
  }
  for (final p in d.predicates) {
    out.add(
      'predicate ${p.name}/${p.types.length} ${d.fluent.contains(p.name) ? 'fluent' : 'static'}',
    );
  }
  for (final schema in d.actions) {
    final add = schema.effects.where((e) => !e.negative).length,
        del = schema.effects.where((e) => e.negative).length;
    out.add(
      'action ${schema.name}/${schema.parameters.length} cost=${schema.cost} pre=${schema.conditions.length} add=$add del=$del',
    );
  }
  return out;
}

List<String> groundingLines(GroundProblem g) {
  final d = g.domain,
      p = g.problem,
      out = [
        '== problem ${g.problem.name} ==',
        ...g.problem.diagnostics,
        'objects: ${g.problem.objects.length}',
      ];
  for (final type in d.types) {
    out.add(heading('  $type:', objectsOfType(d, p, type)));
  }
  out.add('static facts: ${g.staticFacts}');
  for (final schema in d.actions) {
    final c = g.counts[schema.name]!;
    out.add(
      'schema ${schema.name}: assignments=${c.assignments} candidates=${c.candidates} reachable=${c.reachable}',
    );
  }
  out.addAll([
    'candidates: ${g.candidateCount} reachable: ${g.actions.length}',
    'facts: ${g.facts.length} init: ${numbers(g.initial).length} goals: ${numbers(g.goal).length}',
  ]);
  for (final a in g.unreachable) {
    out.add('unreachable goal: ${a.text()}');
  }
  final counts = <String, int>{};
  for (final a in g.facts) {
    counts[a.predicate] = (counts[a.predicate] ?? 0) + 1;
  }
  out.addAll([
    heading('facts by predicate:', [
      for (final p in d.predicates)
        if (d.fluent.contains(p.name)) '${p.name}=${counts[p.name] ?? 0}',
    ]),
    'facts:',
  ]);
  for (var i = 0; i < g.facts.length; i++) {
    out.add('  $i ${g.facts[i].text()}');
  }
  out.add('actions:');
  for (var i = 0; i < g.actions.length; i++) {
    final a = g.actions[i];
    out.add(
      '  $i ${a.text()} cost=${a.cost} pre=${numberList(a.pre)} neg=${numberList(a.neg)} add=${numberList(a.add)} del=${numberList(a.del)}',
    );
  }
  return out;
}

class Validation {
  final String status;
  final List<String> messages;
  final int correct;
  Validation(this.status, this.messages, this.correct);
  String get verdict => status == 'valid'
      ? 'valid ${messages.first}'
      : '$status: ${messages.first}';
}

Validation validateSteps(Domain d, Problem p, List<Step> steps) {
  final world = {for (final a in p.initial) a.text()},
      schemas = {for (final s in d.actions) s.name: s},
      types = objectTypes(p);
  var cost = 0;
  for (var k = 0; k < steps.length; k++) {
    final step = steps[k],
        prefix = 'step ${k + 1} ${steps[k].text()}: ',
        schema = schemas[steps[k].name];
    if (schema == null)
      return Validation('invalid', ['${prefix}unknown action ${step.name}'], k);
    final expected = [for (final param in schema.parameters) param.type],
        reason = argumentCheck(d, step.arguments, expected, types, 'object');
    if (reason.isNotEmpty) return Validation('invalid', ['$prefix$reason'], k);
    final assignment = {
      for (var i = 0; i < schema.parameters.length; i++)
        schema.parameters[i].name: step.arguments[i],
    };
    for (final condition in schema.conditions) {
      final a = substitute(condition.atom, assignment),
          truth = a.predicate == '='
              ? a.terms[0] == a.terms[1]
              : world.contains(a.text());
      if (truth == condition.negative)
        return Validation('invalid', [
          '${prefix}precondition ${Literal(a, condition.negative).text()} is false',
        ], k);
    }
    for (final e in schema.effects) {
      if (e.negative) world.remove(substitute(e.atom, assignment).text());
    }
    for (final e in schema.effects) {
      if (!e.negative) world.add(substitute(e.atom, assignment).text());
    }
    cost += schema.cost;
  }
  final messages = [
    for (final a in p.goals)
      if (!world.contains(a.text())) 'unsatisfied goal ${a.text()}',
  ];
  return messages.isEmpty
      ? Validation('valid', ['length=${steps.length} cost=$cost'], steps.length)
      : Validation('goal not reached', messages, steps.length);
}

List<Step> planSteps(GroundProblem g, List<int> plan) => [
  for (final i in plan) Step(g.actions[i].schema.name, g.actions[i].arguments),
];
List<int> mapSteps(GroundProblem g, List<Step> steps) {
  final indices = {
    for (var i = 0; i < g.actions.length; i++) g.actions[i].text(): i,
  };
  return [for (final s in steps) indices[s.text()]!];
}

int planCost(GroundProblem g, List<int> plan) =>
    plan.fold<int>(0, (cost, i) => cost + g.actions[i].cost);
List<int> improve(GroundProblem g, List<int> plan) {
  var out = List<int>.of(plan), at = 0;
  while (at < out.length) {
    var state = g.initial;
    for (final i in out.take(at)) {
      state = apply(g.actions[i], state);
    }
    final kept = out.take(at).toList();
    for (final i in out.skip(at + 1)) {
      if (applicable(g.actions[i], state)) {
        state = apply(g.actions[i], state);
        kept.add(i);
      }
    }
    if (goal(g, state)) {
      out = kept;
    } else {
      at++;
    }
  }
  return out;
}

bool interfere(GroundAction a, GroundAction b) =>
    intersects(a.del, b.pre | b.add) ||
    intersects(b.del, a.pre | a.add) ||
    intersects(a.add, b.neg) ||
    intersects(b.add, a.neg);
List<List<int>> parallelize(GroundProblem g, List<int> plan) {
  final layers = List.filled(plan.length, 0);
  var count = 0;
  for (var j = 0; j < plan.length; j++) {
    final a = g.actions[plan[j]];
    layers[j] = 1;
    for (var i = 0; i < j; i++) {
      final b = g.actions[plan[i]];
      if (intersects(b.add, a.pre) ||
          intersects(b.del, a.neg) ||
          interfere(a, b))
        layers[j] = max(layers[j], layers[i] + 1);
    }
    count = max(count, layers[j]);
  }
  final out = List.generate(count, (_) => <int>[]);
  for (var i = 0; i < plan.length; i++) {
    out[layers[i] - 1].add(plan[i]);
  }
  return out;
}

String parallelValidation(GroundProblem g, List<List<int>> layers) {
  var state = g.initial;
  for (var k = 0; k < layers.length; k++) {
    final layer = layers[k];
    for (var i = 0; i < layer.length; i++) {
      final a = g.actions[layer[i]];
      if (!applicable(a, state)) return 'invalid at layer ${k + 1}';
      for (final other in layer.skip(i + 1)) {
        if (interfere(a, g.actions[other])) return 'invalid at layer ${k + 1}';
      }
    }
    var adds = BigInt.zero, deletes = BigInt.zero;
    for (final index in layer) {
      adds |= g.actions[index].add;
      deletes |= g.actions[index].del;
    }
    state = (state & ~deletes) | adds;
  }
  return goal(g, state) ? 'valid' : 'goal not reached';
}

(List<GraphElement>, State, int) transformedGraph(GroundProblem g) {
  var negative = BigInt.zero;
  for (final a in g.actions) {
    negative |= a.neg;
  }
  final values = numbers(negative),
      complement = {
        for (var i = 0; i < values.length; i++) values[i]: g.facts.length + i,
      };
  var initial = g.initial;
  for (final e in complement.entries) {
    if (!has(initial, e.key)) initial = put(initial, e.value);
  }
  final actions = <GraphElement>[];
  for (var i = 0; i < g.actions.length; i++) {
    final a = g.actions[i];
    var pre = a.pre, add = a.add, del = a.del;
    for (final p in numbers(a.neg)) {
      pre = put(pre, complement[p]!);
    }
    for (final p in numbers(a.del)) {
      final c = complement[p];
      if (c != null) add = put(add, c);
    }
    for (final p in numbers(a.add)) {
      final c = complement[p];
      if (c != null) del = put(del, c);
    }
    actions.add(GraphElement(i, pre, add, del));
  }
  return (actions, initial, complement.length);
}

String heuristicText(int value) => value == infinity ? 'inf' : '$value';
const heuristicNames = ['goalcount', 'hmax', 'hadd', 'ff', 'lmcount'];
String heuristicValues(Heuristic h) => [
  for (final name in heuristicNames) '$name=${heuristicText(h.value(name))}',
].join(' ');
List<String> actionTexts(GroundProblem g, List<int> indices) => [
  for (final i in indices) g.actions[i].text(),
];

class RunRecord {
  final SearchSettings settings;
  final String tag;
  final SearchResult result;
  RunRecord(this.settings, this.tag, this.result);
}

class ProblemResult {
  final GroundProblem ground;
  final List<RunRecord> runs = [];
  late GraphPlanResult graph;
  RunRecord? proof;
  int best = -1, solved = 0;
  String optimal = 'unknown';
  ProblemResult(this.ground);
}

class Output {
  final List<String> plans = [],
      graph = [],
      validation = [],
      comparison = [
        'problem,algorithm,heuristic,length,cost,expanded,generated',
      ];
  int validated = 0, validPlans = 0;
}

(List<String>, List<String>) planBlock(
  GroundProblem g,
  String tag,
  List<int> plan,
  Map<String, String> seen,
  Output output,
) {
  var line = 'plan: length=${plan.length} cost=${planCost(g, plan)}';
  final key = plan.join(','), earlier = seen[key];
  if (earlier != null) {
    line += ' (same as $earlier)';
  } else {
    seen[key] = tag;
  }
  final out = [line], counts = <String, int>{};
  for (var k = 0; k < plan.length; k++) {
    final a = g.actions[plan[k]];
    counts[a.schema.name] = (counts[a.schema.name] ?? 0) + 1;
    out.add('  ${k + 1} ${a.text()}');
  }
  out.add(
    heading('schemas:', [
      for (final s in g.domain.actions)
        if ((counts[s.name] ?? 0) > 0) '${s.name}=${counts[s.name]}',
    ]),
  );
  final layers = parallelize(g, plan);
  out.add('parallel: layers=${layers.length}');
  for (var k = 0; k < layers.length; k++) {
    out.add(heading('  ${k + 1}:', actionTexts(g, layers[k])));
  }
  final improved = improve(g, plan), removed = plan.length - improved.length;
  out.add(
    'improved: length=${improved.length} cost=${planCost(g, improved)} removed=$removed',
  );
  if (removed > 0) {
    for (var k = 0; k < improved.length; k++) {
      out.add('  ${k + 1} ${g.actions[improved[k]].text()}');
    }
  }
  final landmarks = heuristics(g, g.initial).landmarks;
  var reached = BigInt.zero, state = g.initial;
  for (final i in plan) {
    state = apply(g.actions[i], state);
    reached |= state & landmarks;
  }
  out.add(
    'landmarks reached: ${numbers(reached).length}/${numbers(landmarks).length}',
  );
  for (final p in numbers(landmarks & ~reached)) {
    out.add('  missed ${g.facts[p].text()}');
  }
  final original = validateSteps(g.domain, g.problem, planSteps(g, plan)),
      improvedValidation = validateSteps(
        g.domain,
        g.problem,
        planSteps(g, improved),
      );
  output.validated++;
  if (original.status == 'valid') output.validPlans++;
  return (
    out,
    [
      '$tag: ${original.verdict}',
      '  parallel: ${parallelValidation(g, layers)}',
      '  improved: ${improvedValidation.verdict}',
    ],
  );
}

List<String> profile(GroundProblem g, RunRecord proof) {
  final plan = proof.result.plan,
      out = ['-- profile (${proof.tag}) --'],
      overestimates = List.filled(heuristicNames.length, 0);
  var remaining = planCost(g, plan), state = g.initial;
  for (var k = 0; k <= plan.length; k++) {
    final h = heuristics(g, state);
    out.add('  $k: h*=$remaining ${heuristicValues(h)}');
    for (var i = 0; i < heuristicNames.length; i++) {
      if (h.value(heuristicNames[i]) > remaining) overestimates[i]++;
    }
    if (k < plan.length) {
      final a = g.actions[plan[k]];
      remaining -= a.cost;
      state = apply(a, state);
    }
  }
  out.addAll([
    'overestimates: ${[for (var i = 0; i < heuristicNames.length; i++) '${heuristicNames[i]}=${overestimates[i]}'].join(' ')}',
    '-- causal links (${proof.tag}) --',
  ]);
  final supplier = List.filled(g.facts.length, 0);
  for (var k = 0; k < plan.length; k++) {
    final a = g.actions[plan[k]],
        items = [
          for (final p in numbers(g.actions[plan[k]].pre))
            '${g.facts[p].text()}<-${supplier[p]}',
        ];
    out.add(heading('  ${k + 1} ${a.text()}:', items));
    for (final p in numbers(a.add)) {
      supplier[p] = k + 1;
    }
  }
  out.add(
    heading('  goal:', [
      for (final p in numbers(g.goal)) '${g.facts[p].text()}<-${supplier[p]}',
    ]),
  );
  return out;
}

String resultLine(SearchResult r) => r.status == 'unreachable goal'
    ? 'result: FAIL (unreachable goal)'
    : r.status == 'solved'
    ? 'result: solved expanded=${r.expanded} generated=${r.generated}'
    : 'result: FAIL (${r.status}) expanded=${r.expanded} generated=${r.generated}';
ProblemResult processProblem(GroundProblem g, Settings settings, Output out) {
  final p = ProblemResult(g), unreachable = g.unreachable.isNotEmpty;
  out.plans.add('== problem ${g.problem.name} ==');
  out.graph.add('== problem ${g.problem.name} ==');
  out.validation.add('== problem ${g.problem.name} ==');
  if (unreachable) {
    out.plans.add('initial h: unreachable goal');
  } else {
    final h = heuristics(g, g.initial);
    out.plans.addAll([
      'initial h: ${heuristicValues(h)}',
      'landmarks: ${numbers(h.landmarks).length}',
      for (final f in numbers(h.landmarks)) '  ${g.facts[f].text()}',
      'relaxed plan: length=${h.relaxed.length} cost=${heuristicText(h.ff)}',
      for (final a in h.relaxed) '  ${g.actions[a].text()}',
      heading('helpful:', actionTexts(g, h.helpful)),
    ]);
  }
  for (final run in settings.runs) {
    final result = unreachable
            ? (SearchResult()..status = 'unreachable goal')
            : search(g, g.initial, run, settings.budget, settings.weight),
        record = RunRecord(run, run.tag, result);
    p.runs.add(record);
    if (p.proof == null &&
        record.result.status == 'solved' &&
        (record.tag == 'ucs none' || record.tag == 'astar hmax'))
      p.proof = record;
  }
  if (unreachable) {
    p.graph = GraphPlanResult(0)..status = 'unreachable goal';
    out.graph.add('result: FAIL (unreachable goal)');
  } else {
    final (actions, initial, count) = transformedGraph(g);
    final r = graphPlan(actions, initial, g.goal, count, settings.levelLimit);
    p.graph = r;
    out.graph.addAll(['complementary facts: $count', ...r.logs]);
    if (r.status == 'solved') {
      out.graph.add(
        'result: solved levels=${r.layers.length} length=${r.plan.length} cost=${planCost(g, r.plan)} searched=${r.searched} memo_hits=${r.memoHits} tried=${r.tried}',
      );
      for (var k = 0; k < r.layers.length; k++) {
        out.graph.add(heading('layer ${k + 1}:', actionTexts(g, r.layers[k])));
      }
    } else {
      out.graph.add(
        'result: FAIL (${r.status}) searched=${r.searched} memo_hits=${r.memoHits} tried=${r.tried}',
      );
    }
  }
  final gp = p.graph,
      gpResult = SearchResult()
        ..status = gp.status
        ..plan = List<int>.of(gp.plan)
        ..expanded = gp.searched
        ..generated = gp.tried;
  p.runs.add(
    RunRecord(SearchSettings('graphplan', 'none'), 'graphplan', gpResult),
  );
  final seen = <String, String>{};
  for (final record in p.runs) {
    final r = record.result;
    out.plans.addAll(['-- ${record.tag} --', resultLine(r)]);
    var length = '-', cost = '-';
    if (r.status == 'solved') {
      p.solved++;
      final value = planCost(g, r.plan);
      if (p.best < 0 || value < p.best) p.best = value;
      length = '${r.plan.length}';
      cost = '$value';
      final (block, validation) = planBlock(g, record.tag, r.plan, seen, out);
      out.plans.addAll(block);
      out.validation.addAll(validation);
    }
    out.comparison.add(
      '${g.problem.name},${record.settings.algorithm},${record.settings.heuristic},$length,$cost,${r.expanded},${r.generated}',
    );
  }
  final proof = p.proof;
  if (proof != null) {
    p.optimal = '${planCost(g, proof.result.plan)}';
    out.plans.addAll(profile(g, proof));
  } else {
    for (final record in p.runs) {
      if ([
        'unreachable goal',
        'dead end',
        'exhausted',
        'unreachable',
      ].contains(record.result.status)) {
        p.optimal = 'none';
        break;
      }
    }
  }
  out.plans.add('');
  out.graph.add('');
  out.validation.add('');
  return p;
}

String bestText(int value) => value < 0 ? '-' : '$value';
(List<String>, int) candidateLines(
  Domain d,
  List<CandidatePlan> candidates,
  Map<String, ProblemResult> problems,
  Settings settings,
) {
  final out = ['== candidates =='];
  var validCount = 0;
  for (var i = 0; i < candidates.length; i++) {
    final c = candidates[i],
        p = problems[c.problem]!,
        g = p.ground,
        v = validateSteps(d, g.problem, c.steps),
        base = 'candidate ${i + 1} ${c.problem} ${c.label}: ';
    if (v.status == 'valid') {
      validCount++;
      final plan = mapSteps(g, c.steps), improved = improve(g, plan);
      out.addAll([
        '$base${v.verdict}',
        '  improved: length=${improved.length} cost=${planCost(g, improved)} removed=${c.steps.length - improved.length} best known=${bestText(p.best)}',
      ]);
      continue;
    }
    out.add('$base${v.status}');
    out.addAll(v.messages.map((m) => '  $m'));
    if (g.unreachable.isNotEmpty) {
      out.add('  repair: FAIL (unreachable goal)');
      continue;
    }
    final prefix = mapSteps(g, c.steps.take(v.correct).toList());
    var state = g.initial;
    for (final index in prefix) {
      state = apply(g.actions[index], state);
    }
    final repair = search(
      g,
      state,
      settings.repair,
      settings.budget,
      settings.weight,
    );
    if (repair.status != 'solved') {
      out.add('  repair: FAIL (${repair.status})');
      continue;
    }
    final plan = [...prefix, ...repair.plan],
        validation = validateSteps(d, g.problem, planSteps(g, plan));
    out.add(
      '  repair: kept=${prefix.length} added=${repair.plan.length} ${validation.verdict}',
    );
    for (var k = 0; k < plan.length; k++) {
      out.add('    ${k + 1} ${g.actions[plan[k]].text()}');
    }
  }
  return (out, validCount);
}

void writeLines(String name, List<String> lines) => File(
  'output/$name',
).writeAsStringSync(lines.isEmpty ? '' : '${lines.join('\n')}\n');
void main() {
  final d = readDomain();
  validateDomain(d);
  final rawProblems = readProblems(),
      settings = readSettings(),
      candidates = readCandidates(),
      grounding = domainLines(d),
      out = Output(),
      problems = <ProblemResult>[],
      byName = <String, ProblemResult>{};
  for (final p in rawProblems) {
    validateProblem(d, p);
    final g = ground(d, p);
    grounding.addAll(['', ...groundingLines(g)]);
    final result = processProblem(g, settings, out);
    problems.add(result);
    byName[p.name] = result;
  }
  out.plans.add('== summary ==');
  for (final p in problems) {
    out.plans.add(
      '${p.ground.problem.name}: solved=${p.solved}/${p.runs.length} best=${bestText(p.best)} optimal=${p.optimal}',
    );
  }
  for (var i = 0; i < problems.first.runs.length; i++) {
    final record = problems.first.runs[i];
    var solved = 0, best = 0, expanded = 0, generated = 0;
    for (final p in problems) {
      final r = p.runs[i].result;
      expanded += r.expanded;
      generated += r.generated;
      if (r.status == 'solved') {
        solved++;
        if (planCost(p.ground, r.plan) == p.best) best++;
      }
    }
    out.plans.add(
      '${record.tag}: solved=$solved best=$best expanded=$expanded generated=$generated',
    );
  }
  final (candidateOutput, validCandidates) = candidateLines(
    d,
    candidates,
    byName,
    settings,
  );
  out.validation.addAll([
    ...candidateOutput,
    '',
    '== summary ==',
    'plans: ${out.validated} valid: ${out.validPlans}',
    'candidates: ${candidates.length} valid: $validCandidates',
  ]);
  Directory('output').createSync(recursive: true);
  writeLines('grounding.txt', grounding);
  writeLines('plans.txt', out.plans);
  writeLines('graphplan.txt', out.graph);
  writeLines('validation.txt', out.validation);
  writeLines('comparison.csv', out.comparison);
}
