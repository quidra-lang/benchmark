import { readFileSync } from 'node:fs';
import {
  ACTIONS,
  readWorld,
  Minstd,
  TransitionModel,
  type World,
  type Ending,
} from './environment.ts';
import {
  floorDivide,
  firstMaximum,
  rowValues,
  actionValues,
  greedyPolicy,
  valueIteration,
  inPlaceValueIteration,
  evaluatePolicy,
  policyIteration,
} from './dynamic_programming.ts';
import { choose, nextValue, update, DynaModel } from './td_learning.ts';
import { FirstVisit, discountedReturn, type RecordedStep } from './monte_carlo.ts';
import { fixed, average, cell, grid, policyGrid, qRows, writeReports } from './report.ts';

const METHODS = ['mc', 'sarsa', 'q_learning', 'expected_sarsa', 'dyna_q'] as const;
type Method = (typeof METHODS)[number];
type Schedule = [number, number][];
interface Settings {
  gamma: number;
  stepReward: number;
  denominator: number;
  floorSlip: number;
  iceSlip: number;
  theta: number;
  gammaSweep: number[];
  slipSweep: Schedule;
  episodes: number;
  limit: number;
  blockSize: number;
  alpha: Schedule;
  epsilon: Schedule;
  planning: number;
  seed: number;
  rollouts: number;
  rolloutSeed: number;
  phases: { first: number; last: number }[];
  finalEpsilon: number;
}
interface Episode {
  totalReturn: number;
  steps: number;
  ending: Ending;
  path: number[];
}
function sum(values: number[]): number {
  let total = 0;
  for (const v of values) total += v;
  return total;
}
function maximum(values: number[]): number {
  return values[firstMaximum(values)];
}
function pairs(values: number[]): Schedule {
  const result: Schedule = [];
  for (let i = 0; i < values.length; i += 2) result.push([values[i], values[i + 1]]);
  return result;
}
function scheduleValue(schedule: Schedule, episode: number): number {
  let value = schedule[0][1];
  for (const [start, v] of schedule) {
    if (start > episode) break;
    value = v;
  }
  return value;
}
function readSettings(): Settings {
  const parameters = new Map(
    readFileSync('input/params.txt', 'ascii')
      .slice(0, -1)
      .split('\n')
      .map((line) => {
        const [name, ...values] = line.split(' ');
        return [name, values.map(Number)];
      }),
  );
  const p = (name: string) => parameters.get(name)!;
  const single = (name: string) => p(name)[0];
  const [denominator, floorSlip, iceSlip] = p('SLIP');
  const alpha = pairs(p('ALPHA'));
  const epsilon = pairs(p('EPSILON'));
  const episodes = single('EPISODES');
  const starts = [...new Set([...alpha, ...epsilon].map((pair) => pair[0]))].sort((a, b) => a - b);
  return {
    gamma: single('GAMMA'),
    stepReward: single('STEP_REWARD'),
    denominator,
    floorSlip,
    iceSlip,
    theta: single('THETA'),
    gammaSweep: p('GAMMA_SWEEP'),
    slipSweep: pairs(p('SLIP_SWEEP')),
    episodes,
    limit: single('STEP_LIMIT'),
    blockSize: single('BLOCK_SIZE'),
    alpha,
    epsilon,
    planning: single('PLANNING_STEPS'),
    seed: single('SEED'),
    rollouts: single('ROLLOUTS'),
    rolloutSeed: single('ROLLOUT_SEED'),
    phases: starts.map((first, i) => ({
      first,
      last: i + 1 < starts.length ? starts[i + 1] - 1 : episodes,
    })),
    finalEpsilon: scheduleValue(epsilon, episodes),
  };
}
function agreement(a: number[], b: number[]): number {
  return a.filter((v, i) => v === b[i]).length;
}
function largestEntry(values: number[]) {
  const at = firstMaximum(values);
  return { at, value: values[at] };
}
function distanceAnalysis(world: World, model: TransitionModel) {
  const distances: number[] = Array(world.cells.length).fill(-1);
  distances[world.start] = 0;
  let frontier = [world.start];
  let distance = 0;
  while (frontier.length) {
    const next: number[] = [];
    for (const p of frontier) {
      for (const transitions of model.transitions[world.index[p]]) {
        for (const t of transitions) {
          if (distances[t.cell] >= 0) continue;
          distances[t.cell] = distance + 1;
          if (t.next >= 0) next.push(t.cell);
        }
      }
    }
    frontier = next.sort((a, b) => a - b);
    distance++;
  }
  return { distances, reachable: world.states.filter((p) => distances[p] >= 0).length };
}
function symmetry(world: World, values: number[], policy: number[]) {
  const mirrorActions = [0, 3, 2, 1];
  let pairs = 0;
  let equal = 0;
  let actions = 0;
  world.states.forEach((p, s) => {
    const col = p % world.width;
    if (col >= world.width - 1 - col) return;
    const mirror = world.index[p + world.width - 1 - 2 * col];
    if (mirror < 0) return;
    pairs++;
    if (values[s] === values[mirror]) equal++;
    if (policy[mirror] === mirrorActions[policy[s]]) actions++;
  });
  return { pairs, equal, actions };
}
function prepareData() {
  const world = readWorld();
  const settings = readSettings();
  const model = new TransitionModel(
    world,
    settings.denominator,
    settings.floorSlip,
    settings.iceSlip,
    settings.stepReward,
  );
  const result = valueIteration(model, settings.gamma, settings.theta);
  const table = actionValues(model, result.values, settings.gamma);
  const policy = greedyPolicy(table);
  const optimal = {
    ...result,
    table,
    policy,
    actions: table.map((row) => [0, 1, 2, 3].filter((a) => row[a] === maximum(row))),
  };
  return {
    world,
    settings,
    model,
    optimal,
    inPlace: inPlaceValueIteration(model, settings.gamma, settings.theta),
    iteration: policyIteration(model, settings.gamma, settings.theta),
    distance: distanceAnalysis(world, model),
    symmetry: symmetry(world, optimal.values, policy),
  };
}
type Data = ReturnType<typeof prepareData>;
function episodeStatistics(episodes: Pick<Episode, 'totalReturn' | 'steps' | 'ending'>[]) {
  const result = {
    count: episodes.length,
    totalReturn: 0,
    totalSteps: 0,
    goals: 0,
    pits: 0,
    timeouts: 0,
  };
  for (const e of episodes) {
    result.totalReturn += e.totalReturn;
    result.totalSteps += e.steps;
    result[e.ending === 'goal' ? 'goals' : e.ending === 'pit' ? 'pits' : 'timeouts']++;
  }
  return result;
}
function blockRecord(
  data: Data,
  table: number[][],
  visits: number[][],
  episodes: Episode[],
  number: number,
) {
  return {
    number,
    ...episodeStatistics(episodes.slice(-data.settings.blockSize)),
    agree: agreement(greedyPolicy(table), data.optimal.policy),
    valueError: floorDivide(
      sum(table.map((r, s) => Math.abs(maximum(r) - data.optimal.values[s]))),
      table.length,
    ),
    coverage: visits.filter((row) => sum(row) > 0).length,
  };
}
function learn(data: Data, name: Method) {
  const { world, settings: s, model } = data;
  const table: number[][] = world.states.map(() => Array(4).fill(0));
  const visits = table.map((row) => [...row]);
  const random = new Minstd(s.seed);
  const mc = name === 'mc' ? new FirstVisit(table.length) : null;
  const dyna = name === 'dyna_q' ? new DynaModel() : null;
  const episodes: Episode[] = [];
  const blocks: ReturnType<typeof blockRecord>[] = [];
  for (let e = 1; e <= s.episodes; e++) {
    const alpha = scheduleValue(s.alpha, e);
    const epsilon = scheduleValue(s.epsilon, e);
    const trajectory: RecordedStep[] = [];
    const path = [world.start];
    let state = world.startIndex;
    let action = name === 'sarsa' ? choose(table, state, epsilon, random) : 0;
    let totalReturn = 0;
    let steps = 0;
    let ending: Ending = 'timeout';
    for (let step = 1; step <= s.limit; step++) {
      if (name !== 'sarsa') action = choose(table, state, epsilon, random);
      const result = model.step(state, action, random);
      visits[state][action]++;
      if (mc) trajectory.push({ state, action, reward: result.reward });
      else {
        let future = 0;
        let nextAction = action;
        if (name === 'sarsa') {
          if (result.next >= 0) {
            nextAction = choose(table, result.next, epsilon, random);
            future = table[result.next][nextAction];
          }
        } else future = nextValue(table, result.next, name === 'expected_sarsa' ? epsilon : null);
        update(table, state, action, result.reward, result.next, future, s.gamma, alpha);
        if (dyna) {
          dyna.record(state, action, result.reward, result.next);
          dyna.plan(table, s.planning, s.gamma, alpha, random);
        }
        if (name === 'sarsa') action = nextAction;
      }
      totalReturn += result.reward;
      steps++;
      path.push(result.cell);
      if (result.next < 0) {
        ending = world.terminalAt[result.cell]!.ending;
        break;
      }
      state = result.next;
    }
    if (mc) mc.update(table, trajectory, s.gamma);
    episodes.push({ totalReturn, steps, ending, path: e === s.episodes ? path : [] });
    if (e % s.blockSize === 0) {
      blocks.push(blockRecord(data, table, visits, episodes, floorDivide(e, s.blockSize)));
    }
  }
  return {
    name,
    table,
    visits,
    episodes,
    blocks,
    policy: greedyPolicy(table),
    visitTotals: visits.map(sum),
  };
}
type Learned = ReturnType<typeof learn>;
interface NominalPath {
  path: number[];
  steps: number;
  ending: 'goal' | 'pit' | 'loop' | 'limit';
  last: number;
}
function nominalPath(world: World, policy: number[], origin: number, limit: number): NominalPath {
  const path = [world.states[origin]];
  const seen = new Set(path);
  let state = origin;
  for (let steps = 1; ; steps++) {
    const reached = world.moves[state][policy[state]];
    const repeated = seen.has(reached);
    path.push(reached);
    const terminal = world.terminalAt[reached];
    if (terminal) return { path, steps, ending: terminal.ending, last: reached };
    if (repeated) return { path, steps, ending: 'loop', last: reached };
    if (steps === limit) return { path, steps, ending: 'limit', last: reached };
    seen.add(reached);
    state = world.index[reached];
  }
}
function describePolicy(data: Data, policy: number[]) {
  const { world, model, settings } = data;
  const actions = [0, 0, 0, 0];
  let risk = 0;
  const basins = world.states.map((_, state) => {
    actions[policy[state]]++;
    if (model.transitions[state][policy[state]].some((t) => world.cells[t.cell] === 'P')) risk++;
    const p = nominalPath(world, policy, state, settings.limit);
    return p.ending === 'goal' || p.ending === 'pit' ? world.terminalAt[p.last]!.symbol : '*';
  });
  return {
    actions,
    risk,
    basins,
    path: nominalPath(world, policy, world.startIndex, settings.limit),
  };
}
function absorption(data: Data, policy: number[]): number[] {
  const D = 100000000;
  const { world, model, settings } = data;
  let goals = policy.map(() => 0);
  let pits = [...goals];
  let expected = [...goals];
  for (let k = 1; k <= settings.limit; k++) {
    const ng: number[] = [];
    const np: number[] = [];
    const ne: number[] = [];
    for (let state = 0; state < policy.length; state++) {
      let g = 0;
      let p = 0;
      let e = 0;
      for (const t of model.transitions[state][policy[state]]) {
        if (t.next < 0) {
          if (world.cells[t.cell] === 'G') g += t.weight * D;
          else p += t.weight * D;
        } else {
          g += t.weight * goals[t.next];
          p += t.weight * pits[t.next];
          e += t.weight * expected[t.next];
        }
      }
      ng.push(floorDivide(g, model.denominator));
      np.push(floorDivide(p, model.denominator));
      ne.push(D + floorDivide(e, model.denominator));
    }
    goals = ng;
    pits = np;
    expected = ne;
  }
  const o = world.startIndex;
  return [goals[o], pits[o], D - goals[o] - pits[o], expected[o]];
}
function behaviourValue(data: Data, policy: number[]) {
  const { model, settings: s } = data;
  const values = policy.map(() => 0);
  let sweeps = 0;
  while (true) {
    let delta = 0;
    for (let state = 0; state < policy.length; state++) {
      const row = rowValues(model, values, state, s.gamma);
      let total = 0;
      for (let a = 0; a < 4; a++) {
        total +=
          (s.finalEpsilon + (a === policy[state] ? 4 * (1000 - s.finalEpsilon) : 0)) * row[a];
      }
      const next = floorDivide(total, 4000);
      delta = Math.max(delta, Math.abs(next - values[state]));
      values[state] = next;
    }
    sweeps++;
    if (delta <= s.theta) return { start: values[data.world.startIndex], sweeps };
  }
}
function rollouts(data: Data, policy: number[]) {
  const { world, model, settings: s } = data;
  const random = new Minstd(s.rolloutSeed);
  const terminals = world.terminals.map(() => 0);
  const episodes: Pick<Episode, 'totalReturn' | 'steps' | 'ending'>[] = [];
  let totalDiscounted = 0;
  for (let m = 0; m < s.rollouts; m++) {
    let state = world.startIndex;
    let totalReturn = 0;
    let ending: Ending = 'timeout';
    const rewards: number[] = [];
    for (let step = 1; step <= s.limit; step++) {
      const r = model.step(state, policy[state], random);
      rewards.push(r.reward);
      totalReturn += r.reward;
      if (r.next < 0) {
        const t = world.terminalAt[r.cell]!;
        terminals[t.number]++;
        ending = t.ending;
        break;
      }
      state = r.next;
    }
    totalDiscounted += discountedReturn(rewards, s.gamma);
    episodes.push({ totalReturn, steps: rewards.length, ending });
  }
  const returns = episodes.map((e) => e.totalReturn).sort((a, b) => a - b);
  return {
    ...episodeStatistics(episodes),
    totalDiscounted,
    terminals,
    minimum: returns[0],
    median: returns[floorDivide(s.rollouts + 1, 2) - 1],
    maximum: returns[returns.length - 1],
  };
}
function qErrors(data: Data, method: Learned) {
  const errors = method.table.map((r, s) => Math.abs(maximum(r) - data.optimal.values[s]));
  const perAction = ACTIONS.map((_, a) => {
    let total = 0;
    let count = 0;
    method.table.forEach((row, state) => {
      if (method.visits[state][a] > 0) {
        total += Math.abs(row[a] - data.optimal.table[state][a]);
        count++;
      }
    });
    return count ? floorDivide(total, count) : null;
  });
  return {
    mean: floorDivide(sum(errors), errors.length),
    ...largestEntry(errors),
    perAction,
    unvisited: method.visitTotals.filter((v) => !v).length,
    tied: method.table.filter((r) => r.filter((v) => v === maximum(r)).length > 1).length,
  };
}
function assessPolicy(data: Data, name: string, policy: number[]) {
  const { model, settings: s, optimal, world } = data;
  const e = evaluatePolicy(model, policy, s.gamma, s.theta);
  const improved = greedyPolicy(actionValues(model, e.values, s.gamma));
  const improvedValue = evaluatePolicy(model, improved, s.gamma, s.theta);
  return {
    name,
    policy,
    assessment: {
      agree: agreement(policy, optimal.policy),
      optimalActions: policy.filter((a, state) => optimal.actions[state].includes(a)).length,
      start: e.values[world.startIndex],
      sweeps: e.sweeps,
      gap: largestEntry(optimal.values.map((v, state) => v - e.values[state])),
    },
    improvement: {
      changed: policy.length - agreement(policy, improved),
      start: improvedValue.values[world.startIndex],
      agree: agreement(improved, optimal.policy),
    },
    description: describePolicy(data, policy),
    absorption: absorption(data, policy),
    rollouts: rollouts(data, policy),
  };
}
type Assessed = ReturnType<typeof assessPolicy>;
function trainingSummary(data: Data, method: Learned, optimalReturn: number) {
  let best = method.blocks[0];
  let reach: number | '-' = '-';
  for (const b of method.blocks) {
    if (b.totalReturn > best.totalReturn) best = b;
    if (
      reach === '-' &&
      10 * data.settings.rollouts * b.totalReturn >= 9 * data.settings.blockSize * optimalReturn
    ) {
      reach = b.number;
    }
  }
  const visited = method.visitTotals
    .map((visits, state) => ({ state, visits }))
    .sort((a, b) => b.visits - a.visits || a.state - b.state)
    .slice(0, 3);
  const phases = data.settings.phases.map((p) => ({
    ...p,
    alpha: scheduleValue(data.settings.alpha, p.first),
    epsilon: scheduleValue(data.settings.epsilon, p.first),
    ...episodeStatistics(method.episodes.slice(p.first - 1, p.last)),
  }));
  return {
    ...episodeStatistics(method.episodes),
    best,
    last: method.blocks[method.blocks.length - 1],
    reach,
    visited,
    phases,
  };
}
function sensitivity(data: Data) {
  const analyze = (model: TransitionModel, gamma: number) => {
    const result = valueIteration(model, gamma, data.settings.theta);
    const policy = greedyPolicy(actionValues(model, result.values, gamma));
    return {
      iterations: result.iterations,
      start: result.values[data.world.startIndex],
      path: nominalPath(data.world, policy, data.world.startIndex, data.settings.limit),
      differences: policy.length - agreement(policy, data.optimal.policy),
    };
  };
  return {
    gamma: data.settings.gammaSweep.map((gamma) => ({ gamma, ...analyze(data.model, gamma) })),
    slip: data.settings.slipSweep.map(([f, i]) => ({
      f,
      i,
      ...analyze(
        new TransitionModel(data.world, data.settings.denominator, f, i, data.settings.stepReward),
        data.settings.gamma,
      ),
    })),
  };
}
function sections(parts: string[][]): string[] {
  return parts.flatMap((p, i) => (i ? ['', ...p] : p));
}
function valuesReport(data: Data, sweep: ReturnType<typeof sensitivity>): string[] {
  const { world: w, settings: s, optimal: o, iteration: pi } = data;
  const count = (symbols: string) => w.cells.filter((c) => symbols.includes(c)).length;
  const world = [
    `world rows ${w.height} cols ${w.width} states ${w.states.length} walls ${count('#')} floor ${count('.S')} ice ${count('~')} goals ${count('G')} pits ${count('P')}`,
    `start ${cell(w, w.start)} reachable ${data.distance.reachable}`,
    ...w.terminals.map(
      (t) =>
        `terminal ${cell(w, t.cell)} ${t.ending} reward ${t.reward} distance ${data.distance.distances[t.cell] < 0 ? '-' : data.distance.distances[t.cell]}`,
    ),
  ];
  const iteration = [
    `value_iteration gamma ${s.gamma} theta ${fixed(s.theta)} iterations ${o.iterations}`,
    ...o.changes.map((d, i) => `iteration ${i + 1} max_change ${fixed(d)}`),
  ];
  const ties = [`ties ${o.actions.filter((a) => a.length > 1).length}`];
  o.actions.forEach((a, state) => {
    if (a.length > 1) {
      ties.push(`tie ${cell(w, w.states[state])} ${a.map((i) => ACTIONS[i]).join('')}`);
    }
  });
  ties.push(
    `symmetry pairs ${data.symmetry.pairs} equal_values ${data.symmetry.equal} mirrored_actions ${data.symmetry.actions}`,
  );
  const rounds = [
    `policy_iteration rounds ${pi.rounds.length}`,
    ...pi.rounds.map(
      (r) =>
        `round ${r.number} sweeps ${r.sweeps} changed ${r.changed} value_start ${fixed(r.start)}`,
    ),
  ];
  const difference = largestEntry(o.values.map((v, state) => Math.abs(pi.values[state] - v)));
  const n = w.states.length;
  const comparison = [
    `comparison policy_differences ${n - agreement(pi.policy, o.policy)} max_value_difference ${fixed(difference.value)} at ${cell(w, w.states[difference.at])}`,
    `backups value_iteration ${o.iterations * n * 4} in_place_iterations ${data.inPlace.iterations} in_place ${data.inPlace.iterations * n * 4} policy_iteration ${sum(pi.rounds.map((r) => r.sweeps)) * n + pi.rounds.length * n * 4}`,
  ];
  const detail = (r: Omit<ReturnType<typeof sensitivity>['gamma'][number], 'gamma'>) =>
    `iterations ${r.iterations} value_start ${fixed(r.start)} path ${r.path.ending} steps ${r.path.steps} last ${cell(w, r.path.last)} differences ${r.differences}`;
  const gamma = ['gamma_sweep', ...sweep.gamma.map((r) => `gamma ${r.gamma} ${detail(r)}`)];
  const slip = ['slip_sweep', ...sweep.slip.map((r) => `slip ${r.f} ${r.i} ${detail(r)}`)];
  return sections([
    world,
    iteration,
    ['optimal_values', ...grid(w, (state) => fixed(o.values[state]), true)],
    ['optimal_action_counts', ...grid(w, (state) => o.actions[state].length)],
    ties,
    rounds,
    ['policy_iteration_values', ...grid(w, (state) => fixed(pi.values[state]), true)],
    comparison,
    gamma,
    slip,
  ]);
}
function policiesReport(data: Data, policies: Assessed[], methods: Learned[]): string[] {
  return sections(
    policies.map((p) => {
      const d = p.description;
      const path = d.path;
      const w = data.world;
      const lines = [
        p.name,
        ...policyGrid(w, p.policy),
        `path ${path.ending} steps ${path.steps} ${path.path.map((pos) => cell(w, pos)).join(' ')}`,
        `actions N ${d.actions[0]} E ${d.actions[1]} S ${d.actions[2]} W ${d.actions[3]} risk ${d.risk}`,
        'basins',
        ...grid(w, (state) => d.basins[state]),
      ];
      const method = methods.find((m) => m.name === p.name);
      if (method) {
        lines.push(
          'visits',
          ...grid(w, (state) =>
            method.visitTotals[state] ? String(method.visitTotals[state]).length : 0,
          ),
        );
      }
      return lines;
    }),
  );
}
function evaluationReport(data: Data, policies: Assessed[], methods: Learned[]): string[] {
  const { world: w, settings: s } = data;
  const sc = (state: number) => cell(w, w.states[state]);
  const values = ['policies', 'policy agree optimal_actions value_start sweeps max_gap at'];
  const improved = ['improvement', 'policy changed value_start agree'];
  const absorbed = ['absorption', 'policy p_goal p_pit p_timeout expected_steps'];
  const trials = [
    'rollouts',
    'policy mean_return mean_discounted mean_steps goals pits timeouts min median max',
  ];
  const terminals = ['terminals', `policy ${w.terminals.map((t) => cell(w, t.cell)).join(' ')}`];
  const agreements = ['agreement', `policy ${policies.map((p) => p.name).join(' ')}`];
  for (const p of policies) {
    const a = p.assessment;
    const i = p.improvement;
    const r = p.rollouts;
    values.push(
      `${p.name} ${a.agree} ${a.optimalActions} ${fixed(a.start)} ${a.sweeps} ${fixed(a.gap.value)} ${sc(a.gap.at)}`,
    );
    improved.push(`${p.name} ${i.changed} ${fixed(i.start)} ${i.agree}`);
    absorbed.push(`${p.name} ${p.absorption.map((v) => fixed(floorDivide(v, 10000))).join(' ')}`);
    trials.push(
      `${p.name} ${average(r.totalReturn, s.rollouts)} ${fixed(floorDivide(r.totalDiscounted, s.rollouts))} ${average(r.totalSteps, s.rollouts)} ${r.goals} ${r.pits} ${r.timeouts} ${r.minimum} ${r.median} ${r.maximum}`,
    );
    terminals.push(`${p.name} ${r.terminals.join(' ')}`);
    agreements.push(`${p.name} ${policies.map((q) => agreement(p.policy, q.policy)).join(' ')}`);
  }
  const behaviour = ['behaviour', 'method epsilon value_start sweeps'];
  const errors = ['q_errors', 'method mean_abs max_abs at unvisited tied'];
  const actionErrors = ['q_action_errors', 'method N E S W'];
  const training = [
    'training',
    'method steps goals pits timeouts best_block best_mean last_mean reach',
  ];
  const visited = ['visited'];
  const lastEpisodes = ['last_episodes'];
  const phases = ['phases'];
  for (const m of methods) {
    const b = behaviourValue(data, m.policy);
    const e = qErrors(data, m);
    const t = trainingSummary(data, m, policies[0].rollouts.totalReturn);
    const last = m.episodes[m.episodes.length - 1];
    behaviour.push(`${m.name} ${s.finalEpsilon} ${fixed(b.start)} ${b.sweeps}`);
    errors.push(
      `${m.name} ${fixed(e.mean)} ${fixed(e.value)} ${sc(e.at)} ${e.unvisited} ${e.tied}`,
    );
    actionErrors.push(`${m.name} ${e.perAction.map((v) => fixed(v)).join(' ')}`);
    training.push(
      `${m.name} ${t.totalSteps} ${t.goals} ${t.pits} ${t.timeouts} ${t.best.number} ${average(t.best.totalReturn, s.blockSize)} ${average(t.last.totalReturn, s.blockSize)} ${t.reach}`,
    );
    visited.push(`${m.name} ${t.visited.map((v) => `${sc(v.state)}:${v.visits}`).join(' ')}`);
    lastEpisodes.push(
      `${m.name} return ${last.totalReturn} steps ${last.steps} end ${last.ending} ${last.path.map((pos) => cell(w, pos)).join(' ')}`,
    );
    for (const p of t.phases) {
      phases.push(
        `${m.name} ${p.first}-${p.last} alpha ${p.alpha} epsilon ${p.epsilon} mean_return ${average(p.totalReturn, p.count)} mean_steps ${average(p.totalSteps, p.count)} goals ${p.goals}`,
      );
    }
  }
  return sections([
    [
      `summary states ${w.states.length} start ${cell(w, w.start)} rollouts ${s.rollouts} step_limit ${s.limit}`,
    ],
    values,
    improved,
    absorbed,
    behaviour,
    errors,
    actionErrors,
    trials,
    terminals,
    agreements,
    training,
    visited,
    lastEpisodes,
    phases,
  ]);
}
function main(): void {
  const data = prepareData();
  const methods = METHODS.map((name) => learn(data, name));
  const policies = [
    assessPolicy(data, 'value_iteration', data.optimal.policy),
    assessPolicy(data, 'policy_iteration', data.iteration.policy),
    ...methods.map((m) => assessPolicy(data, m.name, m.policy)),
  ];
  const q = [
    'method,row,col,action,value,visits',
    ...qRows('value_iteration', data.world, data.optimal.table),
    ...methods.flatMap((m) => qRows(m.name, data.world, m.table, m.visits)),
  ];
  const learning = [
    'method,block,mean_return,mean_steps,goals,pits,timeouts,agree,value_error,coverage',
    ...methods.flatMap((m) =>
      m.blocks.map((b) =>
        [
          m.name,
          b.number,
          average(b.totalReturn, data.settings.blockSize),
          average(b.totalSteps, data.settings.blockSize),
          b.goals,
          b.pits,
          b.timeouts,
          b.agree,
          fixed(b.valueError),
          b.coverage,
        ].join(','),
      ),
    ),
  ];
  writeReports({
    'values.txt': valuesReport(data, sensitivity(data)),
    'policies.txt': policiesReport(data, policies, methods),
    'q_tables.csv': q,
    'learning_curves.csv': learning,
    'evaluation.txt': evaluationReport(data, policies, methods),
  });
}
main();
