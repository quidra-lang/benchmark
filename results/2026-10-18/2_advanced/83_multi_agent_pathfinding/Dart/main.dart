import 'dart:io';
import 'dart:math';
part 'grid_map.dart';
part 'low_level.dart';
part 'cbs.dart';
part 'prioritized.dart';
part 'report.dart';

class RunDefinition {
  final String solver, costFunction;
  String get name => '$solver-$costFunction';
  RunDefinition(this.solver, this.costFunction);
}

class Delay {
  final int agent, start, length;
  Delay(this.agent, this.start, this.length);
}

class Parameters {
  int horizon = 0,
      highBudget = 0,
      lowBudget = 0,
      window = 0,
      step = 0,
      frames = 0;
  String animate = '';
  final List<List<int>> orders = [];
  final List<RunDefinition> definitions = [];
  final List<Delay> delays = [];
}

Parameters readParameters(int n) {
  final p = Parameters();
  p.orders.add(List.generate(n, (i) => i));
  for (final line in lines('input/params.txt')) {
    final a = line.split(' ');
    switch (a[0]) {
      case 'HORIZON':
        p.horizon = int.parse(a[1]);
        break;
      case 'HL_BUDGET':
        p.highBudget = int.parse(a[1]);
        break;
      case 'LL_BUDGET':
        p.lowBudget = int.parse(a[1]);
        break;
      case 'WINDOW':
        p.window = int.parse(a[1]);
        p.step = int.parse(a[2]);
        break;
      case 'ORDER':
        p.orders.add(a.skip(1).map(int.parse).toList());
        break;
      case 'RUN':
        p.definitions.add(RunDefinition(a[1], a[2]));
        break;
      case 'ANIMATE':
        p.animate = a[1];
        p.frames = int.parse(a[2]);
        break;
      case 'DELAY':
        p.delays.add(Delay(int.parse(a[1]), int.parse(a[2]), int.parse(a[3])));
        break;
    }
  }
  return p;
}

class Run {
  final RunDefinition definition;
  final Counters counter;
  String reason = '', end = '';
  List<List<int>>? paths;
  int high = 0, generated = 0, pruned = 0, open = 0;
  final List<int> classes = [0, 0, 0];
  final List<String> specific = [], trace = [];
  Node? answer;
  PlanMetrics? metrics;
  Execution? execution;
  Run(this.definition, int limit) : counter = Counters(limit);
}

const classNames = ['cardinal', 'semi_cardinal', 'non_cardinal'];
List<Set<int>> mdd(Grid g, int agent, int length, Prohibitions b) {
  final forward = List.generate(length + 1, (_) => <int>{});
  forward[0].add(g.agents[agent].start);
  for (var t = 1; t <= length; t++) {
    for (final c in forward[t - 1]) {
      for (final v in g.destinations(c)) {
        if (g.distances[agent][v] >= 0 &&
            t + g.distances[agent][v] <= length &&
            b.allowed(c, v, t))
          forward[t].add(v);
      }
    }
  }
  final valid = List.generate(length + 1, (_) => <int>{});
  valid[length].add(g.agents[agent].goal);
  for (var t = length - 1; t >= 0; t--) {
    for (final c in forward[t]) {
      for (final v in g.destinations(c)) {
        if (valid[t + 1].contains(v) && b.allowed(c, v, t + 1)) {
          valid[t].add(c);
          break;
        }
      }
    }
  }
  return valid;
}

int classify(
  Grid g,
  Conflict c,
  List<List<int>> paths,
  List<List<Constraint>> cs,
  Map<int, List<Set<int>>> cache,
) {
  var fixed = 0;
  for (final agent in [c.a, c.b]) {
    final length = paths[agent].length - 1;
    if (c.time > length) {
      fixed++;
      continue;
    }
    final layers = cache.putIfAbsent(
      agent,
      () => mdd(g, agent, length, constraintProhibitions(cs[agent])),
    );
    if (layers[c.time].length == 1 &&
        (!c.edge || layers[c.time - 1].length == 1))
      fixed++;
  }
  return 2 - fixed;
}

