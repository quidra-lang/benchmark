import 'dart:io';
import 'dart:math' as math;
import 'instance.dart';
import 'minstd.dart';
import 'dispatch_rules.dart';
import 'genetic.dart';
import 'gantt.dart';

const rules = ['SPT', 'LPT', 'MWKR', 'FIFO'];
String line(List<Object> parts) => parts.join(' ');
int sum(Iterable<int> values) =>
    values.fold(0, (total, value) => total + value);
int makespan(List<int> starts, List<int> durations) => [
  for (var i = 0; i < starts.length; i++) starts[i] + durations[i],
].reduce(math.max);
String percentage(int a, int b) {
  final t = (2000 * a + b) ~/ (2 * b);
  return '${t ~/ 10}.${t % 10}%';
}

String jobLetter(int j) => String.fromCharCode(65 + j - 1);
void writeLines(String name, List<String> lines) =>
    File('output/$name').writeAsStringSync('${lines.join('\n')}\n');
List<List<int>> copyOrder(List<List<int>> order) =>
    order.map((row) => List<int>.of(row)).toList();

class Parameters {
  final Map<String, List<String>> fields;
  Parameters()
    : fields = {
        for (final text in File('input/ga_params.txt').readAsLinesSync())
          text.split(' ').first: text.split(' ').skip(1).toList(),
      };
  int number(String key) => int.parse(fields[key]!.first);
  (int, int) fraction(String key) {
    final parts = fields[key]!.first.split('/').map(int.parse).toList();
    return (parts[0], parts[1]);
  }

  int get population => number('population');
  int get generations => number('generations');
  int get tournamentSize => number('tournament');
  int get elitism => number('elitism');
  int get tabuIterations => number('tabu_iterations');
  int get tabuTenure => number('tabu_tenure');
}

int jacksonBound(Instance instance, Machine machine) {
  final tasks = machine.operations
          .map((id) => instance.operations[id])
          .toList(),
      remaining = machine.operations
          .map((id) => instance.operations[id].duration)
          .toList();
  var time = 0, bound = 0;
  while (remaining.any((value) => value > 0)) {
    final pending = [
      for (var i = 0; i < tasks.length; i++)
        if (remaining[i] > 0) i,
    ];
    if (pending.every((i) => tasks[i].head > time))
      time = pending.map((i) => tasks[i].head).reduce(math.min);
    var best = -1;
    for (final i in pending) {
      if (tasks[i].head <= time &&
          (best < 0 || tasks[i].tail > tasks[best].tail))
        best = i;
    }
    var step = remaining[best];
    for (final task in tasks) {
      if (task.head > time) step = math.min(step, task.head - time);
    }
    time += step;
    remaining[best] -= step;
    if (remaining[best] == 0) bound = math.max(bound, time + tasks[best].tail);
  }
  return bound;
}

List<int> orderStarts(
  Instance instance,
  List<List<int>> order,
  List<int> durations,
) {
  final starts = List.filled(instance.operations.length, -1),
      ends = List.filled(instance.operations.length, 0),
      positions = List.filled(instance.machineCount, 0);
  var placed = 0;
  while (placed < starts.length) {
    for (var m = 0; m < order.length; m++) {
      final row = order[m];
      while (positions[m] < row.length) {
        final pos = positions[m],
            id = row[positions[m]],
            previous = instance.operations[row[positions[m]]].previous;
        if (previous >= 0 && starts[previous] < 0) break;
        starts[id] = math.max(
          previous < 0 ? 0 : ends[previous],
          pos == 0 ? 0 : ends[row[pos - 1]],
        );
        ends[id] = starts[id] + durations[id];
        positions[m]++;
        placed++;
      }
    }
  }
  return starts;
}

