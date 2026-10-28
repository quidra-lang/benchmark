import 'dart:io';
import 'dart:math' as math;
part 'environment.dart';
part 'dynamic_programming.dart';
part 'td_learning.dart';
part 'monte_carlo.dart';
part 'report.dart';

const methods = ['mc', 'sarsa', 'q_learning', 'expected_sarsa', 'dyna_q'];
const policyNames = ['value_iteration', 'policy_iteration', ...methods];
const endings = ['goal', 'pit', 'timeout'];
const absorptionUnit = 100000000;
List<(int, int)> pairs(List<int> values) => [
  for (var i = 0; i < values.length; i += 2) (values[i], values[i + 1]),
];

class Settings {
  late final int gamma,
      stepReward,
      slipTotal,
      floorSlip,
      iceSlip,
      theta,
      episodes,
      stepLimit,
      blockSize,
      planningSteps,
      seed,
      rollouts,
      rolloutSeed;
  late final List<int> gammaSweep;
  late final List<(int, int)> slipSweep, alpha, epsilon;
  Settings() {
    final fields = <String, List<int>>{};
    for (final line in readLines('input/params.txt')) {
      final words = line.split(' ');
      fields[words.first] = words.skip(1).map(int.parse).toList();
    }
    gamma = fields['GAMMA']![0];
    stepReward = fields['STEP_REWARD']![0];
    slipTotal = fields['SLIP']![0];
    floorSlip = fields['SLIP']![1];
    iceSlip = fields['SLIP']![2];
    theta = fields['THETA']![0];
    gammaSweep = fields['GAMMA_SWEEP']!;
    slipSweep = pairs(fields['SLIP_SWEEP']!);
    episodes = fields['EPISODES']![0];
    stepLimit = fields['STEP_LIMIT']![0];
    blockSize = fields['BLOCK_SIZE']![0];
    alpha = pairs(fields['ALPHA']!);
    epsilon = pairs(fields['EPSILON']!);
    planningSteps = fields['PLANNING_STEPS']![0];
    seed = fields['SEED']![0];
    rollouts = fields['ROLLOUTS']![0];
    rolloutSeed = fields['ROLLOUT_SEED']![0];
  }
}

int scheduleValue(List<(int, int)> schedule, int episode) {
  var value = schedule.first.$2;
  for (final (start, number) in schedule) {
    if (start <= episode) value = number;
  }
  return value;
}

List<(int, int)> phaseRanges(Settings s) {
  final starts = {
    ...s.alpha.map((p) => p.$1),
    ...s.epsilon.map((p) => p.$1),
  }.toList()..sort();
  return [
    for (var i = 0; i < starts.length; i++)
      (starts[i], i + 1 < starts.length ? starts[i + 1] - 1 : s.episodes),
  ];
}

int agreements(List<int> a, List<int> b) {
  var count = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] == b[i]) count++;
  }
  return count;
}

int sum(Iterable<int> values) =>
    values.fold(0, (total, value) => total + value);
List<int> valueErrors(List<List<int>> q, List<int> optimal) => [
  for (var s = 0; s < q.length; s++) (rowMax(q[s]) - optimal[s]).abs(),
];
List<int> endingCounts(List<Episode> episodes) => [
  for (final ending in endings)
    episodes.where((e) => e.ending == ending).length,
];

class Episode {
  int total = 0, steps = 0;
  String ending = 'timeout';
  final List<int> cells;
  Episode(int start) : cells = [start];
}