List<String> overview(Grid g, List<List<int>> independent) {
  var free = 0, components = 0;
  final degrees = [0, 0, 0, 0], seen = <int>{};
  for (var c = 0; c < g.width * g.height; c++) {
    if (!g.free(c)) continue;
    free++;
    degrees[min(g.destinations(c).length - 1, 3)]++;
    if (seen.contains(c)) continue;
    components++;
    final q = [c];
    seen.add(c);
    for (var h = 0; h < q.length; h++) {
      for (final v in g.destinations(q[h]).skip(1)) {
        if (seen.add(v)) q.add(v);
      }
    }
  }
  final out = [
    'instance width ${g.width} height ${g.height} free $free agents ${g.agents.length}',
    'map isolated ${degrees[0]} dead_ends ${degrees[1]} corridors ${degrees[2]} junctions ${degrees[3]} components $components',
  ];
  var lowerSOC = 0, lowerMax = 0;
  for (var i = 0; i < g.agents.length; i++) {
    final a = g.agents[i],
        d = g.distances[i][a.start],
        layers = mdd(g, i, g.distances[i][a.start], Prohibitions());
    var states = 0, width = 0;
    for (final layer in layers) {
      states += layer.length;
      width = max(width, layer.length);
    }
    lowerSOC += d;
    lowerMax = max(lowerMax, d);
    out.add(
      'agent ${agentName(i)} start ${cell(g, a.start)} goal ${cell(g, a.goal)} distance $d mdd $states width $width',
    );
  }
  out.add('lower_bound soc $lowerSOC makespan $lowerMax');
  final cs = conflicts(independent),
      counts = [0, 0, 0],
      restrictions = List.generate(g.agents.length, (_) => <Constraint>[]),
      cache = <int, List<Set<int>>>{},
      adj = List.generate(g.agents.length, (_) => <int>[]);
  var vertex = 0, edge = 0;
  for (final c in cs) {
    counts[classify(g, c, independent, restrictions, cache)]++;
    if (c.edge) {
      edge++;
    } else {
      vertex++;
    }
    adj[c.a].add(c.b);
    adj[c.b].add(c.a);
  }
  out.add(
    'independent conflicts ${cs.length} vertex $vertex edge $edge cardinal ${counts[0]} semi_cardinal ${counts[1]} non_cardinal ${counts[2]}',
  );
  final groups = <String>[], visited = <int>{};
  for (var i = 0; i < g.agents.length; i++) {
    if (visited.contains(i) || adj[i].isEmpty) continue;
    final q = [i];
    visited.add(i);
    for (var h = 0; h < q.length; h++) {
      for (final j in adj[q[h]]) {
        if (visited.add(j)) q.add(j);
      }
    }
    q.sort();
    groups.add(q.map(agentName).join());
  }
  out.add('groups ${groups.isEmpty ? '-' : groups.join(' ')}');
  return out;
}

void solvePP(Grid g, Parameters p, Run r) {
  for (var k = 0; k < p.orders.length; k++) {
    r.high++;
    final order = p.orders[k], before = r.counter.expansions;
    final (paths, planned, failed) = prioritized(g, p, order, k + 1, r);
    if (r.counter.aborted) {
      r.reason = 'll_budget';
      break;
    }
    final line =
        'order ${k + 1} ${order.map(agentName).join()} planned $planned expansions ${r.counter.expansions - before}';
    if (paths != null) {
      r.paths = paths;
      r.specific.add('$line ok');
      r.end = 'end OK order ${k + 1}';
      return;
    }
    r.specific.add('$line failed ${agentName(failed)}');
  }
  if (r.reason.isEmpty) r.reason = 'orders';
}

Node nodeFor(
  List<List<int>> paths,
  List<List<Constraint>> cs,
  int number,
  int parent,
  int depth,
  String costFunction,
) {
  final (soc, makespan) = planCosts(paths);
  return Node(
    number,
    parent,
    depth,
    costFunction == 'SOC' ? soc : makespan,
    paths,
    cs,
    conflicts(paths),
  );
}