class Schedule {
  final Instance instance;
  final List<int> starts;
  late final List<int> ends, machinePrevious, machineNext;
  late final List<List<int>> order;
  late final int makespanValue;
  Schedule(this.instance, this.starts) {
    ends = [
      for (var i = 0; i < starts.length; i++) starts[i] + instance.durations[i],
    ];
    makespanValue = ends.reduce(math.max);
    machinePrevious = List.filled(starts.length, -1);
    machineNext = List.filled(starts.length, -1);
    order = List.generate(instance.machineCount, (_) => <int>[]);
    for (final id in byStart()) {
      order[instance.operations[id].machine - 1].add(id);
    }
    for (final row in order) {
      for (var i = 1; i < row.length; i++) {
        machinePrevious[row[i]] = row[i - 1];
        machineNext[row[i - 1]] = row[i];
      }
    }
  }
  List<int> byStart() => List.generate(starts.length, (i) => i)
    ..sort((a, b) {
      final order = starts[a].compareTo(starts[b]);
      return order != 0 ? order : a.compareTo(b);
    });
  List<int> chromosome() =>
      byStart().map((id) => instance.operations[id].job).toList();
  List<int> path() {
    var current = ends.indexOf(makespanValue);
    final path = [current];
    while (starts[current] != 0) {
      final previous = machinePrevious[current];
      current = previous >= 0 && ends[previous] == starts[current]
          ? previous
          : instance.operations[current].previous;
      path.add(current);
    }
    return path.reversed.toList();
  }

  List<List<int>> blocks(List<int> path) {
    final blocks = <List<int>>[];
    for (final id in path) {
      if (blocks.isNotEmpty &&
          instance.operations[blocks.last.last].machine ==
              instance.operations[id].machine) {
        blocks.last.add(id);
      } else {
        blocks.add([id]);
      }
    }
    return blocks;
  }

  List<(int, int)> moves() => [
    for (final block in blocks(path()))
      for (var i = 1; i < block.length; i++) (block[i - 1], block[i]),
  ];
  int pathCount() {
    final ways = List.filled(starts.length, 0);
    for (final id in byStart()) {
      if (starts[id] == 0) {
        ways[id] = 1;
      } else {
        for (final previous in [
          instance.operations[id].previous,
          machinePrevious[id],
        ]) {
          if (previous >= 0 && ends[previous] == starts[id])
            ways[id] += ways[previous];
        }
      }
    }
    return sum([
      for (var id = 0; id < ends.length; id++)
        if (ends[id] == makespanValue) ways[id],
    ]);
  }

  (int, int)? leftShift(int id) {
    final o = instance.operations[id],
        row = order[instance.operations[id].machine - 1];
    final position = row.indexOf(id),
        ready = o.previous < 0 ? 0 : ends[o.previous];
    for (var insertion = 0; insertion < position; insertion++) {
      final start = math.max(
        insertion == 0 ? 0 : ends[row[insertion - 1]],
        ready,
      );
      if (start + o.duration <= starts[row[insertion]])
        return (start, insertion);
    }
    return null;
  }

  int shiftableCount() => [
    for (var id = 0; id < starts.length; id++)
      if (leftShift(id) != null) id,
  ].length;
  (List<int>, List<int>) slacks() {
    final latest = List.filled(starts.length, 0),
        slack = List.filled(starts.length, 0),
        free = List.filled(starts.length, 0);
    for (final id in byStart().reversed) {
      final next = [
        instance.operations[id].next,
        machineNext[id],
      ].where((i) => i >= 0).toList();
      final limit = next.isEmpty
              ? makespanValue
              : next.map((i) => latest[i]).reduce(math.min),
          startLimit = next.isEmpty
              ? makespanValue
              : next.map((i) => starts[i]).reduce(math.min);
      latest[id] = limit - instance.durations[id];
      slack[id] = latest[id] - starts[id];
      free[id] = startLimit - ends[id];
    }
    return (slack, free);
  }

  List<int> pathCounts() {
    final counts = List.filled(instance.machineCount, 0);
    for (final id in path()) {
      counts[instance.operations[id].machine - 1]++;
    }
    return counts;
  }

  (int, int) bottleneck() {
    final counts = pathCounts(), best = pathCounts().reduce(math.max);
    return (counts.indexOf(best) + 1, best);
  }

  int jobCompletion(Job job) => ends[job.operations.last];
  int flow() => sum(instance.jobs.map(jobCompletion));
  int idle() => sum(instance.machines.map((m) => makespanValue - m.load));
  String letters(int m) =>
      order[m - 1].map((id) => jobLetter(instance.operations[id].job)).join();
}

Schedule scheduleOfOrder(Instance instance, List<List<int>> order) =>
    Schedule(instance, orderStarts(instance, order, instance.durations));