class Learner {
  final String method;
  final Environment environment;
  final Settings settings;
  final RandomGenerator generator;
  final List<List<int>> q, visits;
  final DynaModel model;
  final ReturnAverages averages;
  int alpha = 0, epsilon = 0;
  final episodes = <Episode>[], blocks = <(int, int, int)>[];
  Learner(this.method, this.environment, this.settings)
    : generator = RandomGenerator(settings.seed),
      q = List.generate(
        environment.world.states.length,
        (_) => List.filled(4, 0),
      ),
      visits = List.generate(
        environment.world.states.length,
        (_) => List.filled(4, 0),
      ),
      model = DynaModel(environment.world.states.length),
      averages = ReturnAverages(environment.world.states.length);
  List<int> policy() => q.map(firstMax).toList();
  List<int> stateVisits() => visits.map(sum).toList();
  int select(int state) => choose(generator, q[state], epsilon);
  void learn(List<int> optimal, List<int> optimalPolicy) {
    for (var ep = 1; ep <= settings.episodes; ep++) {
      alpha = scheduleValue(settings.alpha, ep);
      epsilon = scheduleValue(settings.epsilon, ep);
      episodes.add(play());
      if (ep % settings.blockSize == 0)
        blocks.add((
          agreements(policy(), optimalPolicy),
          floorDiv(sum(valueErrors(q, optimal)), optimal.length),
          stateVisits().where((v) => v > 0).length,
        ));
    }
  }

  Episode play() {
    final w = environment.world,
        s = settings,
        ep = Episode(environment.world.start),
        history = <(int, int, int)>[];
    var state = w.startState,
        action = method == 'sarsa' ? select(w.startState) : 0;
    while (ep.steps < s.stepLimit) {
      if (method != 'sarsa') action = select(state);
      final (cell, reward) = environment.step(generator, state, action);
      visits[state][action]++;
      ep.total += reward;
      ep.steps++;
      ep.cells.add(cell);
      final next = w.stateIndex[cell];
      if (method == 'mc') {
        history.add((state, action, reward));
      } else {
        var future = 0, nextAction = action;
        if (next >= 0) {
          if (method == 'sarsa') {
            nextAction = select(next);
            future = q[next][nextAction];
          } else if (method == 'expected_sarsa') {
            future = expectedValue(q[next], epsilon);
          } else {
            future = rowMax(q[next]);
          }
        }
        tdUpdate(
          q[state],
          action,
          tdTarget(reward, next < 0, future, s.gamma),
          alpha,
        );
        if (method == 'dyna_q') {
          model.record(state, action, reward, next);
          model.plan(generator, q, s.gamma, alpha, s.planningSteps);
        }
        action = nextAction;
      }
      if (next < 0) {
        ep.ending = w.terminalName(cell);
        break;
      }
      state = next;
    }
    if (method == 'mc') averages.update(q, history, s.gamma);
    return ep;
  }

  List<Episode> blockEpisodes(int number) => episodes.sublist(
    (number - 1) * settings.blockSize,
    number * settings.blockSize,
  );
  List<int> blockReturns() => [
    for (var number = 1; number <= blocks.length; number++)
      sum(blockEpisodes(number).map((e) => e.total)),
  ];
}

(String, List<int>) nominalPath(
  Environment e,
  List<int> policy,
  int origin,
  int limit,
) {
  final cells = [origin], seen = {origin};
  while (true) {
    final state = e.world.stateIndex[cells.last],
        target = e.moves[state][policy[state]],
        repeated = seen.contains(e.moves[state][policy[state]]);
    cells.add(target);
    seen.add(target);
    if (e.world.isTerminal(target))
      return (e.world.terminalName(target), cells);
    if (repeated) return ('loop', cells);
    if (cells.length - 1 == limit) return ('limit', cells);
  }
}

List<String> basinSymbols(Environment e, List<int> policy, int limit) {
  final symbols = <String>[];
  for (final cell in e.world.states) {
    final (ending, cells) = nominalPath(e, policy, cell, limit);
    symbols.add(
      ending == 'goal' || ending == 'pit'
          ? String.fromCharCode(97 + e.world.terminalIndex[cells.last])
          : '*',
    );
  }
  return symbols;
}

int riskyStates(Environment e, List<int> policy) {
  var count = 0;
  for (var s = 0; s < policy.length; s++) {
    if (e.transitions[s][policy[s]].any((t) => e.world.kinds[t.$1] == 'P'))
      count++;
  }
  return count;
}