void solveCBS(Grid g, Parameters p, Run r) {
  final n = g.agents.length,
      paths = List.generate(g.agents.length, (_) => <int>[]),
      constraints = List.generate(g.agents.length, (_) => <Constraint>[]),
      open = MinHeap<Node>(nodeCompare);
  try {
    for (var i = 0; i < n; i++) {
      final path = lowLevel(
        g,
        i,
        g.agents[i].start,
        0,
        p.horizon,
        Prohibitions(),
        false,
        r.counter,
      );
      if (r.counter.aborted) {
        r.reason = 'll_budget';
        return;
      }
      paths[i] = path!;
    }
    open.add(nodeFor(paths, constraints, 0, -1, 0, r.definition.costFunction));
    r.generated = 1;
    while (open.isNotEmpty) {
      final node = open.remove();
      if (node.conflicts.isEmpty) {
        r.paths = node.paths;
        r.answer = node;
        r.end = 'end OK node ${node.number} cost ${node.cost}';
        return;
      }
      if (r.high == p.highBudget) {
        r.reason = 'hl_budget';
        return;
      }
      r.high++;
      var split = node.conflicts.first, kind = 2;
      if (r.definition.solver == 'ICBS') {
        final cache = <int, List<Set<int>>>{};
        kind = 3;
        for (final c in node.conflicts) {
          final current = classify(g, c, node.paths, node.constraints, cache);
          if (current < kind) {
            split = c;
            kind = current;
          }
        }
        r.classes[kind]++;
      }
      final children = ['-', '-'];
      for (var k = 0; k < 2; k++) {
        final agent = k == 0 ? split.a : split.b,
            cs = List<List<Constraint>>.of(node.constraints);
        cs[agent] = [...cs[agent], split.constraint(agent)];
        final path = lowLevel(
          g,
          agent,
          g.agents[agent].start,
          0,
          p.horizon,
          constraintProhibitions(cs[agent]),
          false,
          r.counter,
        );
        if (r.counter.aborted) {
          r.reason = 'll_budget';
          return;
        }
        if (path == null) {
          r.pruned++;
          continue;
        }
        final newPaths = List<List<int>>.of(node.paths), number = r.generated++;
        newPaths[agent] = path;
        open.add(
          nodeFor(
            newPaths,
            cs,
            number,
            node.number,
            node.depth + 1,
            r.definition.costFunction,
          ),
        );
        children[k] = '$number';
      }
      final parent = node.parent < 0 ? '-' : '${node.parent}',
          splitText =
              '${conflictText(g, split)}${r.definition.solver == 'ICBS' ? ' class ${classNames[kind]}' : ''}';
      r.trace.add(
        'expand ${r.high} node ${node.number} parent $parent depth ${node.depth} cost ${node.cost} conflicts ${node.conflicts.length} split $splitText children ${children[0]} ${children[1]}',
      );
    }
    r.reason = 'exhausted';
  } finally {
    r.open = open.values.length;
    r.specific.add(
      'search expanded ${r.high} generated ${r.generated} pruned ${r.pruned} open ${r.open}',
    );
    if (r.definition.solver == 'ICBS')
      r.specific.add(
        'classes cardinal ${r.classes[0]} semi_cardinal ${r.classes[1]} non_cardinal ${r.classes[2]}',
      );
    final answer = r.answer;
    if (answer != null) {
      r.specific.add('solution node ${answer.number} depth ${answer.depth}');
      final all = answer.constraints.expand((cs) => cs).toList();
      List<int> key(Constraint c) => [
        c.agent,
        c.time,
        c.edge ? 1 : 0,
        c.u % g.width,
        c.u ~/ g.width,
        c.v % g.width,
        c.v ~/ g.width,
      ];
      all.sort((a, b) => compareInts(key(a), key(b)));
      for (final c in all) {
        r.specific.add(
          c.edge
              ? 'constraint ${agentName(c.agent)} edge ${cell(g, c.u)} ${cell(g, c.v)} t ${c.time}'
              : 'constraint ${agentName(c.agent)} vertex ${cell(g, c.v)} t ${c.time}',
        );
      }
    }
  }
}

