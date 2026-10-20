import { mkdirSync, readFileSync } from 'node:fs';
import {
  InputError,
  wellFormedNumber,
  readDimacs,
  modelLines,
  type Formula,
  type Model,
} from './cnf_io.ts';
import { queens, pigeon, coloring, positions, type Graph } from './encoders.ts';
import { preprocess } from './preprocess.ts';
import { solveRound, type SearchStatistics } from './dpll.ts';
import {
  items,
  numberList,
  frequencyList,
  boardLines,
  writeParagraphs,
  writeCsv,
} from './report.ts';

type NumericArgument = 'size' | 'pigeons' | 'holes' | 'colors' | 'maximum' | 'limit';
type ArgumentKind = NumericArgument | 'file' | 'graph';
const ARGUMENTS = new Map<string, ArgumentKind[]>([
  ['SOLVE', ['file']],
  ['ENUM', ['file', 'limit']],
  ['CORE', ['file']],
  ['QUEENS', ['size', 'limit']],
  ['PIGEON', ['pigeons', 'holes', 'limit']],
  ['COLOR', ['graph', 'colors', 'limit']],
  ['CHROMATIC', ['graph', 'maximum']],
]);
const LIMITS: Record<NumericArgument, number> = {
  size: 8,
  pigeons: 8,
  holes: 8,
  colors: 6,
  maximum: 6,
  limit: 200,
};
const STAT_COLUMNS = [
  'job',
  'command',
  'status',
  'variables',
  'clauses',
  'removed_clauses',
  'decisions',
  'propagations',
  'conflicts',
  'max_depth',
  'models',
  'rounds',
];
interface Job {
  number: number;
  line: string;
  command: string;
  arguments: string[];
  file: string;
  graph?: Graph;
  size: number;
  pigeons: number;
  holes: number;
  colors: number;
  maximum: number;
  limit: number;
}
interface SolveResult {
  formula: Formula;
  preprocessing: ReturnType<typeof preprocess>;
  models: Model[];
  rounds: number;
  stop: 'preprocess' | 'all' | 'limit';
  status: 'SAT' | 'UNSAT';
  statistics: SearchStatistics;
  trace: string[];
  removed: number;
  attempts: { colors: number; result: SolveResult }[];
}
interface CompletedJob {
  job: Job;
  result: SolveResult;
  analysis: ReturnType<typeof analyzeModels>;
  core?: ReturnType<typeof unsatisfiableCore>;
}
function sum<T>(values: T[], select: (value: T) => number): number {
  let total = 0;
  for (const value of values) total += select(value);
  return total;
}
const emptyStatistics = (): SearchStatistics => ({
  decisions: 0,
  propagations: 0,
  conflicts: 0,
  maxDepth: 0,
});
function addStatistics(total: SearchStatistics, part: SearchStatistics): void {
  total.decisions += part.decisions;
  total.propagations += part.propagations;
  total.conflicts += part.conflicts;
  total.maxDepth = Math.max(total.maxDepth, part.maxDepth);
}
function analyzeGraph(graph: Graph): void {
  const adjacent: number[][] = Array.from({ length: graph.vertices + 1 }, () => []);
  for (const [a, b] of graph.edges) {
    adjacent[a].push(b);
    adjacent[b].push(a);
  }
  const order = Array.from({ length: graph.vertices }, (_, i) => i + 1).sort(
    (a, b) => adjacent[b].length - adjacent[a].length || a - b,
  );
  const colors: number[] = Array(graph.vertices + 1).fill(0);
  let maximumDegree = 0;
  let used = 0;
  for (const v of order) {
    maximumDegree = Math.max(maximumDegree, adjacent[v].length);
    const unavailable = new Set(adjacent[v].map((w) => colors[w]));
    let color = 1;
    while (unavailable.has(color)) color++;
    colors[v] = color;
    used = Math.max(used, color);
  }
  graph.maximumDegree = maximumDegree;
  graph.greedy = { used, colors: colors.slice(1) };
}
function readGraphs(): Map<string, Graph> {
  const graphs = new Map<string, Graph>();
  const lines = readFileSync('input/graphs.txt', 'ascii').split('\n');
  let graph: Graph | null = null;
  let seen = new Set<string>();
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (graph === null) {
      if (line === '' || line.startsWith('#')) continue;
      const [, name, vertices] = line.split(' ');
      graph = {
        name,
        vertices: Number(vertices),
        edges: [],
        reason: null,
        maximumDegree: 0,
        greedy: { used: 0, colors: [] },
      };
      graphs.set(name, graph);
      seen = new Set();
      continue;
    }
    if (line === 'END') {
      if (graph.reason === null) {
        graph.edges.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
        analyzeGraph(graph);
      }
      graph = null;
      continue;
    }
    if (graph.reason !== null) continue;
    const tokens = line.split(' ');
    let reason: string | null = null;
    if (tokens.length !== 2 || !tokens.every(wellFormedNumber)) reason = 'bad edge line';
    else {
      const a = Number(tokens[0]);
      const b = Number(tokens[1]);
      const edge: [number, number] = [Math.min(a, b), Math.max(a, b)];
      const key = edge.join(',');
      if (a < 1 || a > graph.vertices || b < 1 || b > graph.vertices) {
        reason = 'vertex out of range';
      } else if (a === b) reason = 'self loop';
      else if (seen.has(key)) reason = 'duplicate edge';
      else {
        graph.edges.push(edge);
        seen.add(key);
      }
    }
    if (reason !== null) graph.reason = `${reason} at line ${i + 1}`;
  }
  return graphs;
}
function readJobs(): Job[] {
  const jobs: Job[] = [];
  for (const line of readFileSync('input/jobs.txt', 'ascii').split('\n')) {
    if (line === '' || line.startsWith('#')) continue;
    const [command, ...args] = line.split(' ');
    jobs.push({
      number: jobs.length + 1,
      line,
      command,
      arguments: args,
      file: '',
      size: 0,
      pigeons: 0,
      holes: 0,
      colors: 0,
      maximum: 0,
      limit: 1,
    });
  }
  return jobs;
}
function validateJob(job: Job, graphs: Map<string, Graph>): void {
  const kinds = ARGUMENTS.get(job.command);
  if (kinds === undefined) throw new InputError(`unknown command ${job.command}`);
  if (job.arguments.length !== kinds.length) throw new InputError('wrong argument count');
  kinds.forEach((kind, i) => {
    const token = job.arguments[i];
    if (kind === 'file') {
      if (!/^[a-z0-9_]{1,20}\.cnf$/.test(token)) throw new InputError(`bad file name ${token}`);
      job.file = token;
    } else if (kind === 'graph') {
      const graph = graphs.get(token);
      if (graph === undefined) throw new InputError(`unknown graph ${token}`);
      if (graph.reason !== null) throw new InputError(`invalid graph ${token}: ${graph.reason}`);
      job.graph = graph;
    } else {
      if (!wellFormedNumber(token)) throw new InputError(`bad number ${token}`);
      const value = Number(token);
      if (value < 1 || value > LIMITS[kind]) throw new InputError(`out of range ${token}`);
      job[kind] = value;
    }
  });
}
function originalFormula(job: Job): Formula {
  if (job.file !== '') return readDimacs(`input/${job.file}`);
  if (job.command === 'QUEENS') return queens(job.size);
  if (job.command === 'PIGEON') return pigeon(job.pigeons, job.holes);
  return coloring(job.graph!, job.colors);
}
function solveFormula(formula: Formula, limit: number): SolveResult {
  const simplified = preprocess(formula, limit === 1);
  const result: SolveResult = {
    formula,
    preprocessing: simplified,
    models: [],
    rounds: 0,
    stop: 'limit',
    status: 'UNSAT',
    statistics: emptyStatistics(),
    trace: [],
    removed: simplified.removed,
    attempts: [],
  };
  if (simplified.emptyClause !== null) {
    result.stop = 'preprocess';
    return result;
  }
  const blocking: number[][] = [];
  while (result.models.length < limit) {
    const round = solveRound(formula.variables, [...simplified.clauses, ...blocking]);
    result.rounds++;
    if (result.rounds === 1) result.trace = round.events;
    addStatistics(result.statistics, round.statistics);
    if (!round.satisfiable) {
      result.stop = 'all';
      break;
    }
    const model: Model = Array(formula.variables + 1).fill(false);
    for (let x = 1; x <= formula.variables; x++) model[x] = simplified.fixed[x] ?? round.model![x];
    result.models.push(model);
    blocking.push(simplified.active.map((x) => (model[x] ? -x : x)));
  }
  if (result.models.length) result.status = 'SAT';
  return result;
}
function literalTrue(literal: number, model: Model, flipped = 0): boolean {
  const x = Math.abs(literal);
  const value = x === flipped ? !model[x] : model[x];
  return literal > 0 ? value : !value;
}
function analyzeModels(result: SolveResult) {
  const { formula, models } = result;
  if (models.length === 0) return null;
  let failure: { model: number; clause: number } | null = null;
  for (let i = 0; i < models.length && failure === null; i++) {
    for (let j = 0; j < formula.clauses.length; j++) {
      if (!formula.clauses[j].some((literal) => literalTrue(literal, models[i]))) {
        failure = { model: i + 1, clause: j + 1 };
        break;
      }
    }
  }
  const distribution = formula.clauses.map(
    (clause) => clause.filter((literal) => literalTrue(literal, models[0])).length,
  );
  const safe: number[] = [];
  for (let x = 1; x <= formula.variables; x++) {
    if (
      formula.clauses.every((clause) =>
        clause.some((literal) => literalTrue(literal, models[0], x)),
      )
    ) {
      safe.push(x);
    }
  }
  let diversity: { pairs: number; minimum: number; maximum: number } | null = null;
  if (models.length >= 2) {
    diversity = { pairs: 0, minimum: formula.variables, maximum: 0 };
    for (let i = 0; i < models.length; i++) {
      for (let j = i + 1; j < models.length; j++) {
        let distance = 0;
        for (let x = 1; x <= formula.variables; x++) if (models[i][x] !== models[j][x]) distance++;
        diversity.pairs++;
        diversity.minimum = Math.min(diversity.minimum, distance);
        diversity.maximum = Math.max(diversity.maximum, distance);
      }
    }
  }
  let backbone: number[] | null = null;
  if (result.stop === 'all') {
    backbone = [];
    for (let x = 1; x <= formula.variables; x++) {
      if (models.every((model) => model[x] === models[0][x])) backbone.push(models[0][x] ? x : -x);
    }
  }
  return { failure, distribution, safe, diversity, backbone };
}
function unsatisfiableCore(formula: Formula) {
  const retained = new Set(formula.clauses.map((_, i) => i + 1));
  let decisions = 0;
  let conflicts = 0;
  for (let number = 1; number <= formula.clauses.length; number++) {
    const clauses = formula.clauses.filter((_, i) => retained.has(i + 1) && i + 1 !== number);
    const result = solveFormula({ variables: formula.variables, clauses }, 1);
    decisions += result.statistics.decisions;
    conflicts += result.statistics.conflicts;
    if (result.status === 'UNSAT') retained.delete(number);
  }
  return { clauses: [...retained], decisions, conflicts };
}
function solveChromatic(job: Job): SolveResult {
  const attempts: SolveResult['attempts'] = [];
  const statistics = emptyStatistics();
  let rounds = 0;
  let removed = 0;
  for (let colors = 1; colors <= job.maximum; colors++) {
    const result = solveFormula(coloring(job.graph!, colors), 1);
    attempts.push({ colors, result });
    addStatistics(statistics, result.statistics);
    rounds += result.rounds;
    removed += result.removed;
    job.colors = colors;
    if (result.status === 'SAT') break;
  }
  return { ...attempts[attempts.length - 1].result, attempts, statistics, rounds, removed };
}
const heading = (job: Job): string => `JOB ${job.number} ${job.line}`;
const searchLine = (s: SearchStatistics): string =>
  items('search', {
    decisions: s.decisions,
    propagations: s.propagations,
    conflicts: s.conflicts,
    max_depth: s.maxDepth,
  });