List<int> distances(Environment e) {
  final w = e.world,
      distance = List.filled(e.world.kinds.length, -1),
      queue = [e.world.start];
  distance[w.start] = 0;
  for (var head = 0; head < queue.length; head++) {
    final cell = queue[head];
    for (final transitions in e.transitions[w.stateIndex[cell]]) {
      for (final (target, _) in transitions) {
        if (distance[target] < 0) {
          distance[target] = distance[cell] + 1;
          if (!w.isTerminal(target)) queue.add(target);
        }
      }
    }
  }
  return distance;
}

(int, int, int) symmetry(World w, List<int> values, List<int> policy) {
  var pairs = 0, equal = 0, mirrored = 0;
  const mirrorActions = [0, 3, 2, 1];
  for (var s = 0; s < w.states.length; s++) {
    final cell = w.states[s],
        col = cell % w.cols,
        mirrorCol = w.cols - 1 - col,
        other = w.stateIndex[cell ~/ w.cols * w.cols + mirrorCol];
    if (col < mirrorCol && other >= 0) {
      pairs++;
      if (values[s] == values[other]) equal++;
      if (policy[other] == mirrorActions[policy[s]]) mirrored++;
    }
  }
  return (pairs, equal, mirrored);
}

(int, int, int) absorption(Environment e, List<int> policy, int limit) {
  var goal = List.filled(policy.length, 0),
      pit = List.filled(policy.length, 0),
      expected = List.filled(policy.length, 0);
  for (var i = 0; i < limit; i++) {
    final ng = List.filled(policy.length, 0),
        np = List.filled(policy.length, 0),
        ne = List.filled(policy.length, 0);
    for (var s = 0; s < policy.length; s++) {
      var g = 0, p = 0, t = 0;
      for (final (cell, weight) in e.transitions[s][policy[s]]) {
        final target = e.world.stateIndex[cell];
        if (target >= 0) {
          g += weight * goal[target];
          p += weight * pit[target];
          t += weight * expected[target];
        } else if (e.world.kinds[cell] == 'G') {
          g += weight * absorptionUnit;
        } else {
          p += weight * absorptionUnit;
        }
      }
      ng[s] = g ~/ e.slipTotal;
      np[s] = p ~/ e.slipTotal;
      ne[s] = absorptionUnit + t ~/ e.slipTotal;
    }
    goal = ng;
    pit = np;
    expected = ne;
  }
  final start = e.world.startState;
  return (goal[start], pit[start], expected[start]);
}

(int, int) behaviourValue(
  Environment e,
  List<int> policy,
  int epsilon,
  int gamma,
  int theta,
) {
  final values = List.filled(policy.length, 0);
  for (var sweep = 1; ; sweep++) {
    var delta = 0;
    for (var s = 0; s < policy.length; s++) {
      final row = actionValues(e, values, gamma, s);
      var total = 0;
      for (var a = 0; a < 4; a++) {
        total +=
            (epsilon + (a == policy[s] ? 4 * (1000 - epsilon) : 0)) * row[a];
      }
      final value = floorDiv(total, 4000);
      delta = math.max(delta, (value - values[s]).abs());
      values[s] = value;
    }
    if (delta <= theta) return (values[e.world.startState], sweep);
  }
}

class RolloutSummary {
  final returns = <int>[],
      discounted = <int>[],
      steps = <int>[],
      endings = <String>[];
  final List<int> terminalCounts;
  RolloutSummary(int count) : terminalCounts = List.filled(count, 0);
}

RolloutSummary performRollouts(Environment e, List<int> policy, Settings s) {
  final w = e.world,
      generator = RandomGenerator(s.rolloutSeed),
      summary = RolloutSummary(e.world.terminals.length);
  for (var i = 0; i < s.rollouts; i++) {
    var state = w.startState, ending = 'timeout';
    final rewards = <int>[];
    while (rewards.length < s.stepLimit) {
      final (cell, reward) = e.step(generator, state, policy[state]);
      rewards.add(reward);
      state = w.stateIndex[cell];
      if (state < 0) {
        ending = w.terminalName(cell);
        summary.terminalCounts[w.terminalIndex[cell]]++;
        break;
      }
    }
    summary.returns.add(sum(rewards));
    summary.discounted.add(discountedReturn(rewards, s.gamma));
    summary.steps.add(rewards.length);
    summary.endings.add(ending);
  }
  return summary;
}