void solveWHCA(Grid g, Parameters p, Run r) {
  final executed = [
        for (final a in g.agents) [a.start],
      ],
      current = [for (final a in g.agents) a.start];
  try {
    for (var time = 0; ; time += p.step) {
      var done = true;
      for (var i = 0; i < g.agents.length; i++) {
        if (current[i] != g.agents[i].goal) done = false;
      }
      if (done) {
        for (var i = 0; i < g.agents.length; i++) {
          final path = executed[i];
          while (path.length > 1 && path[path.length - 2] == g.agents[i].goal) {
            path.removeLast();
          }
        }
        r.paths = executed;
        r.end = 'end OK rounds ${r.high}';
        return;
      }
      if (time >= p.horizon) {
        r.reason = 'timeout';
        return;
      }
      r.high++;
      final order = [
            for (final atGoal in [false, true])
              for (var i = 0; i < g.agents.length; i++)
                if ((current[i] == g.agents[i].goal) == atGoal) i,
          ],
          b = Prohibitions(),
          window = List.generate(g.agents.length, (_) => <int>[]);
      for (final agent in order) {
        final before = r.counter.expansions,
            path = lowLevel(
              g,
              agent,
              current[agent],
              time,
              time + p.window,
              b,
              true,
              r.counter,
            );
        if (r.counter.aborted) {
          r.reason = 'll_budget';
          return;
        }
        final base = 'round ${r.high} time $time agent ${agentName(agent)}';
        if (path == null) {
          r.trace.add(
            '$base blocked expansions ${r.counter.expansions - before}',
          );
          r.reason = 'blocked';
          return;
        }
        while (path.length < p.window + 1) {
          path.add(path.last);
        }
        r.trace.add(
          '$base moves ${actions(g, path)} expansions ${r.counter.expansions - before}',
        );
        window[agent] = path;
        b.reserve(path, time, false);
      }
      for (var i = 0; i < g.agents.length; i++) {
        executed[i].addAll(window[i].sublist(1, p.step + 1));
        current[i] = window[i][p.step];
      }
    }
  } finally {
    r.specific.add('window ${p.window} step ${p.step} rounds ${r.high}');
  }
}

class AgentMetrics {
  final int cost, extra;
  final String moves;
  int waits = 0, turns = 0, arrival = -1, leave = 0;
  AgentMetrics(this.cost, this.extra, this.moves);
}

class PlanMetrics {
  final int soc, makespan;
  int sumExtra = 0, maxExtra = 0, waits = 0, turns = 0;
  final List<AgentMetrics> agents = [];
  final List<int> traffic, cellWaits, arrivals, hotspots = [];
  PlanMetrics(this.soc, this.makespan, int size)
    : traffic = List.filled(size, 0),
      cellWaits = List.filled(size, 0),
      arrivals = List.filled(makespan + 1, 0);
}

PlanMetrics metrics(Grid g, List<List<int>> paths) {
  final (soc, makespan) = planCosts(paths);
  final m = PlanMetrics(soc, makespan, g.width * g.height);
  for (var i = 0; i < paths.length; i++) {
    final p = paths[i],
        a = AgentMetrics(
          paths[i].length - 1,
          paths[i].length - 1 - g.distances[i][g.agents[i].start],
          actions(g, paths[i]),
        ),
        seen = <int>{};
    var last = '';
    for (var t = 0; t < p.length; t++) {
      final c = p[t];
      seen.add(c);
      if (c == g.agents[i].goal && a.arrival < 0) a.arrival = t;
      if (t == 0) continue;
      if (c == p[t - 1]) {
        a.waits++;
        m.cellWaits[c]++;
      } else {
        final direction = action(g, p[t - 1], c);
        if (last.isNotEmpty && last != direction) a.turns++;
        last = direction;
      }
      if (p[t - 1] == g.agents[i].goal && c != g.agents[i].goal) a.leave++;
    }
    for (final c in seen) {
      m.traffic[c]++;
    }
    for (var t = a.cost; t <= makespan; t++) {
      m.arrivals[t]++;
    }
    m.sumExtra += a.extra;
    m.maxExtra = max(m.maxExtra, a.extra);
    m.waits += a.waits;
    m.turns += a.turns;
    m.agents.add(a);
  }
  for (var c = 0; c < m.traffic.length; c++) {
    if (m.traffic[c] > 0) m.hotspots.add(c);
  }
  m.hotspots.sort((a, b) {
    final c = m.traffic[b].compareTo(m.traffic[a]);
    return c != 0 ? c : a.compareTo(b);
  });
  if (m.hotspots.length > 5) m.hotspots.removeRange(5, m.hotspots.length);
  return m;
}