List<List<int>> applyMove(
  Instance instance,
  List<List<int>> order,
  (int, int) move,
) {
  final result = copyOrder(order), m = instance.operations[move.$1].machine - 1;
  final row = result[m], pos = result[m].indexOf(move.$1);
  row[pos] = move.$2;
  row[pos + 1] = move.$1;
  return result;
}

List<int> machineDistances(Schedule a, Schedule b) {
  final distances = <int>[];
  for (var m = 0; m < a.order.length; m++) {
    final row = a.order[m],
        ranks = {for (var i = 0; i < b.order[m].length; i++) b.order[m][i]: i};
    var count = 0;
    for (var i = 0; i < row.length; i++) {
      for (var j = i + 1; j < row.length; j++) {
        if (ranks[row[i]]! > ranks[row[j]]!) count++;
      }
    }
    distances.add(count);
  }
  return distances;
}

class TabuRecord {
  final int iteration, moves, tabu, value, best;
  final (int, int) move;
  final bool aspiration;
  TabuRecord(
    this.iteration,
    this.moves,
    this.tabu,
    this.move,
    this.aspiration,
    this.value,
    this.best,
  );
}

class Search {
  List<List<int>> bestOrder;
  final int startValue;
  int bestValue, found = 0;
  final records = <TabuRecord>[];
  String reason = 'limit';
  Search(this.bestOrder, this.startValue) : bestValue = startValue;
}

Search tabuSearch(Instance instance, List<List<int>> order, Parameters p) {
  final search = Search(order, scheduleOfOrder(instance, order).makespanValue),
      expiry = <(int, int), int>{};
  var current = order;
  for (var it = 1; it <= p.tabuIterations; it++) {
    final moves = scheduleOfOrder(instance, current).moves();
    if (moves.isEmpty) {
      search.reason = 'no_moves';
      break;
    }
    var best = -1, bestValue = 0, tabuCount = 0, chosenTabu = false;
    for (var i = 0; i < moves.length; i++) {
      final move = moves[i],
          value = scheduleOfOrder(
            instance,
            applyMove(instance, current, moves[i]),
          ).makespanValue;
      final tabu = expiry.containsKey(move) && expiry[move]! >= it;
      if (tabu) tabuCount++;
      if ((!tabu || value < search.bestValue) &&
          (best < 0 || value < bestValue)) {
        best = i;
        bestValue = value;
        chosenTabu = tabu;
      }
    }
    if (best < 0) {
      search.reason = 'all_tabu';
      break;
    }
    final move = moves[best];
    current = applyMove(instance, current, move);
    expiry[(move.$2, move.$1)] = it + p.tabuTenure;
    if (bestValue < search.bestValue) {
      search.bestOrder = current;
      search.bestValue = bestValue;
      search.found = it;
    }
    search.records.add(
      TabuRecord(
        it,
        moves.length,
        tabuCount,
        move,
        chosenTabu,
        bestValue,
        search.bestValue,
      ),
    );
  }
  return search;
}

typedef Shift = (int, int, int);
(List<List<int>>, List<Shift>) activate(
  Instance instance,
  List<List<int>> order,
) {
  final current = copyOrder(order), shifts = <Shift>[];
  while (true) {
    final s = scheduleOfOrder(instance, current);
    var found = false;
    for (final id in s.byStart()) {
      final shift = s.leftShift(id);
      if (shift == null) continue;
      final row = current[instance.operations[id].machine - 1];
      row.remove(id);
      row.insert(shift.$2, id);
      shifts.add((id, s.starts[id], shift.$1));
      found = true;
      break;
    }
    if (!found) return (current, shifts);
  }
}

class Baseline {
  final String rule;
  final Schedule schedule;
  final int decisions, ties;
  final Search search;
  Baseline(this.rule, this.schedule, this.decisions, this.ties, this.search);
}

List<int> ranking(List<int> values) =>
    List.generate(values.length, (i) => i)..sort((a, b) {
      final order = values[a].compareTo(values[b]);
      return order == 0 ? a.compareTo(b) : order;
    });