class PolicyEvaluation {
  late final List<int> values;
  late final int sweeps,
      agree,
      optimalActions,
      maxGapState,
      maxGap,
      improvedChanges,
      improvedStart,
      improvedAgree;
  late final (int, int, int) absorptionValues;
  late final RolloutSummary rollouts;
  PolicyEvaluation(Experiment x, List<int> policy) {
    final e = x.environment,
        s = x.settings,
        evaluated = evaluatePolicy(
          x.environment,
          policy,
          List.filled(policy.length, 0),
          x.settings.gamma,
          x.settings.theta,
        );
    values = evaluated.$1;
    sweeps = evaluated.$2;
    agree = agreements(policy, x.optimalPolicy);
    optimalActions = sum([
      for (var state = 0; state < policy.length; state++)
        x.optimalActions[state].contains(policy[state]) ? 1 : 0,
    ]);
    final gaps = [
      for (var state = 0; state < policy.length; state++)
        x.optimalValues[state] - values[state],
    ];
    maxGapState = firstMax(gaps);
    maxGap = gaps[maxGapState];
    final improved = greedyPolicy(e, values, s.gamma);
    improvedChanges = policy.length - agreements(improved, policy);
    improvedStart = evaluatePolicy(
      e,
      improved,
      List.filled(policy.length, 0),
      s.gamma,
      s.theta,
    ).$1[e.world.startState];
    improvedAgree = agreements(improved, x.optimalPolicy);
    absorptionValues = absorption(e, policy, s.stepLimit);
    rollouts = performRollouts(e, policy, s);
  }
}

class Experiment {
  final World world;
  final Settings settings;
  late final Environment environment;
  late final List<int> optimalValues,
      changes,
      optimalPolicy,
      iterationPolicy,
      iterationValues;
  late final List<List<int>> optimalQ, optimalActions;
  late final int inPlaceSweeps;
  late final List<(int, int, int)> rounds;
  final learners = <Learner>[],
      policies = <List<int>>[],
      evaluations = <PolicyEvaluation>[];
  Experiment(this.world, this.settings) {
    final s = settings;
    environment = environmentWith(s.floorSlip, s.iceSlip);
    final vi = valueIteration(environment, s.gamma, s.theta);
    optimalValues = vi.$1;
    changes = vi.$2;
    optimalQ = [
      for (var state = 0; state < world.states.length; state++)
        actionValues(environment, optimalValues, s.gamma, state),
    ];
    optimalPolicy = optimalQ.map(firstMax).toList();
    optimalActions = [
      for (final row in optimalQ)
        [
          for (var a = 0; a < 4; a++)
            if (row[a] == rowMax(row)) a,
        ],
    ];
    inPlaceSweeps = inPlaceValueIteration(environment, s.gamma, s.theta).$2;
    final pi = policyIteration(environment, s.gamma, s.theta);
    iterationPolicy = pi.$1;
    iterationValues = pi.$2;
    rounds = pi.$3;
    policies.addAll([optimalPolicy, iterationPolicy]);
    for (final method in methods) {
      final learner = Learner(method, environment, s);
      learner.learn(optimalValues, optimalPolicy);
      learners.add(learner);
      policies.add(learner.policy());
    }
    for (final policy in policies) {
      evaluations.add(PolicyEvaluation(this, policy));
    }
  }
  Environment environmentWith(int floor, int ice) =>
      Environment(world, settings.stepReward, settings.slipTotal, floor, ice);
  String stateText(int state) => cellText(world, world.states[state]);
  String sensitivity(Environment e, int gamma) {
    final (values, changes) = valueIteration(e, gamma, settings.theta);
    final policy = greedyPolicy(e, values, gamma);
    final (ending, cells) = nominalPath(
      e,
      policy,
      world.start,
      settings.stepLimit,
    );
    return 'iterations ${changes.length} value_start ${fixedText(values[world.startState])} path $ending steps ${cells.length - 1} last ${cellText(world, cells.last)} differences ${policy.length - agreements(policy, optimalPolicy)}';
  }