List<String> validation(
  Grid g,
  String name,
  List<List<int>> paths,
  bool independent,
) {
  var start = 0, goal = 0, moves = 0, follows = 0, vertex = 0, edge = 0;
  for (var i = 0; i < paths.length; i++) {
    final p = paths[i];
    if (p.first != g.agents[i].start) start++;
    if (p.last != g.agents[i].goal) goal++;
    for (var t = 1; t < p.length; t++) {
      if (!g.destinations(p[t - 1]).contains(p[t])) moves++;
    }
  }
  final cs = conflicts(paths);
  for (final c in cs) {
    if (c.edge) {
      edge++;
    } else {
      vertex++;
    }
  }
  final last = planCosts(paths).$2;
  for (var t = 1; t <= last; t++) {
    for (var a = 0; a < paths.length; a++) {
      for (var b = 0; b < paths.length; b++) {
        if (a != b &&
            position(paths[a], t) != position(paths[a], t - 1) &&
            position(paths[a], t) == position(paths[b], t - 1) &&
            position(paths[b], t) != position(paths[a], t - 1))
          follows++;
      }
    }
  }
  final verdict = start + goal + moves + vertex + edge == 0
          ? 'VALID'
          : 'INVALID',
      out = [
        'plan $name verdict $verdict start $start goal $goal moves $moves vertex $vertex edge $edge follows $follows',
      ],
      cache = <int, List<Set<int>>>{},
      constraints = List.generate(paths.length, (_) => <Constraint>[]);
  for (final c in cs) {
    out.add(
      '  ${conflictText(g, c)}${independent ? ' ${classNames[classify(g, c, paths, constraints, cache)]}' : ''}',
    );
  }
  return out;
}

class Execution {
  bool deadlock = false;
  int time = 0, soc = 0, makespan = 0, blocked = 0;
  final List<int> finish;
  Execution(int n) : finish = List.filled(n, 0);
}

Execution delayed(List<List<int>> paths, List<Delay> delays) {
  final n = paths.length,
      steps = List.generate(paths.length, (_) => <(int, int)>[]);
  for (var i = 0; i < n; i++) {
    final p = paths[i];
    steps[i].add((0, p[0]));
    for (var t = 1; t < p.length; t++) {
      if (p[t] != p[t - 1]) steps[i].add((t, p[t]));
    }
  }
  final needs = List.generate(
    n,
    (i) => List.generate(steps[i].length, (_) => <(int, int)>[]),
  );
  for (var i = 0; i < n; i++) {
    for (var k = 1; k < steps[i].length; k++) {
      final s = steps[i][k];
      for (var j = 0; j < n; j++) {
        if (i == j) continue;
        for (var l = 0; l < steps[j].length; l++) {
          final t = steps[j][l];
          if (t.$2 == s.$2 && t.$1 < s.$1) needs[i][k].add((j, l));
        }
      }
    }
  }
  final out = Execution(n), progress = List.filled(n, 0);
  for (var time = 0; ; time++) {
    var done = true;
    for (var i = 0; i < n; i++) {
      if (progress[i] < steps[i].length - 1) done = false;
    }
    if (done) {
      for (final finish in out.finish) {
        out.soc += finish;
        out.makespan = max(out.makespan, finish);
      }
      return out;
    }
    final advance = <int>[];
    var stopped = false;
    for (var i = 0; i < n; i++) {
      if (progress[i] == steps[i].length - 1) continue;
      final stop = delays.any(
        (d) => d.agent == i && d.start <= time && time < d.start + d.length,
      );
      if (stop) {
        stopped = true;
        continue;
      }
      final held = needs[i][progress[i] + 1].any((p) => progress[p.$1] <= p.$2);
      if (held) {
        out.blocked++;
      } else {
        advance.add(i);
      }
    }
    if (advance.isEmpty && !stopped) {
      out.deadlock = true;
      out.time = time;
      return out;
    }
    for (final i in advance) {
      progress[i]++;
      out.finish[i] = time + 1;
    }
  }
}

