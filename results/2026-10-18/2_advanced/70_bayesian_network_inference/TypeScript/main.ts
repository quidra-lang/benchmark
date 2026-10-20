import { mkdirSync, writeFileSync } from 'node:fs';
import { readInputs } from './network_io.ts';
import {
  combination,
  countFamily,
  familyScore,
  learn,
  logLikelihood,
  parameters,
} from './learning.ts';
import { assignments, cptFactor, reduce, scope, type Factor } from './factors.ts';
import { eliminate, plan, traceback, type Plan } from './elimination.ts';
import { Minstd, weightedSample } from './sampling.ts';

const { variables, samples, queries, settings } = readInputs();
const n = variables.length;
const N = samples.length;
const all = variables.map((_, v) => v);
const cards = variables.map((variable) => variable.states.length);
const names = new Map(variables.map((variable, v) => [variable.name, v]));
const parents = variables.map((variable) => variable.parents);
const children = all.map((v) => all.filter((u) => parents[u].includes(v)));
const sorted = (values: Iterable<number>) => [...new Set(values)].sort((a, b) => a - b);
const sequence = (values: number[]) =>
  values.length ? values.map((v) => variables[v].name).join(' ') : '-';
const format = (value: number) => {
  if (Math.abs(value) >= 1e21) return `${BigInt(value)}.0000`;
  const text = value.toFixed(4);
  return +text === 0 ? '0.0000' : text;
};
const total = (values: number[]) => {
  let result = 0;
  for (const value of values) result += value;
  return result;
};
const assignmentText = (assignment: number[], set: number[]) =>
  set.map((v) => `${variables[v].name}=${variables[v].states[assignment[v]]}`).join(' ');
const stateValues = (v: number, values: number[]) =>
  variables[v].states.map((state, s) => `${state} ${format(values[s])}`).join(' ');
const close = (a: number, b: number) => Math.abs(a - b) <= 1e-9;
const sameAssignment = (a: number[], b: number[]) => a.every((state, v) => state === b[v]);
function closure(start: number[], links = parents): number[] {
  const reached = new Set(start);
  const stack = [...start];
  while (stack.length) {
    for (const v of links[stack.pop()!]) {
      if (!reached.has(v)) {
        reached.add(v);
        stack.push(v);
      }
    }
  }
  return sorted(reached);
}
const ancestors = all.map((v) => closure([v]).filter((u) => u !== v));
const descendants = all.map((v) => closure([v], children).filter((u) => u !== v));
const spouses = all.map((v) =>
  sorted(children[v].flatMap((child) => parents[child])).filter(
    (u) => u !== v && !parents[v].includes(u) && !children[v].includes(u),
  ),
);
const blankets = all.map((v) => sorted([...parents[v], ...children[v], ...spouses[v]]));
const topological: number[] = [];
const selected = new Set<number>();
const depth = Array<number>(n).fill(0);
while (topological.length < n) {
  const v = all.find((v) => !selected.has(v) && parents[v].every((p) => selected.has(p)))!;
  selected.add(v);
  topological.push(v);
  for (const p of parents[v]) depth[v] = Math.max(depth[v], depth[p] + 1);
}
const counts = all.map((v) => countFamily(v, parents[v], cards, samples));
const learned = counts.map((count) => learn(count, settings.alpha));
const cpts = all.map((v) => (settings.sources[v] === 'GIVEN' ? variables[v].given! : learned[v]));
const factors = all.map((v) => cptFactor(v, parents[v], cpts[v], cards));
const ll = all.map((v) => logLikelihood(counts[v], cpts[v]));
const dimensions = counts.map(parameters);
const networkLl = total(ll);
const dimension = total(dimensions);
const makePlan = (initial: Factor[], set: number[], method = settings.method) =>
  plan(initial, set, method, settings.order, cards);