  List<String> valuesReport() {
    final w = world,
        s = settings,
        distance = distances(environment),
        kinds = world.kinds.split('');
    int count(String kind) => kinds.where((c) => c == kind).length;
    final worldPart = [
      'world rows ${w.rows} cols ${w.cols} states ${w.states.length} walls ${count('#')} floor ${count('.') + count('S')} ice ${count('~')} goals ${count('G')} pits ${count('P')}',
      'start ${cellText(w, w.start)} reachable ${w.states.where((cell) => distance[cell] >= 0).length}',
      for (var i = 0; i < w.terminals.length; i++)
        'terminal ${cellText(w, w.terminals[i])} ${w.terminalName(w.terminals[i])} reward ${w.rewards[i]} distance ${distance[w.terminals[i]] < 0 ? '-' : distance[w.terminals[i]]}',
    ];
    final vi = [
      'value_iteration gamma ${s.gamma} theta ${fixedText(s.theta)} iterations ${changes.length}',
      for (var i = 0; i < changes.length; i++)
        'iteration ${i + 1} max_change ${fixedText(changes[i])}',
    ];
    final ties = <String>[];
    for (var state = 0; state < optimalActions.length; state++) {
      if (optimalActions[state].length > 1)
        ties.add(
          'tie ${stateText(state)} ${optimalActions[state].map((a) => actionLetters[a]).join()}',
        );
    }
    ties.insert(0, 'ties ${ties.length}');
    final (pairs, equal, mirrored) = symmetry(w, optimalValues, optimalPolicy);
    ties.add(
      'symmetry pairs $pairs equal_values $equal mirrored_actions $mirrored',
    );
    final pi = [
      'policy_iteration rounds ${rounds.length}',
      for (var i = 0; i < rounds.length; i++)
        'round ${i + 1} sweeps ${rounds[i].$1} changed ${rounds[i].$2} value_start ${fixedText(rounds[i].$3)}',
    ];
    final differences = [
          for (var state = 0; state < optimalValues.length; state++)
            (iterationValues[state] - optimalValues[state]).abs(),
        ],
        n = w.states.length;
    final largest = firstMax(differences);
    final comparison = [
      'comparison policy_differences ${n - agreements(iterationPolicy, optimalPolicy)} max_value_difference ${fixedText(differences[largest])} at ${stateText(largest)}',
      'backups value_iteration ${changes.length * n * 4} in_place_iterations $inPlaceSweeps in_place ${inPlaceSweeps * n * 4} policy_iteration ${sum(rounds.map((r) => r.$1)) * n + rounds.length * n * 4}',
    ];
    return joinParts([
      worldPart,
      vi,
      ['optimal_values', ...valueGrid(w, optimalValues)],
      [
        'optimal_action_counts',
        ...gridLines(w, optimalActions.map((a) => '${a.length}').toList(), ''),
      ],
      ties,
      pi,
      ['policy_iteration_values', ...valueGrid(w, iterationValues)],
      comparison,
      [
        'gamma_sweep',
        for (final gamma in s.gammaSweep)
          'gamma $gamma ${sensitivity(environment, gamma)}',
      ],
      [
        'slip_sweep',
        for (final (floor, ice) in s.slipSweep)
          'slip $floor $ice ${sensitivity(environmentWith(floor, ice), s.gamma)}',
      ],
    ]);
  }