List<String> countPicture(Grid g, List<int> counts) {
  final out = <String>[];
  for (var y = 0; y < g.height; y++) {
    final row = g.rows[y].split('');
    for (var x = 0; x < g.width; x++) {
      final c = y * g.width + x;
      if (!g.free(c)) continue;
      final v = counts[c];
      row[x] = v == 0
          ? '.'
          : v <= 9
          ? '$v'
          : '+';
    }
    out.add(row.join());
  }
  return out;
}

List<String> frames(Grid g, Parameters p, Run r) {
  final paths = r.paths;
  if (paths == null) return ['run ${p.animate} FAIL'];
  final out = ['run ${p.animate} frames ${p.frames}'];
  for (var t = 0; t < p.frames; t++) {
    final picture = [for (final row in g.rows) row.split('')];
    for (var i = 0; i < g.agents.length; i++) {
      final a = g.agents[i];
      picture[a.goal ~/ g.width][a.goal % g.width] = agentName(i).toLowerCase();
    }
    var done = 0, moving = 0, waiting = 0;
    for (var i = 0; i < paths.length; i++) {
      final path = paths[i], c = position(paths[i], t);
      picture[c ~/ g.width][c % g.width] = agentName(i);
      if (t >= path.length - 1) {
        done++;
      } else if (t >= 1 && position(path, t) != position(path, t - 1)) {
        moving++;
      } else {
        waiting++;
      }
    }
    out.addAll([
      '',
      'frame $t done $done moving $moving waiting $waiting',
      for (final row in picture) row.join(),
    ]);
  }
  out.addAll([
    '',
    'traffic',
    ...countPicture(g, r.metrics!.traffic),
    '',
    'waits',
    ...countPicture(g, r.metrics!.cellWaits),
  ]);
  return out;
}

List<String> runBlock(Grid g, Run r) {
  final d = r.definition,
      base =
          'run ${r.definition.name} solver ${r.definition.solver} cost_function ${r.definition.costFunction} result';
  if (r.paths == null) return ['$base FAIL reason ${r.reason}', ...r.specific];
  final m = r.metrics!;
  var cost = m.soc, lower = 0;
  for (var i = 0; i < g.agents.length; i++) {
    lower += g.distances[i][g.agents[i].start];
  }
  if (d.costFunction == 'MAKESPAN') {
    cost = m.makespan;
    lower = 0;
    for (var i = 0; i < g.agents.length; i++) {
      lower = max(lower, g.distances[i][g.agents[i].start]);
    }
  }
  final out = [
    '$base OK cost $cost soc ${m.soc} makespan ${m.makespan} ratio ${fraction(cost, lower)}',
    ...r.specific,
  ];
  for (var i = 0; i < m.agents.length; i++) {
    final a = m.agents[i];
    out.add(
      'agent ${agentName(i)} cost ${a.cost} extra ${a.extra} waits ${a.waits} turns ${a.turns} arrive ${a.arrival} leave ${a.leave} moves ${a.moves}',
    );
  }
  out.add('arrivals ${m.arrivals.join(' ')}');
  out.add(
    'hotspots ${m.hotspots.map((c) => '${cell(g, c)}:${m.traffic[c]}').join(' ')}',
  );
  final e = r.execution!;
  out.add(
    e.deadlock
        ? 'execution deadlock time ${e.time}'
        : 'execution soc ${e.soc} makespan ${e.makespan} blocked ${e.blocked} finish ${e.finish.join(' ')}',
  );
  return out;
}