const graphLine = (g: Graph): string =>
  items('graph', {
    vertices: g.vertices,
    edges: g.edges.length,
    max_degree: g.maximumDegree,
    greedy: g.greedy.used,
  });
function analysisLines(completed: CompletedJob, full = true): string[] {
  const { result, analysis: a } = completed;
  if (a === null) return [];
  const lines = [
    a.failure === null
      ? items('verify ok', {
          models: result.models.length,
          clauses: result.formula.clauses.length,
          true_literals: frequencyList(a.distribution),
        })
      : items('verify failed', a.failure),
    items('flips', { safe: a.safe.length, variables: numberList(a.safe) }),
  ];
  if (full && a.diversity !== null) {
    lines.push(
      items('diversity', {
        pairs: a.diversity.pairs,
        min_distance: a.diversity.minimum,
        max_distance: a.diversity.maximum,
      }),
    );
  }
  if (full && a.backbone !== null) {
    lines.push(items('backbone', { size: a.backbone.length, literals: numberList(a.backbone) }));
  }
  return lines;
}
function preprocessingLines(p: ReturnType<typeof preprocess>): string[] {
  const s = p.statistics;
  const r = p.records;
  const lines = [
    items('preprocess', {
      pure: p.pure ? 'on' : 'off',
      tautologies: s.tautologies,
      duplicate_literals: s.duplicateLiterals,
      unit_fixed: s.unitFixed,
      unit_removed: s.unitRemoved,
      subsumed: s.subsumed,
      pure_fixed: s.pureFixed,
      pure_removed: s.pureRemoved,
      removed: p.removed,
    }),
    items('removed_clauses', {
      tautology: numberList(r.tautology),
      unit: numberList(r.unit),
      subsumed: numberList(r.subsumed),
      pure: numberList(r.pure),
    }),
  ];
  if (p.emptyClause !== null) lines.push(items('simplified', { empty_clause: p.emptyClause }));
  else {
    const lengths = p.clauses.map((clause) => clause.length);
    lines.push(
      items('simplified', {
        clauses: p.clauses.length,
        literals: sum(lengths, (x) => x),
        lengths: frequencyList(lengths),
        fixed: p.fixedLiterals.length,
        active: p.active.length,
      }),
      items('fixed', { literals: numberList(p.fixedLiterals) }),
    );
  }
  return lines;
}
function jobParagraph(completed: CompletedJob): string[] {
  const { job, result: r } = completed;
  const lines = [heading(job)];
  if (job.command === 'CHROMATIC') {
    lines.push(graphLine(job.graph!));
    for (const attempt of r.attempts) {
      const a = attempt.result;
      const s = a.statistics;
      lines.push(
        items('attempt', {
          k: attempt.colors,
          clauses: a.formula.clauses.length,
          removed: a.removed,
          result: a.status,
          stop: a.stop,
          decisions: s.decisions,
          propagations: s.propagations,
          conflicts: s.conflicts,
          max_depth: s.maxDepth,
        }),
      );
    }
    lines.push(
      items(`result ${r.status}`, {
        chromatic: r.status === 'SAT' ? job.colors : '-',
        attempts: r.attempts.length,
      }),
      searchLine(r.statistics),
      ...analysisLines(completed, false),
    );
    return lines;
  }
  if (job.command === 'COLOR') lines.push(graphLine(job.graph!));
  const lengths = r.formula.clauses.map((clause) => clause.length);
  lines.push(
    items('formula', {
      variables: r.formula.variables,
      clauses: r.formula.clauses.length,
      literals: sum(lengths, (x) => x),
      lengths: frequencyList(lengths),
    }),
    ...preprocessingLines(r.preprocessing),
    items(`result ${r.status}`, { models: r.models.length, rounds: r.rounds, stop: r.stop }),
    searchLine(r.statistics),
  );
  if (r.rounds > 0) {
    lines.push(
      'trace ' +
        (r.trace.length ? r.trace.slice(0, 12).join(' ') : '-') +
        (r.trace.length > 12 ? ` +${r.trace.length - 12}` : ''),
    );
  }
  lines.push(...analysisLines(completed));
  if (completed.core) {
    const c = completed.core;
    lines.push(
      items('core', {
        size: c.clauses.length,
        decisions: c.decisions,
        conflicts: c.conflicts,
        clauses: numberList(c.clauses),
      }),
    );
  }
  return lines;
}
function summaryParagraph(jobs: Job[], valid: CompletedJob[]): string[] {
  const sat = valid.filter((c) => c.result.status === 'SAT').length;
  const lines = [
    items('SUMMARY', {
      jobs: jobs.length,
      sat,
      unsat: valid.length - sat,
      error: jobs.length - valid.length,
    }),
    items('totals', {
      models: sum(valid, (c) => c.result.models.length),
      rounds: sum(valid, (c) => c.result.rounds),
      decisions: sum(valid, (c) => c.result.statistics.decisions),
      propagations: sum(valid, (c) => c.result.statistics.propagations),
      conflicts: sum(valid, (c) => c.result.statistics.conflicts),
      removed_clauses: sum(valid, (c) => c.result.removed),
    }),
  ];
  for (const command of ARGUMENTS.keys()) {
    const group = valid.filter((c) => c.job.command === command);
    if (!group.length) continue;
    const sat = group.filter((c) => c.result.status === 'SAT').length;
    lines.push(
      items(`command ${command}`, {
        jobs: group.length,
        sat,
        unsat: group.length - sat,
        decisions: sum(group, (c) => c.result.statistics.decisions),
        propagations: sum(group, (c) => c.result.statistics.propagations),
        conflicts: sum(group, (c) => c.result.statistics.conflicts),
      }),
    );
  }
  const rankings: [string, keyof SearchStatistics, string][] = [
    ['hardest', 'conflicts', 'conflicts'],
    ['deepest', 'maxDepth', 'max_depth'],
    ['busiest', 'propagations', 'propagations'],
  ];
  if (valid.length) {
    for (const [label, field, output] of rankings) {
      let best = valid[0];
      for (const c of valid) {
        if (c.result.statistics[field] > best.result.statistics[field]) best = c;
      }
      lines.push(items(label, { job: best.job.number, [output]: best.result.statistics[field] }));
    }
  }
  return lines;
}
function modelParagraph(c: CompletedJob): string[] {
  const lines = [heading(c.job)];
  c.result.models.forEach((model, i) => lines.push(`model ${i + 1}`, ...modelLines(model)));
  return lines;
}
interface BoardClass {
  number: number;
  canonical: number[];
  first: number;
  found: number;
  orbit: number;
}
function queenCanonical(columns: number[]) {
  const n = columns.length;
  const transforms: number[][] = Array.from({ length: 8 }, () => Array(n).fill(0));
  for (let r = 1; r <= n; r++) {
    const c = columns[r - 1];
    const images = [
      [r, c],
      [c, n + 1 - r],
      [n + 1 - r, n + 1 - c],
      [n + 1 - c, r],
      [r, n + 1 - c],
      [n + 1 - r, c],
      [c, r],
      [n + 1 - c, n + 1 - r],
    ];
    images.forEach(([r, c], i) => {
      transforms[i][r - 1] = c;
    });
  }
  const compare = (a: number[], b: number[]) => {
    for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] - b[i];
    return 0;
  };
  transforms.sort(compare);
  return { canonical: transforms[0], orbit: new Set(transforms.map((t) => t.join(','))).size };
}
function colorCanonical(colors: number[]): number[] {
  const mapping = new Map<number, number>();
  return colors.map((color) => {
    if (!mapping.has(color)) mapping.set(color, mapping.size + 1);
    return mapping.get(color)!;
  });
}
function boardParagraph(completed: CompletedJob): string[] {
  const { job: j, result: r } = completed;
  const lines: string[] = [];
  if (j.command === 'PIGEON') {
    lines.push(items('PIGEON', { job: j.number, pigeons: j.pigeons, holes: j.holes }));
    r.models.forEach((model, i) => {
      const holes = positions(model, j.pigeons, j.holes);
      const empty: number[] = [];
      for (let h = 1; h <= j.holes; h++) if (!holes.includes(h)) empty.push(h);
      lines.push(
        items(`assignment ${i + 1}`, { holes: numberList(holes), empty: numberList(empty) }),
      );
    });
    let expected = j.pigeons > j.holes ? 0 : 1;
    if (expected) for (let i = 0; i < j.pigeons; i++) expected *= j.holes - i;
    lines.push(items('summary', { assignments: r.models.length, stop: r.stop, expected }));
    return lines;
  }
  const isQueen = j.command === 'QUEENS';
  const graph = j.graph;
  const classes: BoardClass[] = [];
  const lookup = new Map<string, BoardClass>();
  if (isQueen) lines.push(items('QUEENS', { job: j.number, n: j.size }));
  else {
    lines.push(
      items(j.command, {
        job: j.number,
        graph: graph!.name,
        vertices: graph!.vertices,
        edges: graph!.edges.length,
        colors: j.colors,
      }),
      items('greedy', { used: graph!.greedy.used, colors: numberList(graph!.greedy.colors) }),
    );
  }
  r.models.forEach((model, i) => {
    const sequence = positions(
      model,
      isQueen ? j.size : graph!.vertices,
      isQueen ? j.size : j.colors,
    );
    const symmetry = isQueen
      ? queenCanonical(sequence)
      : { canonical: colorCanonical(sequence), orbit: 0 };
    const key = symmetry.canonical.join(',');
    let entry = lookup.get(key);
    if (entry === undefined) {
      entry = {
        number: classes.length + 1,
        canonical: symmetry.canonical,
        orbit: symmetry.orbit,
        first: i + 1,
        found: 0,
      };
      classes.push(entry);
      lookup.set(key, entry);
    }
    entry.found++;
    if (isQueen) {
      lines.push(
        items(`solution ${i + 1}`, { columns: numberList(sequence), class: entry.number }),
      );
      if (entry.first === i + 1) lines.push(...boardLines(sequence));
    } else {
      const sizes: number[] = Array(j.colors).fill(0);
      for (const color of sequence) sizes[color - 1]++;
      lines.push(
        items(`coloring ${i + 1}`, {
          colors: numberList(sequence),
          used: new Set(sequence).size,
          sizes: numberList(sizes),
          class: entry.number,
        }),
      );
    }
  });
  for (const c of classes) {
    lines.push(
      isQueen
        ? items(`class ${c.number}`, {
            orbit: c.orbit,
            found: c.found,
            first: c.first,
            canonical: numberList(c.canonical),
          })
        : items(`class ${c.number}`, {
            found: c.found,
            first: c.first,
            canonical: numberList(c.canonical),
          }),
    );
  }
  lines.push(
    items('summary', {
      [isQueen ? 'solutions' : 'colorings']: r.models.length,
      stop: r.stop,
      classes: classes.length,
    }),
  );
  return lines;
}
function statisticsValues(c: CompletedJob): (string | number)[] {
  const r = c.result;
  const s = r.statistics;
  return [
    c.job.number,
    c.job.command,
    r.status,
    r.formula.variables,
    r.formula.clauses.length,
    r.removed,
    s.decisions,
    s.propagations,
    s.conflicts,
    s.maxDepth,
    r.models.length,
    r.rounds,
  ];
}
function main(): void {
  const graphs = readGraphs();
  const jobs = readJobs();
  const valid: CompletedJob[] = [];
  const results: string[][] = [];
  for (const job of jobs) {
    try {
      validateJob(job, graphs);
      const result =
        job.command === 'CHROMATIC'
          ? solveChromatic(job)
          : solveFormula(originalFormula(job), job.limit);
      const completed: CompletedJob = { job, result, analysis: analyzeModels(result) };
      if (job.command === 'CORE' && result.status === 'UNSAT') {
        completed.core = unsatisfiableCore(result.formula);
      }
      valid.push(completed);
      results.push(jobParagraph(completed));
    } catch (error) {
      if (!(error instanceof InputError)) throw error;
      results.push([heading(job), `error ${error.message}`]);
    }
  }
  results.push(summaryParagraph(jobs, valid));
  mkdirSync('output', { recursive: true });
  writeParagraphs('results.txt', results);
  writeParagraphs(
    'models.txt',
    valid.filter((c) => c.result.models.length > 0).map(modelParagraph),
  );
  writeParagraphs(
    'boards.txt',
    valid
      .filter((c) => ['QUEENS', 'PIGEON', 'COLOR', 'CHROMATIC'].includes(c.job.command))
      .map(boardParagraph),
  );
  writeCsv('stats.csv', [STAT_COLUMNS, ...valid.map(statisticsValues)]);
}
main();