class GeneticAlgorithm {
  final Instance instance;
  final Parameters params;
  final Minstd rng;
  List<List<int>> population;
  var values = <int>[];
  final records = <(int, int, int)>[];
  final progress = <String>[];
  int crossovers = 0, swaps = 0, inserts = 0;
  GeneticAlgorithm(this.instance, this.params, this.population)
    : rng = Minstd(params.number('seed'));
  void mutate(List<int> child) {
    if (rng.chance(params.fraction('swap_mutation'))) {
      swaps++;
      swapMutation(rng, child);
    }
    if (rng.chance(params.fraction('insert_mutation'))) {
      inserts++;
      insertMutation(rng, child);
    }
  }

  void run() {
    while (population.length < params.population) {
      final sequence = [
        for (final j in instance.jobs)
          for (final _ in j.operations) j.number,
      ];
      rng.shuffle(sequence);
      population.add(sequence);
    }
    var previous = -1;
    final checkpoints = params.fields['checkpoints']!.map(int.parse).toSet();
    for (var generation = 0; generation <= params.generations; generation++) {
      values = population
          .map((c) => makespan(decode(instance, c), instance.durations))
          .toList();
      final order = ranking(values), best = ranking(values).first;
      if (generation == 0 || values[best] < previous)
        records.add((generation, values[best], best + 1));
      previous = values[best];
      if (checkpoints.contains(generation)) {
        final total = sum(values),
            divisor = sum(values).gcd(params.population),
            distinct = population.map((c) => c.join(' ')).toSet().length;
        progress.add(
          '$generation,${values[best]},${total ~/ divisor}/${params.population ~/ divisor},${values.reduce(math.max)},$distinct',
        );
      }
      if (generation == params.generations) break;
      final next = [
        for (final i in order.take(params.elitism)) List<int>.of(population[i]),
      ];
      while (next.length < params.population) {
        final first =
                population[tournament(rng, values, params.tournamentSize)],
            second = population[tournament(rng, values, params.tournamentSize)];
        List<int> a, b;
        if (rng.chance(params.fraction('crossover'))) {
          crossovers++;
          (a, b) = crossover(rng, first, second, instance.jobs);
        } else {
          a = List<int>.of(first);
          b = List<int>.of(second);
        }
        mutate(a);
        mutate(b);
        next.addAll([a, b]);
      }
      population = next;
    }
  }
}