String statsLine(Run r) {
  final d = r.definition,
      out = [r.definition.name, r.definition.solver, r.definition.costFunction];
  if (r.paths == null) {
    out.addAll(['FAIL', r.reason, ...List.filled(9, '-')]);
  } else {
    final m = r.metrics!,
        e = r.execution!,
        cost = d.costFunction == 'SOC' ? m.soc : m.makespan;
    out.addAll([
      'OK',
      '-',
      ...([
        cost,
        m.soc,
        m.makespan,
        m.sumExtra,
        m.maxExtra,
        m.waits,
        m.turns,
      ].map((v) => '$v')),
      ...(e.deadlock ? ['-', '-'] : ['${e.soc}', '${e.makespan}']),
    ]);
  }
  out.addAll([
    '${r.high}',
    d.solver == 'CBS' || d.solver == 'ICBS' ? '${r.generated}' : '-',
    '${r.counter.searches}',
    '${r.counter.expansions}',
  ]);
  return out.join(',');
}

void main() {
  final g = readGrid(),
      p = readParameters(g.agents.length),
      independent = <List<int>>[],
      counter = Counters(0x7fffffffffffffff);
  for (var i = 0; i < g.agents.length; i++) {
    independent.add(
      lowLevel(
        g,
        i,
        g.agents[i].start,
        0,
        p.horizon,
        Prohibitions(),
        false,
        counter,
      )!,
    );
  }
  final solutions = overview(g, independent),
      validations = validation(g, 'INDEPENDENT', independent, true),
      stats = [
        'run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,exec_soc,exec_makespan,high_level,generated,searches,expansions',
      ],
      trace = <String>[],
      runs = <Run>[],
      successful = <int>[];
  Run? animated;
  for (final definition in p.definitions) {
    final r = Run(definition, p.lowBudget);
    switch (definition.solver) {
      case 'PP':
        solvePP(g, p, r);
        break;
      case 'CBS':
      case 'ICBS':
        solveCBS(g, p, r);
        break;
      case 'WHCA':
        solveWHCA(g, p, r);
        break;
    }
    final paths = r.paths;
    if (paths != null) {
      r.metrics = metrics(g, paths);
      r.execution = delayed(paths, p.delays);
      successful.add(runs.length);
      validations.addAll(validation(g, definition.name, paths, false));
    } else {
      validations.add('plan ${definition.name} verdict NONE');
      r.end = 'end FAIL ${r.reason}';
    }
    solutions.addAll(['', ...runBlock(g, r)]);
    stats.add(statsLine(r));
    if (trace.isNotEmpty) trace.add('');
    trace.addAll(['run ${definition.name}', ...r.trace, r.end]);
    runs.add(r);
    if (definition.name == p.animate) animated = r;
  }
  solutions.addAll([
    '',
    'summary ok ${successful.length} failed ${runs.length - successful.length}',
  ]);
  if (successful.isNotEmpty) {
    var bestSOC = runs[successful.first].metrics!.soc,
        bestMax = runs[successful.first].metrics!.makespan;
    for (final i in successful) {
      bestSOC = min(bestSOC, runs[i].metrics!.soc);
      bestMax = min(bestMax, runs[i].metrics!.makespan);
    }
    final socNames = [
          for (final i in successful)
            if (runs[i].metrics!.soc == bestSOC) runs[i].definition.name,
        ],
        maxNames = [
          for (final i in successful)
            if (runs[i].metrics!.makespan == bestMax) runs[i].definition.name,
        ];
    solutions.addAll([
      'best_soc $bestSOC ${socNames.join(' ')}',
      'best_makespan $bestMax ${maxNames.join(' ')}',
    ]);
    successful.sort((i, j) {
      final a = runs[i].metrics!, b = runs[j].metrics!;
      var c = a.soc.compareTo(b.soc);
      if (c != 0) return c;
      c = a.makespan.compareTo(b.makespan);
      return c != 0 ? c : i.compareTo(j);
    });
    solutions.add(
      'ranking ${successful.map((i) => runs[i].definition.name).join(' ')}',
    );
  }
  Directory('output').createSync(recursive: true);
  writeLines('solutions.txt', solutions);
  writeLines('stats.csv', stats);
  writeLines('validation.txt', validations);
  writeLines('trace.txt', trace);
  writeLines('frames.txt', frames(g, p, animated!));
}