interface Posterior {
  relevant: number[];
  eliminated: number[];
  initial: Factor[];
  minfill: Plan;
  given: Plan;
  variables: number[];
  values: number[];
  z: number;
  alternate: number[];
  alternateZ: number;
}
function posterior(query: number[], evidence: Map<number, number>): Posterior {
  const relevant = closure([...query, ...evidence.keys()]);
  const initial = relevant.map((v) => reduce(factors[v], evidence, cards));
  const eliminated = relevant.filter((v) => !query.includes(v) && !evidence.has(v));
  const minfill = makePlan(initial, eliminated, 'MINFILL');
  const given = makePlan(initial, eliminated, 'GIVEN');
  const first = eliminate(initial, minfill, cards).factor;
  const second = eliminate(initial, given, cards).factor;
  const used = settings.method === 'MINFILL' ? first : second;
  const other = settings.method === 'MINFILL' ? second : first;
  const z = total(used.values);
  const alternateZ = total(other.values);
  return {
    relevant,
    eliminated,
    initial,
    minfill,
    given,
    variables: used.variables,
    values: used.values.map((value) => value / z),
    z,
    alternate: other.values.map((value) => value / alternateZ),
    alternateZ,
  };
}
function marginals(result: Posterior): Map<number, number[]> {
  const marginals = new Map(result.variables.map((v) => [v, Array<number>(cards[v]).fill(0)]));
  let index = 0;
  for (const assignment of assignments(result.variables, cards)) {
    const value = result.values[index++];
    for (const v of result.variables) marginals.get(v)![assignment[v]] += value;
  }
  return marginals;
}
function joint(assignment: number[], set: number[]): number {
  let probability = 1;
  for (const v of set) {
    probability *= cpts[v][combination(parents[v], assignment, cards)][assignment[v]];
  }
  return probability;
}
const assignmentCount = (set: number[]) => {
  let size = 1;
  for (const v of set) size *= cards[v];
  return size;
};
function parseEvidence(tokens: string[]): Map<number, number> {
  const evidence = new Map<number, number>();
  for (const token of tokens) {
    const [name, state] = token.split('=');
    const v = names.get(name)!;
    evidence.set(v, variables[v].states.indexOf(state));
  }
  return evidence;
}
function queryParts(tokens: string[]): { query: number[]; evidence: Map<number, number> } {
  const separator = tokens.indexOf('|');
  return {
    query: (separator < 0 ? tokens : tokens.slice(0, separator)).map((name) => names.get(name)!),
    evidence: parseEvidence(separator < 0 ? [] : tokens.slice(separator + 1)),
  };
}
function planLines(label: string, plan: Plan): string[] {
  return [
    `order ${label}`,
    ...plan.steps.map(
      (step) =>
        `step ${variables[step.variable].name} fill ${step.fill} scope ${sequence(step.variables)} entries ${step.size}`,
    ),
    `cost max ${plan.maximum} total ${plan.total}`,
  ];
}
const cptLines: string[] = [];
all.forEach((v) => {
  if (v) cptLines.push('');
  const variable = variables[v];
  const model = marginals(posterior([v], new Map())).get(v)!;
  const frequency = Array<number>(cards[v]).fill(0);
  for (const sample of samples) frequency[sample[v]]++;
  cptLines.push(
    `variable ${variable.name} source ${settings.sources[v]}`,
    `states ${variable.states.join(' ')}`,
    `parents ${sequence(parents[v])}`,
  );
  let row = 0;
  for (const assignment of assignments(parents[v], cards)) {
    cptLines.push(
      `row ${parents[v].length ? assignmentText(assignment, parents[v]) : '-'} counts ${counts[v][row].join(' ')} probs ${cpts[v][row].map(format).join(' ')}`,
    );
    row++;
  }
  cptLines.push(
    `loglik ${format(ll[v])} parameters ${dimensions[v]} bic ${format(ll[v] - (dimensions[v] * Math.log(N)) / 2)}`,
    `marginal model ${model.map(format).join(' ')} data ${frequency.map((count) => format(count / N)).join(' ')}`,
  );
  if (settings.sources[v] === 'LEARNED') {
    let difference = 0;
    const given = variable.given;
    if (given) {
      learned[v].forEach((row, r) =>
        row.forEach((value, s) => {
          difference = Math.max(difference, Math.abs(value - given[r][s]));
        }),
      );
    }
    cptLines.push(`given_difference ${given ? format(difference) : '-'}`);
  }
});
cptLines.push(
  '',
  `network samples ${N} pseudocount ${format(settings.alpha)} loglik ${format(networkLl)} parameters ${dimension} bic ${format(networkLl - (dimension * Math.log(N)) / 2)}`,
);
const moral = new Set<string>();
for (const factor of factors) {
  factor.variables.forEach((v, i) => {
    for (const u of factor.variables.slice(i + 1)) moral.add(`${v}:${u}`);
  });
}
const summaryMinfill = makePlan(factors, all, 'MINFILL');
const summaryGiven = makePlan(factors, all, 'GIVEN');
const width = (plan: Plan) => Math.max(...plan.steps.map((step) => step.variables.length)) - 1;
const structure = [
  `variables ${n} edges ${total(parents.map((set) => set.length))}`,
  `topological_order ${sequence(topological)}`,
  `roots ${sequence(all.filter((v) => !parents[v].length))}`,
  `leaves ${sequence(all.filter((v) => !children[v].length))}`,
  `moral_edges ${moral.size} width minfill ${width(summaryMinfill)} given ${width(summaryGiven)}`,
  ...all.map(
    (v) =>
      `variable ${variables[v].name} states ${cards[v]} parents ${parents[v].length} children ${children[v].length} depth ${depth[v]} ancestors ${ancestors[v].length} descendants ${descendants[v].length} blanket ${blankets[v].length}`,
  ),
];
const answers: string[] = [];
const eliminationLines: string[] = [];
const samplingLines = ['query,samples,variable,state,estimate,exact,abs_error'];
const random = new Minstd(settings.seed);
function appendBlock(destination: string[], lines: string[]): void {
  if (destination.length) destination.push('');
  destination.push(...lines);
}
function eliminationBlock(
  header: string,
  relevant: number[],
  eliminated: number[],
  minfill: Plan,
  given: Plan,
  agree: boolean,
  k: number,
  enumeration: string,
): void {
  appendBlock(eliminationLines, [
    header,
    `relevant ${sequence(relevant)}`,
    `pruned ${sequence(all.filter((v) => !relevant.includes(v)))}`,
    `eliminate ${sequence(eliminated)}`,
    ...planLines('minfill', minfill),
    ...planLines('given', given),
    `used ${settings.method.toLowerCase()}`,
    `orders_agree ${agree ? 'yes' : 'no'}`,
    `enumeration ${k} ${enumeration}`,
  ]);
}
function reachable(x: number[], z: number[]): number[] {
  const observed = new Set(z);
  const ancestorSet = new Set(closure(z));
  const visited = new Set<string>();
  const queue: { v: number; direction: 'up' | 'down' }[] = x.map((v) => ({ v, direction: 'up' }));
  for (let head = 0; head < queue.length; head++) {
    const { v, direction } = queue[head];
    const key = `${v}:${direction}`;
    if (visited.has(key)) continue;
    visited.add(key);
    if (direction === 'up' && !observed.has(v)) {
      for (const p of parents[v]) queue.push({ v: p, direction: 'up' });
      for (const c of children[v]) queue.push({ v: c, direction: 'down' });
    }
    if (direction === 'down') {
      if (!observed.has(v)) for (const c of children[v]) queue.push({ v: c, direction: 'down' });
      if (ancestorSet.has(v)) for (const p of parents[v]) queue.push({ v: p, direction: 'up' });
    }
  }
  return all.filter(
    (v) =>
      !observed.has(v) && !x.includes(v) && (visited.has(`${v}:up`) || visited.has(`${v}:down`)),
  );
}
function mutualInformation(
  x: number[],
  y: number[],
  z: number[],
): { cmi: number; g2: number; df: number } {
  const w = scope([...x, ...y, ...z]);
  const xz = scope([...x, ...z]);
  const yz = scope([...y, ...z]);
  const jointCounts = new Map<number, { count: number; assignment: number[] }>();
  const xCounts = new Map<number, number>();
  const yCounts = new Map<number, number>();
  const zCounts = new Map<number, number>();
  const increment = (counts: Map<number, number>, key: number) =>
    counts.set(key, (counts.get(key) ?? 0) + 1);
  for (const sample of samples) {
    const key = combination(w, sample, cards);
    const entry = jointCounts.get(key) ?? { count: 0, assignment: sample };
    entry.count++;
    jointCounts.set(key, entry);
    increment(xCounts, combination(xz, sample, cards));
    increment(yCounts, combination(yz, sample, cards));
    increment(zCounts, combination(z, sample, cards));
  }
  let cmi = 0;
  for (const [, { count, assignment }] of [...jointCounts].sort((a, b) => a[0] - b[0])) {
    const nz = zCounts.get(combination(z, assignment, cards))!;
    const nxz = xCounts.get(combination(xz, assignment, cards))!;
    const nyz = yCounts.get(combination(yz, assignment, cards))!;
    cmi += (count / N) * Math.log((count * nz) / (nxz * nyz));
  }
  return {
    cmi,
    g2: 2 * N * cmi,
    df: (assignmentCount(x) - 1) * (assignmentCount(y) - 1) * assignmentCount(z),
  };
}
function path(a: number, b: number, ignore?: [number, number]): number[] | undefined {
  const queue = [a];
  const marked = new Set([a]);
  const previous = new Map<number, number>();
  for (let head = 0; head < queue.length; head++) {
    for (const child of children[queue[head]]) {
      const parent = queue[head];
      if (ignore && parent === ignore[0] && child === ignore[1]) continue;
      if (marked.has(child)) continue;
      marked.add(child);
      previous.set(child, parent);
      if (child === b) {
        const result = [b];
        while (result[0] !== a) result.unshift(previous.get(result[0])!);
        return result;
      }
      queue.push(child);
    }
  }
  return undefined;
}
queries.forEach((line, queryIndex) => {
  const [kind, ...tokens] = line.split(' ');
  const number = queryIndex + 1;
  const header = `query ${number} ${line}`;
  if (kind === 'QUERY') {
    const { query, evidence } = queryParts(tokens);
    const result = posterior(query, evidence);
    const marginal = marginals(result);
    const block = [header, `log_evidence ${format(Math.log(result.z))}`];
    if (evidence.size) {
      let conflict = 0;
      for (const [v, state] of evidence) {
        conflict += Math.log(posterior([], new Map([[v, state]])).z);
      }
      block.push(`conflict ${format(conflict - Math.log(result.z))}`);
    }
    if (query.length >= 2) {
      let index = 0;
      for (const assignment of assignments(result.variables, cards)) {
        block.push(
          `joint ${assignmentText(assignment, result.variables)} ${format(result.values[index++])}`,
        );
      }
    }
    for (const v of query) {
      block.push(`marginal ${variables[v].name} ${stateValues(v, marginal.get(v)!)}`);
    }
    for (const [v, state] of evidence) {
      const reduced = new Map(evidence);
      reduced.delete(v);
      const dropped = marginals(posterior(query, reduced));
      let shift = 0;
      for (const q of query) {
        for (let s = 0; s < cards[q]; s++) {
          shift = Math.max(shift, Math.abs(marginal.get(q)![s] - dropped.get(q)![s]));
        }
      }
      block.push(`drop ${variables[v].name}=${variables[v].states[state]} shift ${format(shift)}`);
    }
    const agree =
      close(Math.log(result.z), Math.log(result.alternateZ)) &&
      result.values.every((value, i) => close(value, result.alternate[i]));
    const unknown = result.relevant.filter((v) => !evidence.has(v));
    const k = assignmentCount(unknown);
    let enumeration = 'skipped';
    if (k <= settings.limit) {
      const values = Array<number>(result.values.length).fill(0);
      for (const assignment of assignments(unknown, cards)) {
        for (const [v, state] of evidence) assignment[v] = state;
        values[combination(result.variables, assignment, cards)] += joint(
          assignment,
          result.relevant,
        );
      }
      const z = total(values);
      enumeration =
        close(Math.log(z), Math.log(result.z)) &&
        values.every((value, i) => close(value / z, result.values[i]))
          ? 'agree'
          : 'disagree';
    }
    appendBlock(answers, block);
    eliminationBlock(
      header,
      result.relevant,
      result.eliminated,
      result.minfill,
      result.given,
      agree,
      k,
      enumeration,
    );
  } else if (kind === 'MPE') {
    const evidence = parseEvidence(tokens);
    const initial = factors.map((factor) => reduce(factor, evidence, cards));
    const unknown = all.filter((v) => !evidence.has(v));
    const minfill = makePlan(initial, unknown, 'MINFILL');
    const given = makePlan(initial, unknown, 'GIVEN');
    const first = eliminate(initial, minfill, cards, true);
    const second = eliminate(initial, given, cards, true);
    const firstAssignment = traceback(first.products, minfill, evidence, cards);
    const secondAssignment = traceback(second.products, given, evidence, cards);
    const result = settings.method === 'MINFILL' ? first : second;
    const assignment = settings.method === 'MINFILL' ? firstAssignment : secondAssignment;
    const m = result.factor.values[0];
    const z = evidence.size ? posterior([], evidence).z : 1;
    const block = [
      header,
      `assignment ${assignmentText(assignment, all)}`,
      `log_joint ${format(Math.log(m))}`,
      `log_evidence ${format(Math.log(z))}`,
      `posterior ${format(m / z)}`,
    ];
    for (const v of unknown) {
      const marginPlan = makePlan(
        initial,
        unknown.filter((u) => u !== v),
      );
      const values = eliminate(initial, marginPlan, cards, true).factor.values;
      let chosen = -1;
      for (let state = 0; state < cards[v]; state++) {
        if (state !== assignment[v] && (chosen < 0 || values[state] > values[chosen])) {
          chosen = state;
        }
      }
      block.push(
        `margin ${variables[v].name} ${variables[v].states[chosen]} ${format(Math.log(m) - Math.log(values[chosen]))}`,
      );
    }
    const agree =
      sameAssignment(firstAssignment, secondAssignment) &&
      close(Math.log(first.factor.values[0]), Math.log(second.factor.values[0]));
    const k = assignmentCount(unknown);
    let enumeration = 'skipped';
    if (k <= settings.limit) {
      let best = -Infinity;
      let bestAssignment: number[] = [];
      for (const candidate of assignments(unknown, cards)) {
        for (const [v, state] of evidence) candidate[v] = state;
        const value = joint(candidate, all);
        if (value > best) {
          best = value;
          bestAssignment = candidate;
        }
      }
      enumeration =
        sameAssignment(bestAssignment, assignment) && close(Math.log(best), Math.log(m))
          ? 'agree'
          : 'disagree';
    }
    appendBlock(answers, block);
    eliminationBlock(header, all, unknown, minfill, given, agree, k, enumeration);
  } else if (kind === 'SAMPLE') {
    const separator = tokens.indexOf('COUNTS');
    const checkpoints = tokens.slice(separator + 1).map(Number);
    const { query, evidence } = queryParts(tokens.slice(0, separator));
    const exact = marginals(posterior(query, evidence));
    const weights = new Map(query.map((v) => [v, Array<number>(cards[v]).fill(0)]));
    const block = [
      header,
      ...query.map((v) => `exact ${variables[v].name} ${stateValues(v, exact.get(v)!)}`),
    ];
    let weight = 0;
    let squaredWeight = 0;
    let checkpoint = 0;
    for (let count = 1; count <= checkpoints.at(-1)!; count++) {
      const sample = weightedSample(variables, cpts, cards, topological, evidence, random);
      weight += sample.weight;
      squaredWeight += sample.weight * sample.weight;
      for (const v of query) weights.get(v)![sample.assignment[v]] += sample.weight;
      if (count !== checkpoints[checkpoint]) continue;
      checkpoint++;
      let maxError = 0;
      for (const v of query) {
        for (let state = 0; state < cards[v]; state++) {
          const estimate = weights.get(v)![state] / weight;
          const value = exact.get(v)![state];
          const error = Math.abs(estimate - value);
          maxError = Math.max(maxError, error);
          samplingLines.push(
            [
              number,
              count,
              variables[v].name,
              variables[v].states[state],
              format(estimate),
              format(value),
              format(error),
            ].join(','),
          );
        }
      }
      block.push(
        `after ${count} weight ${format(weight)} ess ${format((weight * weight) / squaredWeight)} max_error ${format(maxError)}`,
      );
    }
    appendBlock(answers, block);
  } else if (kind === 'PREDICT') {
    const v = names.get(tokens[0])!;
    const confusion = Array.from({ length: cards[v] }, () => Array<number>(cards[v]).fill(0));
    let correct = 0;
    let logLoss = 0;
    for (const sample of samples) {
      const assignment = [...sample];
      const values: number[] = [];
      for (let state = 0; state < cards[v]; state++) {
        assignment[v] = state;
        let value = cpts[v][combination(parents[v], assignment, cards)][state];
        for (const child of children[v]) {
          value *= cpts[child][combination(parents[child], assignment, cards)][assignment[child]];
        }
        values.push(value);
      }
      const denominator = total(values);
      const probabilities = values.map((value) => value / denominator);
      let predicted = 0;
      for (let state = 1; state < cards[v]; state++) {
        if (probabilities[state] > probabilities[predicted]) predicted = state;
      }
      confusion[sample[v]][predicted]++;
      if (sample[v] === predicted) correct++;
      logLoss += Math.log(probabilities[sample[v]]);
    }
    appendBlock(answers, [
      header,
      `blanket ${sequence(blankets[v])}`,
      `accuracy ${correct}/${N} ${format(correct / N)}`,
      `log_loss ${format(-logLoss / N)}`,
      `predicted ${variables[v].states.join(' ')}`,
      ...variables[v].states.map((state, s) => `actual ${state} ${confusion[s].join(' ')}`),
    ]);
  } else if (kind === 'DSEP') {
    const groups = tokens
      .join(' ')
      .split(' | ')
      .map((group) => group.split(' ').map((name) => names.get(name)!));
    const [x, y, z = []] = groups;
    const reached = reachable(x, z);
    const separated = y.every((v) => !reached.includes(v));
    const data = mutualInformation(x, y, z);
    appendBlock(structure, [
      header,
      `result ${separated ? 'separated' : 'connected'}`,
      `reachable ${sequence(reached)}`,
      `data cmi ${format(data.cmi)} g2 ${format(data.g2)} df ${data.df}`,
    ]);
  } else if (kind === 'BLANKET') {
    const v = names.get(tokens[0])!;
    const rest = all.filter((u) => u !== v && !blankets[v].includes(u));
    const reached = reachable([v], blankets[v]);
    appendBlock(structure, [
      header,
      `parents ${sequence(parents[v])}`,
      `children ${sequence(children[v])}`,
      `spouses ${sequence(spouses[v])}`,
      `blanket ${sequence(blankets[v])}`,
      `rest ${sequence(rest)}`,
      `rest_separated ${rest.every((u) => !reached.includes(u)) ? 'yes' : 'no'}`,
    ]);
  } else if (kind === 'EDGE') {
    const [operation, xName, yName] = tokens;
    const x = names.get(xName)!;
    const y = names.get(yName)!;
    const exists = parents[y].includes(x);
    const block = [header];
    if (operation === 'ADD' && exists) block.push('result exists');
    else if (operation !== 'ADD' && !exists) block.push('result missing');
    else {
      const found =
        operation === 'ADD' ? path(y, x) : operation === 'REVERSE' ? path(x, y, [x, y]) : undefined;
      if (found) {
        block.push(
          `result cycle ${[operation === 'ADD' ? x : y, ...found].map((v) => variables[v].name).join(' -> ')}`,
        );
      } else {
        const beforeY = familyScore(y, parents[y], cards, samples, settings.alpha);
        const newParents =
          operation === 'ADD' ? [...parents[y], x] : parents[y].filter((v) => v !== x);
        const afterY = familyScore(y, newParents, cards, samples, settings.alpha);
        let change = afterY - beforeY;
        block.push(
          'result ok',
          `family ${yName} before ${format(beforeY)} after ${format(afterY)}`,
        );
        if (operation === 'REVERSE') {
          const beforeX = familyScore(x, parents[x], cards, samples, settings.alpha);
          const afterX = familyScore(x, [...parents[x], y], cards, samples, settings.alpha);
          block.push(`family ${xName} before ${format(beforeX)} after ${format(afterX)}`);
          change += afterX - beforeX;
        }
        block.push(`delta ${format(change)} ${change > 0 ? 'improves' : 'worsens'}`);
      }
    }
    appendBlock(structure, block);
  }
});
mkdirSync('output', { recursive: true });
for (const [name, lines] of [
  ['cpts.txt', cptLines],
  ['structure.txt', structure],
  ['answers.txt', answers],
  ['elimination.txt', eliminationLines],
  ['sampling.csv', samplingLines],
] as const) {
  writeFileSync(`output/${name}`, lines.length ? lines.join('\n') + '\n' : '', 'ascii');
}