class Solver {
  final Instance instance;
  final Parameters params;
  late final List<int> jacksons;
  late final Job jobBound;
  late final Machine machineBound;
  late final int jacksonIndex, lower;
  final baselines = <Baseline>[];
  late final GeneticAlgorithm genetic;
  late final Schedule gaSchedule, finalSchedule;
  late final int activeValue, activeDecisions, activatedValue;
  late final List<Shift> shifts;
  late final Search search;
  Solver(this.instance, this.params) {
    jacksons = instance.machines.map((m) => jacksonBound(instance, m)).toList();
    jobBound = instance.jobs.reduce((a, b) => b.work > a.work ? b : a);
    machineBound = instance.machines.reduce(
      (a, b) => b.bound > a.bound ? b : a,
    );
    jacksonIndex = jacksons.indexOf(jacksons.reduce(math.max));
    lower = math.max(
      jobBound.work,
      math.max(machineBound.bound, jacksons[jacksonIndex]),
    );
    for (final rule in rules) {
      final (starts, decisions, ties) = dispatch(instance, rule);
      final s = Schedule(instance, starts);
      baselines.add(
        Baseline(
          rule,
          s,
          decisions,
          ties,
          tabuSearch(instance, s.order, params),
        ),
      );
    }
    genetic = GeneticAlgorithm(
      instance,
      params,
      baselines.map((b) => b.schedule.chromosome()).toList(),
    )..run();
    final chromosome = genetic.population[ranking(genetic.values).first];
    gaSchedule = Schedule(instance, decode(instance, chromosome));
    final positions = List.filled(instance.operations.length, 0),
        operations = geneOperations(instance, chromosome);
    for (var i = 0; i < operations.length; i++) {
      positions[operations[i]] = i + 1;
    }
    final (starts, decisions, _) = dispatch(instance, 'GENES', positions);
    activeValue = makespan(starts, instance.durations);
    activeDecisions = decisions;
    final (order, recordedShifts) = activate(instance, gaSchedule.order);
    shifts = recordedShifts;
    activatedValue = scheduleOfOrder(instance, order).makespanValue;
    search = tabuSearch(instance, order, params);
    finalSchedule = scheduleOfOrder(instance, search.bestOrder);
  }
  List<String> baselineLines() {
    final lines = [
      line([
        'INSTANCE',
        'jobs',
        instance.jobs.length,
        'machines',
        instance.machineCount,
        'operations',
        instance.operations.length,
        'work',
        sum(instance.durations),
        'errors',
        instance.errors.length,
      ]),
    ];
    lines.addAll(instance.errors.map((e) => 'ERROR $e'));
    for (final j in instance.jobs) {
      lines.add(
        line([
          'JOB',
          'J${j.number}',
          'operations',
          j.operations.length,
          'work',
          j.work,
          'route',
          j.operations
              .map((id) => 'M${instance.operations[id].machine}')
              .join(' '),
        ]),
      );
    }
    for (var i = 0; i < instance.machines.length; i++) {
      final m = instance.machines[i];
      lines.add(
        line([
          'MACHINE',
          'M${m.number}',
          'operations',
          m.operations.length,
          'load',
          m.load,
          'head',
          m.head,
          'tail',
          m.tail,
          'bound',
          m.bound,
          'jackson',
          jacksons[i],
        ]),
      );
    }
    lines.addAll([
      'BOUND job ${jobBound.work} J${jobBound.number}',
      'BOUND machine ${machineBound.bound} M${machineBound.number}',
      'BOUND jackson ${jacksons[jacksonIndex]} M${jacksonIndex + 1}',
      'BOUND lower $lower',
    ]);
    var best = baselines.first;
    for (final b in baselines) {
      final x = b.schedule,
          path = b.schedule.path(),
          bottleneck = b.schedule.bottleneck(),
          search = b.search;
      lines.addAll([
        line([
          'RULE',
          b.rule,
          'makespan',
          x.makespanValue,
          'gap',
          percentage(x.makespanValue - lower, lower),
          'flow',
          x.flow(),
          'idle',
          x.idle(),
          'decisions',
          b.decisions,
          'ties',
          b.ties,
        ]),
        line([
          'PATH',
          b.rule,
          'operations',
          path.length,
          'blocks',
          x.blocks(path).length,
          'critical_paths',
          x.pathCount(),
          'bottleneck',
          'M${bottleneck.$1}',
        ]),
        line([
          'TABU',
          b.rule,
          'makespan',
          x.makespanValue,
          '->',
          search.bestValue,
          'found',
          search.found,
          'iterations',
          search.records.length,
          'stop',
          search.reason,
        ]),
      ]);
      if (x.makespanValue < best.schedule.makespanValue) best = b;
    }
    lines.add('BEST ${best.rule} makespan ${best.schedule.makespanValue}');
    for (final m in instance.machines) {
      lines.add(
        'UTILIZATION M${m.number} ${baselines.map((b) => '${b.rule} ${percentage(m.load, b.schedule.makespanValue)}').join(' ')}',
      );
    }
    return lines;
  }

  List<String> ganttLines() {
    final x = finalSchedule, onPath = finalSchedule.path().toSet();
    final (scale, columns) = chartScale(
      x.makespanValue,
      params.number('gantt_width'),
    );
    final rows = List.generate(instance.machineCount, (_) => <Interval>[]);
    for (final o in instance.operations) {
      final letter = jobLetter(o.job);
      rows[o.machine - 1].add((
        x.starts[o.ident],
        x.ends[o.ident],
        onPath.contains(o.ident) ? letter.toLowerCase() : letter,
      ));
    }
    final lines = [
      'GANTT scale $scale columns $columns',
      timeRow(scale, columns),
      ruleRow(columns),
    ];
    for (var m = 0; m < rows.length; m++) {
      lines.add(chartRow('M${m + 1}', rows[m], scale, columns));
    }
    lines.add(busyRow(rows, scale, columns));
    for (final j in instance.jobs) {
      lines.add(
        chartRow(
          'J${j.number}',
          [
            for (final id in j.operations)
              (
                x.starts[id],
                x.ends[id],
                '${instance.operations[id].machine % 10}',
              ),
          ],
          scale,
          columns,
        ),
      );
    }
    return lines;
  }