  List<String> policiesReport() {
    final parts = <List<String>>[];
    for (var i = 0; i < policies.length; i++) {
      final policy = policies[i],
          counts = [
            for (var a = 0; a < 4; a++)
              policies[i].where((value) => value == a).length,
          ];
      final (ending, cells) = nominalPath(
        environment,
        policy,
        world.start,
        settings.stepLimit,
      );
      final lines = [
        policyNames[i],
        ...policyGrid(world, policy),
        'path $ending steps ${cells.length - 1} ${cellsText(world, cells)}',
        'actions N ${counts[0]} E ${counts[1]} S ${counts[2]} W ${counts[3]} risk ${riskyStates(environment, policy)}',
        'basins',
        ...gridLines(
          world,
          basinSymbols(environment, policy, settings.stepLimit),
          '',
        ),
      ];
      if (i >= 2)
        lines.addAll([
          'visits',
          ...gridLines(
            world,
            learners[i - 2]
                .stateVisits()
                .map((count) => count == 0 ? '0' : '${count.toString().length}')
                .toList(),
            '',
          ),
        ]);
      parts.add(lines);
    }
    return joinParts(parts);
  }

  List<String> qTable() => [
    'method,row,col,action,value,visits',
    ...qTableRows(world, 'value_iteration', optimalQ, null),
    for (final l in learners) ...qTableRows(world, l.method, l.q, l.visits),
  ];
  List<String> learningCurves() {
    final lines = [
      'method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage',
    ];
    for (final l in learners) {
      for (var i = 0; i < l.blocks.length; i++) {
        final episodes = l.blockEpisodes(i + 1),
            b = l.blocks[i],
            counts = endingCounts(l.blockEpisodes(i + 1));
        lines.add(
          '${l.method},${i + 1},${averageText(sum(episodes.map((e) => e.total)), episodes.length)},${averageText(sum(episodes.map((e) => e.steps)), episodes.length)},${counts[0]},${counts[1]},${counts[2]},${b.$1},${fixedText(b.$2)},${b.$3}',
        );
      }
    }
    return lines;
  }