  List<String> scheduleLines() {
    final g = genetic,
        x = finalSchedule,
        bestIndex = ranking(genetic.values).first;
    final lines = [
      'GA best ${gaSchedule.makespanValue} generation ${g.records.last.$1} crossovers ${g.crossovers} swaps ${g.swaps} inserts ${g.inserts}',
    ];
    for (final r in g.records) {
      lines.add(
        'RECORD generation ${r.$1} makespan ${r.$2} individual ${r.$3}',
      );
    }
    final seen = <String>{};
    var rank = 0;
    for (final i in ranking(g.values)) {
      if (!seen.add(g.population[i].join(' '))) continue;
      rank++;
      final other = Schedule(instance, decode(instance, g.population[i]));
      lines.add(
        'TOP $rank individual ${i + 1} makespan ${g.values[i]} distance ${sum(machineDistances(other, gaSchedule))}',
      );
      if (rank == 5) break;
    }
    lines.addAll([
      'GA_CHROMOSOME ${g.population[bestIndex].join(' ')}',
      'ACTIVE_DECODE makespan $activeValue decisions $activeDecisions',
    ]);
    for (var i = 0; i < shifts.length; i++) {
      final shift = shifts[i], o = instance.operations[shifts[i].$1];
      lines.add(
        'SHIFT ${i + 1} ${o.code} M${o.machine} start ${shift.$2} -> ${shift.$3}',
      );
    }
    lines.addAll([
      'ACTIVATED makespan ${gaSchedule.makespanValue} -> $activatedValue shifts ${shifts.length}',
      line([
        'SCHEDULE',
        'makespan',
        x.makespanValue,
        'lower_bound',
        lower,
        'gap',
        percentage(x.makespanValue - lower, lower),
        'improvement',
        gaSchedule.makespanValue - x.makespanValue,
        'shiftable',
        x.shiftableCount(),
      ]),
      'CHROMOSOME ${x.chromosome().join(' ')}',
      'LEGEND ${instance.jobs.map((j) => '${jobLetter(j.number)}=J${j.number}').join(' ')}',
    ]);
    lines.addAll(ganttLines());
    for (final m in instance.machines) {
      lines.add(
        'ORDER M${m.number} FINAL ${x.letters(m.number)} ${baselines.map((b) => '${b.rule} ${b.schedule.letters(m.number)}').join(' ')}',
      );
    }
    for (final m in instance.machines) {
      final row = x.order[m.number - 1],
          sequence = <String>[],
          idle = <String>[];
      var gaps = 0, longest = 0, last = 0;
      for (var i = 0; i < row.length; i++) {
        final id = row[i];
        if (x.starts[id] > last) {
          idle.add('$last-${x.starts[id]}');
          if (i > 0) {
            gaps++;
            longest = math.max(longest, x.starts[id] - last);
          }
        }
        sequence.add(
          'J${instance.operations[id].job}:${x.starts[id]}-${x.ends[id]}',
        );
        last = x.ends[id];
      }
      if (last < x.makespanValue) idle.add('$last-${x.makespanValue}');
      lines.addAll([
        line([
          'MACHINE',
          'M${m.number}',
          'load',
          m.load,
          'idle',
          x.makespanValue - m.load,
          'utilization',
          percentage(m.load, x.makespanValue),
          'gaps',
          gaps,
          'longest_gap',
          longest,
          'sequence',
          sequence.join(' '),
        ]),
        'IDLE M${m.number} ${idle.isEmpty ? 'none' : idle.join(' ')}',
      ]);
    }
    var waiting = 0;
    for (final j in instance.jobs) {
      final completion = x.jobCompletion(j);
      waiting += completion - j.work;
      lines.add(
        line([
          'JOB',
          'J${j.number}',
          'operations',
          j.operations.length,
          'work',
          j.work,
          'start',
          x.starts[j.operations.first],
          'completion',
          completion,
          'waiting',
          completion - j.work,
        ]),
      );
    }
    lines.add('TOTAL flow ${x.flow()} waiting $waiting idle ${x.idle()}');
    final labels = [...rules, 'GA'],
        others = [...baselines.map((b) => b.schedule), gaSchedule],
        distances = [
          ...baselines.map((b) => machineDistances(x, b.schedule)),
          machineDistances(x, gaSchedule),
        ];
    var pairsTotal = 0;
    for (var m = 0; m < instance.machines.length; m++) {
      final q = instance.machines[m].operations.length,
          pairs =
              instance.machines[m].operations.length *
              (instance.machines[m].operations.length - 1) ~/
              2;
      pairsTotal += q * (q - 1) ~/ 2;
      lines.add(
        'DISTANCE M${m + 1} pairs $pairs ${[for (var j = 0; j < others.length; j++) '${labels[j]} ${distances[j][m]}'].join(' ')}',
      );
    }
    lines.add(
      'DISTANCE total pairs $pairsTotal ${[for (var j = 0; j < labels.length; j++) '${labels[j]} ${sum(distances[j])}'].join(' ')}',
    );
    return lines;
  }