  List<String> evaluationReport() {
    final n = world.states.length, s = settings;
    final summary = [
      'summary states $n start ${cellText(world, world.start)} rollouts ${s.rollouts} step_limit ${s.stepLimit}',
    ];
    final values = [
          'policies',
          'policy agree optimal_actions value_start sweeps max_gap at',
        ],
        improvement = ['improvement', 'policy changed value_start agree'],
        absorb = ['absorption', 'policy p_goal p_pit p_timeout expected_steps'],
        rollouts = [
          'rollouts',
          'policy mean_return mean_discounted mean_steps goals pits timeouts min median max',
        ],
        terminals = [
          'terminals',
          'policy ${cellsText(world, world.terminals)}',
        ],
        agreement = ['agreement', 'policy ${policyNames.join(' ')}'];
    for (var i = 0; i < evaluations.length; i++) {
      final name = policyNames[i],
          v = evaluations[i],
          r = evaluations[i].rollouts;
      values.add(
        '$name ${v.agree} ${v.optimalActions} ${fixedText(v.values[world.startState])} ${v.sweeps} ${fixedText(v.maxGap)} ${stateText(v.maxGapState)}',
      );
      improvement.add(
        '$name ${v.improvedChanges} ${fixedText(v.improvedStart)} ${v.improvedAgree}',
      );
      final (goal, pit, expected) = v.absorptionValues;
      absorb.add(
        '$name ${fixedText(goal ~/ 10000)} ${fixedText(pit ~/ 10000)} ${fixedText((absorptionUnit - goal - pit) ~/ 10000)} ${fixedText(expected ~/ 10000)}',
      );
      final ordered = [...r.returns]..sort(),
          counts = [
            for (final ending in endings)
              r.endings.where((e) => e == ending).length,
          ];
      rollouts.add(
        '$name ${averageText(sum(r.returns), s.rollouts)} ${fixedText(floorDiv(sum(r.discounted), s.rollouts))} ${averageText(sum(r.steps), s.rollouts)} ${counts[0]} ${counts[1]} ${counts[2]} ${ordered.first} ${ordered[(s.rollouts + 1) ~/ 2 - 1]} ${ordered.last}',
      );
      terminals.add('$name ${r.terminalCounts.join(' ')}');
      agreement.add(
        '$name ${policies.map((other) => agreements(policies[i], other)).join(' ')}',
      );
    }
    final behaviour = ['behaviour', 'method epsilon value_start sweeps'],
        qErrors = ['q_errors', 'method mean_abs max_abs at unvisited tied'],
        actionErrors = ['q_action_errors', 'method N E S W'],
        training = [
          'training',
          'method steps goals pits timeouts best_block best_mean last_mean reach',
        ],
        visited = ['visited'],
        last = ['last_episodes'],
        phases = ['phases'];
    final epsilon = scheduleValue(s.epsilon, s.episodes),
        optimalReturn = sum(evaluations.first.rollouts.returns);
    for (final l in learners) {
      final policy = l.policy(),
          errors = valueErrors(l.q, optimalValues),
          visits = l.stateVisits();
      final (value, sweeps) = behaviourValue(
        environment,
        policy,
        epsilon,
        s.gamma,
        s.theta,
      );
      behaviour.add('${l.method} $epsilon ${fixedText(value)} $sweeps');
      final largest = firstMax(errors),
          unvisited = visits.where((v) => v == 0).length,
          tied = l.q
              .where((row) => row.where((v) => v == rowMax(row)).length > 1)
              .length;
      qErrors.add(
        '${l.method} ${fixedText(sum(errors) ~/ n)} ${fixedText(errors[largest])} ${stateText(largest)} $unvisited $tied',
      );
      final fields = [l.method];
      for (var a = 0; a < 4; a++) {
        var total = 0, count = 0;
        for (var state = 0; state < n; state++) {
          if (l.visits[state][a] > 0) {
            total += (l.q[state][a] - optimalQ[state][a]).abs();
            count++;
          }
        }
        fields.add(count > 0 ? fixedText(total ~/ count) : '-');
      }
      actionErrors.add(fields.join(' '));
      final counts = endingCounts(l.episodes),
          steps = sum(l.episodes.map((e) => e.steps)),
          totals = l.blockReturns(),
          best = firstMax(l.blockReturns());
      var reach = '-';
      for (var i = 0; i < totals.length; i++) {
        if (10 * s.rollouts * totals[i] >= 9 * s.blockSize * optimalReturn) {
          reach = '${i + 1}';
          break;
        }
      }
      training.add(
        '${l.method} $steps ${counts[0]} ${counts[1]} ${counts[2]} ${best + 1} ${averageText(totals[best], s.blockSize)} ${averageText(totals.last, s.blockSize)} $reach',
      );
      final order = List.generate(n, (i) => i)
        ..sort((a, b) {
          final cmp = visits[b].compareTo(visits[a]);
          return cmp != 0 ? cmp : a.compareTo(b);
        });
      visited.add(
        '${l.method} ${order.take(3).map((state) => '${stateText(state)}:${visits[state]}').join(' ')}',
      );
      final episode = l.episodes.last;
      last.add(
        '${l.method} return ${episode.total} steps ${episode.steps} end ${episode.ending} ${cellsText(world, episode.cells)}',
      );
      for (final (first, end) in phaseRanges(s)) {
        final episodes = l.episodes.sublist(first - 1, end);
        phases.add(
          '${l.method} $first-$end alpha ${scheduleValue(s.alpha, first)} epsilon ${scheduleValue(s.epsilon, first)} mean_return ${averageText(sum(episodes.map((e) => e.total)), episodes.length)} mean_steps ${averageText(sum(episodes.map((e) => e.steps)), episodes.length)} goals ${episodes.where((e) => e.ending == 'goal').length}',
        );
      }
    }
    return joinParts([
      summary,
      values,
      improvement,
      absorb,
      behaviour,
      qErrors,
      actionErrors,
      rollouts,
      terminals,
      agreement,
      training,
      visited,
      last,
      phases,
    ]);
  }
}

void main() {
  final x = Experiment(readWorld(), Settings());
  Directory('output').createSync(recursive: true);
  writeLines('values.txt', x.valuesReport());
  writeLines('policies.txt', x.policiesReport());
  writeLines('q_tables.csv', x.qTable());
  writeLines('learning_curves.csv', x.learningCurves());
  writeLines('evaluation.txt', x.evaluationReport());
}