  List<String> pathLines() {
    final x = finalSchedule,
        path = finalSchedule.path(),
        blocks = finalSchedule.blocks(finalSchedule.path());
    final lines = [
      'SEARCH start ${search.startValue} iterations ${params.tabuIterations} tenure ${params.tabuTenure}',
    ];
    for (final r in search.records) {
      final a = instance.operations[r.move.$1],
          b = instance.operations[r.move.$2];
      lines.add(
        line([
          'ITER',
          r.iteration,
          'moves',
          r.moves,
          'tabu',
          r.tabu,
          'swap',
          'M${a.machine}',
          a.code,
          b.code,
          r.aspiration ? 'aspiration' : 'free',
          'makespan',
          r.value,
          'best',
          r.best,
        ]),
      );
    }
    lines.addAll([
      'STOP iterations ${search.records.length} reason ${search.reason} best ${search.bestValue} found ${search.found}',
      'PATH operations ${path.length} blocks ${blocks.length} makespan ${x.makespanValue} critical_paths ${x.pathCount()}',
    ]);
    for (var i = 0; i < path.length; i++) {
      final id = path[i],
          o = instance.operations[path[i]],
          link = i == 0
              ? 'start'
              : x.machinePrevious[path[i]] == path[i - 1]
              ? 'machine'
              : 'job';
      lines.add(
        'NODE ${i + 1} ${o.code} M${o.machine} ${x.starts[id]}-${x.ends[id]} $link',
      );
    }
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      lines.add(
        'BLOCK ${i + 1} M${instance.operations[block.first].machine} ${x.starts[block.first]}-${x.ends[block.last]} ${block.map((id) => instance.operations[id].code).join(' ')}',
      );
    }
    final moves = x.moves();
    for (var i = 0; i < moves.length; i++) {
      final move = moves[i],
          a = instance.operations[moves[i].$1],
          b = instance.operations[moves[i].$2];
      lines.add(
        'NEIGHBOUR ${i + 1} M${a.machine} ${a.code} ${b.code} makespan ${scheduleOfOrder(instance, applyMove(instance, x.order, move)).makespanValue}',
      );
    }
    final (slack, free) = x.slacks();
    lines.add(
      'CRITICAL operations ${slack.where((v) => v == 0).length} total ${instance.operations.length}',
    );
    for (final kind in ['SLACK', 'FREE']) {
      final values = kind == 'SLACK' ? slack : free;
      for (final j in instance.jobs) {
        lines.add(
          '$kind J${j.number} ${j.operations.map((id) => values[id]).join(' ')}',
        );
      }
    }
    final counts = x.pathCounts();
    for (var m = 0; m < instance.machines.length; m++) {
      final machine = instance.machines[m],
          durations = List<int>.of(instance.durations);
      for (final id in machine.operations) {
        durations[id] += (durations[id] + 9) ~/ 10;
      }
      final value = makespan(
            orderStarts(instance, x.order, durations),
            durations,
          ),
          critical = machine.operations.where((id) => slack[id] == 0).length;
      lines.add(
        'MACHINE M${machine.number} critical $critical path ${counts[m]} sensitivity $value delta ${value - x.makespanValue}',
      );
    }
    final bottleneck = x.bottleneck();
    lines.add('BOTTLENECK M${bottleneck.$1} path ${bottleneck.$2}');
    return lines;
  }
}

void main() {
  final solver = Solver(loadInstance(), Parameters());
  Directory('output').createSync(recursive: true);
  writeLines('baselines.txt', solver.baselineLines());
  writeLines('ga_progress.csv', [
    'generation,best,mean,worst,distinct',
    ...solver.genetic.progress,
  ]);
  writeLines('best_schedule.txt', solver.scheduleLines());
  writeLines('critical_path.txt', solver.pathLines());
}
