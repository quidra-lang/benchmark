import {
  readInput,
  real,
  modelLines,
  write,
  type Sequence,
  type Labeled,
  type Model,
} from './model_io.ts';
import { decode, viterbi, maximum } from './inference.ts';
import { baumWelch, counting, totalLoglik } from './training.ts';
import {
  matrix,
  accumulate,
  correct,
  metricLines,
  runs,
  overlaps,
  boundaries,
  boundaryMatches,
  fraction,
  type Segment,
} from './evaluation.ts';
import { Random, synthetic, posteriorPath } from './sampler.ts';

const input = readInput();
const { alphabet } = input;
const { states, symbols, missing } = alphabet;
const k = states.length;
const m = symbols.length;
const values = (key: string) => input.parameters.get(key) ?? [];
const number = (key: string) => Number(values(key)[0]);
const p = {
  iterations: number('iterations'),
  pseudocount: number('pseudocount'),
  smoothing: values('smoothing'),
  folds: number('folds'),
  minLength: number('min_sequence_length'),
  maxMissing: number('max_missing_percent'),
  segment: states.indexOf(values('segment_state')[0]),
  gap: number('merge_gap'),
  minSegment: number('min_segment_length'),
  motif: values('motif').map((c) => symbols.indexOf(c)),
  rich: new Set(values('rich_symbols').map((c) => symbols.indexOf(c))),
  minRich: number('min_rich_percent'),
  minMotif: number('min_motif_percent'),
  confidence: number('confidence'),
  tolerance: number('boundary_tolerance'),
  posteriorSeed: number('posterior_seed'),
  posteriorSamples: number('posterior_samples'),
  sampleSeed: number('sample_seed'),
  sampleCount: number('sample_count'),
  sampleLength: number('sample_length'),
};
interface Rejection {
  file: string;
  line: number;
  name: string;
  reason: string;
}
const rejected: Rejection[] = [];
const unlabeled: Sequence[] = [];
const labeled: Labeled[] = [];
function validate(
  name: string,
  raw: string,
  seen: Set<string>,
  labels?: string,
): string | undefined {
  const duplicate = seen.has(name);
  seen.add(name);
  if (duplicate) return 'duplicate name';
  const obs = raw.toUpperCase();
  const bad = [...obs].findIndex((c) => c !== missing && !symbols.includes(c));
  if (bad >= 0) return `invalid symbol ${obs[bad]} at position ${bad + 1}`;
  if (labels !== undefined) {
    const badLabel = [...labels].findIndex((c) => !states.includes(c));
    if (badLabel >= 0) return `invalid label ${labels[badLabel]} at position ${badLabel + 1}`;
    if (obs.length !== labels.length) return `length mismatch ${obs.length} ${labels.length}`;
  }
  if (obs.length < p.minLength) return `too short ${obs.length}`;
  const absent = [...obs].filter((c) => c === missing).length;
  if (100 * absent > p.maxMissing * obs.length) return `too many missing ${absent}`;
}
const observations = (raw: string) =>
  [...raw.toUpperCase()].map((c) => (c === missing ? -1 : symbols.indexOf(c)));
const sequenceNames = new Set<string>();
const recordNames = new Set<string>();
input.sequences.forEach(([name, raw], i) => {
  const reason = validate(name, raw, sequenceNames);
  if (reason) rejected.push({ file: 'sequences.txt', line: i + 1, name, reason });
  else unlabeled.push({ name, obs: observations(raw) });
});
for (let i = 0; i < input.labeled.length; i += 2) {
  const [name, role, raw] = input.labeled[i].split(' ');
  const labels = input.labeled[i + 1];
  const reason = validate(name, raw, recordNames, labels);
  if (reason) rejected.push({ file: 'labeled.txt', line: i + 1, name, reason });
  else {
    labeled.push({
      name,
      role: role === 'TRAIN' ? 'TRAIN' : 'TEST',
      obs: observations(raw),
      path: [...labels].map((c) => states.indexOf(c)),
    });
  }
}
const train = labeled.filter((r) => r.role === 'TRAIN');
const test = labeled.filter((r) => r.role === 'TEST');
const unobs = unlabeled.map((s) => s.obs);
const testobs = test.map((s) => s.obs);
const heldout = [...train, ...test].map((s) => s.obs);
const positions = (records: Sequence[]) => records.reduce((sum, s) => sum + s.obs.length, 0);
const missingCount = (records: Sequence[]) =>
  records.reduce((sum, s) => sum + s.obs.filter((c) => c < 0).length, 0);
const z = positions(unlabeled);
const observed = z - missingCount(unlabeled);
const trainZ = positions(train);
const testZ = positions(test);
const pathText = (path: number[]) => path.map((s) => states[s]).join('');
function segments(path: number[]): Segment[] {
  const merged: Segment[] = [];
  for (const run of runs(path).filter((r) => r.state === p.segment)) {
    const last = merged[merged.length - 1];
    if (last && run.start - last.end - 1 <= p.gap) last.end = run.end;
    else merged.push({ start: run.start, end: run.end });
  }
  return merged.filter((s) => s.end - s.start + 1 >= p.minSegment);
}
function composition(obs: number[], segment: Segment) {
  let n = 0;
  let r = 0;
  let q = 0;
  let k1 = 0;
  let k2 = 0;
  for (let t = segment.start; t <= segment.end; t++) {
    const c = obs[t];
    if (c >= 0) {
      n++;
      if (p.rich.has(c)) r++;
      if (c === p.motif[0]) k1++;
      if (c === p.motif[1]) k2++;
    }
    if (t < segment.end && c === p.motif[0] && obs[t + 1] === p.motif[1]) q++;
  }
  return {
    rich: n === 0 ? null : r / n,
    ratio: k1 * k2 === 0 ? null : (q * n) / (k1 * k2),
    island: k1 * k2 > 0 && 100 * r >= p.minRich * n && 100 * q * n >= p.minMotif * k1 * k2,
  };
}

const bwTrace = ['iteration,loglik,heldout,change,max_change,status'];
let bw = input.model;
let previousL = totalLoglik(bw, unobs);
let bestH = totalLoglik(bw, heldout);
let bestIteration = 0;
let violations = 0;
const initialL = previousL;
bwTrace.push(`0,${real(previousL)},${real(bestH)},,,`);
const probabilities = (model: Model) => [...model.pi, ...model.a.flat(), ...model.b.flat()];
for (let iteration = 1; iteration <= p.iterations; iteration++) {
  const next = baumWelch(bw, unobs, p.pseudocount);
  const likelihood = totalLoglik(next, unobs);
  const held = totalLoglik(next, heldout);
  const old = probabilities(bw);
  const change = Math.max(...probabilities(next).map((v, i) => Math.abs(v - old[i])));
  const violation = likelihood < previousL - 0.000001 * Math.abs(previousL);
  if (violation) violations++;
  if (held > bestH) {
    bestH = held;
    bestIteration = iteration;
  }
  bwTrace.push(
    `${iteration},${real(likelihood)},${real(held)},${real(likelihood - previousL)},${real(change, 6)},${violation ? 'violation' : 'ok'}`,
  );
  bw = next;
  previousL = likelihood;
}
const vtTrace = ['iteration,logprob,loglik,changed'];
let vt = input.model;
let vtDecoded = unobs.map((obs) => viterbi(vt, obs));
let vtIterations = 0;
let converged = false;
const logprob = (decoded: ReturnType<typeof viterbi>[]) =>
  decoded.reduce((sum, d) => sum + d.logprob, 0);
vtTrace.push(`0,${real(logprob(vtDecoded))},${real(initialL)},`);
for (let iteration = 1; iteration <= p.iterations; iteration++) {
  vt = counting(
    unobs.map((obs, i) => ({ obs, path: vtDecoded[i].path })),
    k,
    m,
    p.pseudocount,
    'VITERBI_TRAINING',
  );
  const next = unobs.map((obs) => viterbi(vt, obs));
  const changed = next.reduce(
    (sum, d, i) => sum + d.path.length - correct(d.path, vtDecoded[i].path),
    0,
  );
  vtTrace.push(`${iteration},${real(logprob(next))},${real(totalLoglik(vt, unobs))},${changed}`);
  vtDecoded = next;
  vtIterations = iteration;
  converged = changed === 0;
  if (converged) break;
}
interface Fold {
  records: number;
  positions: number;
  correct: number;
}
const candidates = p.smoothing.map((text) => {
  const confusion = matrix(k);
  const folds: Fold[] = [];
  for (let fold = 0; fold < p.folds; fold++) {
    const model = counting(
      train.filter((_, i) => i % p.folds !== fold),
      k,
      m,
      Number(text),
    );
    const records = train.filter((_, i) => i % p.folds === fold);
    let count = 0;
    for (const record of records) {
      const path = viterbi(model, record.obs).path;
      count += correct(record.path, path);
      accumulate(confusion, record.path, path);
    }
    folds.push({ records: records.length, positions: positions(records), correct: count });
  }
  return { text, confusion, folds, correct: folds.reduce((sum, fold) => sum + fold.correct, 0) };
});
const selected = candidates[maximum(candidates.map((c) => c.correct))];
const supervised = counting(train, k, m, Number(selected.text));
const models = [input.model, bw, vt, supervised];
const evaluationBlocks: string[][] = [];
const testCorrect: number[][] = [];
for (const model of models) {
  const decoded = test.map((record) => decode(model, record.obs));
  const modelCorrect: number[] = [];
  for (let decoder = 0; decoder < 2; decoder++) {
    const confusion = matrix(k);
    const calibration = Array.from({ length: 10 }, () => ({ positions: 0, correct: 0 }));
    const recordLines: string[] = [];
    let predictedRegions = 0;
    let trueRegions = 0;
    let matchedPredicted = 0;
    let matchedTrue = 0;
    let predictedBoundaries = 0;
    let trueBoundaries = 0;
    let matchedPB = 0;
    let matchedTB = 0;
    let totalCorrect = 0;
    test.forEach((record, i) => {
      const d = decoded[i];
      const path = decoder === 0 ? d.viterbi.path : d.posterior;
      const count = correct(record.path, path);
      accumulate(confusion, record.path, path);
      totalCorrect += count;
      const predicted = segments(path);
      const truth = runs(record.path).filter((r) => r.state === p.segment);
      predictedRegions += predicted.length;
      trueRegions += truth.length;
      matchedPredicted += predicted.filter((a) => truth.some((b) => overlaps(a, b))).length;
      matchedTrue += truth.filter((a) => predicted.some((b) => overlaps(a, b))).length;
      const pb = boundaries(path);
      const tb = boundaries(record.path);
      predictedBoundaries += pb.length;
      trueBoundaries += tb.length;
      matchedPB += boundaryMatches(pb, tb, p.tolerance);
      matchedTB += boundaryMatches(tb, pb, p.tolerance);
      if (decoder === 1) {
        path.forEach((s, t) => {
          const bin = calibration[Math.min(9, Math.floor(10 * d.confidence[t]))];
          bin.positions++;
          if (s === record.path[t]) bin.correct++;
        });
      }
      recordLines.push(`RECORD ${record.name} length ${path.length} correct ${count}`);
    });
    const block = [
      `EVALUATION ${model.name} ${decoder === 0 ? 'VITERBI' : 'POSTERIOR'}`,
      ...metricLines(confusion, states),
      `REGIONS ${states[p.segment]} predicted ${predictedRegions} true ${trueRegions} precision ${fraction(matchedPredicted, predictedRegions)} recall ${fraction(matchedTrue, trueRegions)}`,
      `BOUNDARIES predicted ${predictedBoundaries} true ${trueBoundaries} precision ${fraction(matchedPB, predictedBoundaries)} recall ${fraction(matchedTB, trueBoundaries)}`,
    ];
    if (decoder === 1) {
      calibration.forEach((bin, b) => {
        if (bin.positions) {
          block.push(
            `CALIBRATION 0.${b}-${b === 9 ? '1.0' : '0.' + (b + 1)} positions ${bin.positions} correct ${bin.correct} accuracy ${fraction(bin.correct, bin.positions)}`,
          );
        }
      });
    }
    block.push(...recordLines);
    evaluationBlocks.push(block);
    modelCorrect.push(totalCorrect);
  }
  testCorrect.push(modelCorrect);
}
evaluationBlocks.push([
  `CROSS_VALIDATION folds ${p.folds}`,
  ...candidates.map(
    (c) =>
      `SMOOTHING ${c.text} positions ${trainZ} correct ${c.correct} accuracy ${fraction(c.correct, trainZ)}`,
  ),
  `SELECTED ${selected.text}`,
  ...selected.folds.map(
    (fold, f) =>
      `FOLD ${f + 1} records ${fold.records} positions ${fold.positions} correct ${fold.correct} accuracy ${fraction(fold.correct, fold.positions)}`,
  ),
  ...metricLines(selected.confusion, states),
]);
const learning = ['LEARNING_CURVE'];
for (let r = 1; r <= train.length; r++) {
  const model = counting(train.slice(0, r), k, m, Number(selected.text));
  const count = test.reduce(
    (sum, record) => sum + correct(record.path, viterbi(model, record.obs).path),
    0,
  );
  learning.push(`RECORDS ${r} correct ${count} accuracy ${fraction(count, testZ)}`);
}
evaluationBlocks.push(learning);

const decodings: string[] = [];
const segmentLines = [
  'sequence,decoder,start,end,length,mean_posterior,support,rich_fraction,motif_ratio,island',
];
const posteriorRandom = new Random(p.posteriorSeed);
for (const sequence of unlabeled) {
  const d = decode(bw, sequence.obs);
  const samples = Array.from({ length: p.posteriorSamples }, () =>
    posteriorPath(bw, d.forward, posteriorRandom),
  );
  const expected =
    samples.reduce((sum, path) => sum + segments(path).length, 0) / p.posteriorSamples;
  const imputed = sequence.obs
    .map((c, t) => {
      if (c >= 0) return symbols[c];
      const weights = symbols.map((_, c) => {
        let total = 0;
        for (let i = 0; i < k; i++) total += d.gamma[t][i] * bw.b[i][c];
        return total;
      });
      return symbols[maximum(weights)].toLowerCase();
    })
    .join('');
  decodings.push(
    `SEQUENCE ${sequence.name} length ${sequence.obs.length} loglik ${real(d.loglik)} viterbi ${real(d.viterbi.logprob)} differences ${sequence.obs.length - correct(d.viterbi.path, d.posterior)} uncertain ${d.confidence.filter((v) => v < p.confidence).length} expected_segments ${real(expected)}`,
    'VITERBI ' + pathText(d.viterbi.path),
    'POSTERIOR ' + pathText(d.posterior),
    'CONFIDENT ' +
      d.posterior.map((s, t) => (d.confidence[t] < p.confidence ? '.' : states[s])).join(''),
    'IMPUTED ' + imputed,
  );
  [d.viterbi.path, d.posterior].forEach((path, decoder) => {
    for (const segment of segments(path)) {
      const length = segment.end - segment.start + 1;
      let mean = 0;
      for (let t = segment.start; t <= segment.end; t++) mean += d.gamma[t][p.segment];
      const support = samples.filter((sample) => {
        let count = 0;
        for (let t = segment.start; t <= segment.end; t++) if (sample[t] === p.segment) count++;
        return 2 * count > length;
      }).length;
      const c = composition(sequence.obs, segment);
      segmentLines.push(
        [
          sequence.name,
          decoder === 0 ? 'viterbi' : 'posterior',
          segment.start + 1,
          segment.end + 1,
          length,
          real(mean / length),
          support,
          real(c.rich),
          real(c.ratio),
          c.island ? 'yes' : 'no',
        ].join(','),
      );
    }
  });
}
const samples: string[] = [];
const sampleRandom = new Random(p.sampleSeed);
let syntheticV = 0;
let syntheticP = 0;
for (let n = 1; n <= p.sampleCount; n++) {
  const sample = synthetic(bw, p.sampleLength, sampleRandom);
  const d = decode(bw, sample.obs);
  const vc = correct(sample.path, d.viterbi.path);
  const pc = correct(sample.path, d.posterior);
  syntheticV += vc;
  syntheticP += pc;
  samples.push(
    `SAMPLE ${n} loglik ${real(d.loglik)} viterbi ${real(d.viterbi.logprob)} viterbi_correct ${vc} posterior_correct ${pc}`,
    'STATES ' + pathText(sample.path),
    'SYMBOLS ' + sample.obs.map((c) => symbols[c]).join(''),
    'VITERBI ' + pathText(d.viterbi.path),
    'POSTERIOR ' + pathText(d.posterior),
  );
}
const syntheticZ = p.sampleCount * p.sampleLength;
samples.push(
  `TOTAL positions ${syntheticZ} viterbi_accuracy ${fraction(syntheticV, syntheticZ)} posterior_accuracy ${fraction(syntheticP, syntheticZ)}`,
);

function runStatistics(paths: number[][]) {
  const occupancy = Array<number>(k).fill(0);
  const count = Array<number>(k).fill(0);
  for (const path of paths) {
    for (const run of runs(path)) {
      occupancy[run.state] += run.end - run.start + 1;
      count[run.state]++;
    }
  }
  return { occupancy, mean: occupancy.map((n, i) => (count[i] === 0 ? null : n / count[i])) };
}
function stationary(model: Model): number[] {
  const rows = states.map((_, j) =>
    j === k - 1
      ? [...Array<number>(k).fill(1), 1]
      : [...states.map((_, i) => model.a[i][j] - (i === j ? 1 : 0)), 0],
  );
  for (let col = 0; col < k; col++) {
    let pivot = col;
    for (let row = col + 1; row < k; row++) {
      if (Math.abs(rows[row][col]) > Math.abs(rows[pivot][col])) pivot = row;
    }
    [rows[col], rows[pivot]] = [rows[pivot], rows[col]];
    for (let row = col + 1; row < k; row++) {
      const ratio = rows[row][col] / rows[col][col];
      for (let j = col; j <= k; j++) rows[row][j] -= ratio * rows[col][j];
    }
  }
  const phi = Array<number>(k).fill(0);
  for (let i = k - 1; i >= 0; i--) {
    let value = rows[i][k];
    for (let j = i + 1; j < k; j++) value -= rows[i][j] * phi[j];
    phi[i] = value / rows[i][i];
  }
  return phi;
}
function alignment(model: Model) {
  const c = matrix(k);
  for (const record of train) accumulate(c, record.path, viterbi(model, record.obs).path);
  let best: number[] = [];
  let count = -1;
  function visit(permutation: number[]): void {
    if (permutation.length === k) {
      let score = 0;
      for (let j = 0; j < k; j++) score += c[permutation[j]][j];
      if (score > count) {
        count = score;
        best = permutation.slice();
      }
      return;
    }
    for (let i = 0; i < k; i++) if (!permutation.includes(i)) visit([...permutation, i]);
  }
  visit([]);
  return { permutation: best, count };
}
const compositionCounts = Array<number>(m).fill(0);
for (const sequence of unlabeled) for (const c of sequence.obs) if (c >= 0) compositionCounts[c]++;
const inputBlock = [
  'INPUT',
  `SEQUENCES accepted ${unlabeled.length} rejected ${rejected.filter((r) => r.file === 'sequences.txt').length} positions ${z} missing ${missingCount(unlabeled)}`,
  `LABELED train ${train.length} test ${test.length} rejected ${rejected.filter((r) => r.file === 'labeled.txt').length} positions ${trainZ + testZ} missing ${missingCount(labeled)}`,
  ...rejected.map((r) => `REJECT ${r.file} line ${r.line} ${r.name} ${r.reason}`),
  'COMPOSITION ' + symbols.map((c, i) => `${c} ${real(compositionCounts[i] / observed)}`).join(' '),
];
for (const [role, records] of [
  ['TRAIN', train],
  ['TEST', test],
] as const) {
  const stats = runStatistics(records.map((r) => r.path));
  const total = positions([...records]);
  states.forEach((s, i) =>
    inputBlock.push(
      `TRUTH ${role} ${s} occupancy ${real(stats.occupancy[i] / total)} mean_run ${real(stats.mean[i])}`,
    ),
  );
}
const unDecoded = models.map((model) => unobs.map((obs) => decode(model, obs)));
const preferences = Array<number>(4).fill(0);
unlabeled.forEach((_, i) => preferences[maximum(unDecoded.map((d) => d[i].loglik))]++);
const trainingBlock = [
  `TRAINING BAUM_WELCH iterations ${p.iterations} initial_loglik ${real(initialL)} final_loglik ${real(previousL)} violations ${violations} best_heldout_iteration ${bestIteration}`,
  `TRAINING VITERBI_TRAINING iterations ${vtIterations} converged ${converged ? 'yes' : 'no'}`,
  `TRAINING SUPERVISED smoothing ${selected.text}`,
  'PREFERENCE ' + models.map((model, i) => `${model.name} ${preferences[i]}`).join(' '),
];
for (let i = 0; i < models.length; i++) {
  for (let j = i + 1; j < models.length; j++) {
    const count = unlabeled.reduce(
      (sum, _, n) => sum + correct(unDecoded[i][n].viterbi.path, unDecoded[j][n].viterbi.path),
      0,
    );
    trainingBlock.push(`AGREEMENT ${models[i].name} ${models[j].name} ${fraction(count, z)}`);
  }
}
['VITERBI', 'POSTERIOR'].forEach((decoder, d) => {
  const best = maximum(testCorrect.map((counts) => counts[d]));
  trainingBlock.push(
    `BEST ${decoder} ${models[best].name} accuracy ${fraction(testCorrect[best][d], testZ)}`,
  );
});
const modelBlocks = models.map((model, modelIndex) => {
  const decoded = unDecoded[modelIndex];
  const stats = runStatistics(decoded.map((d) => d.viterbi.path));
  const phi = stationary(model);
  const aligned = alignment(model);
  let likelihood = 0;
  let count = 0;
  let length = 0;
  let islands = 0;
  decoded.forEach((d, i) => {
    likelihood += d.loglik;
    for (const segment of segments(d.viterbi.path)) {
      count++;
      length += segment.end - segment.start + 1;
      if (composition(unlabeled[i].obs, segment).island) islands++;
    }
  });
  return [
    `MODEL ${model.name}`,
    `LOGLIK unlabeled ${real(likelihood)} per_symbol ${real(likelihood / observed)} test ${real(totalLoglik(model, testobs))}`,
    `SEGMENTS count ${count} mean_length ${real(count === 0 ? null : length / count)} islands ${islands}`,
    'ALIGNMENT ' +
      states.map((s, i) => `${s}=${states[aligned.permutation[i]]}`).join(' ') +
      ' agreement ' +
      fraction(aligned.count, trainZ),
    ...states.map(
      (s, i) =>
        `STATE ${s} stationary ${real(phi[i])} duration ${real(1 / (1 - model.a[i][i]))} occupancy ${real(stats.occupancy[i] / z)} mean_run ${real(stats.mean[i])}`,
    ),
  ];
});
const blocks = (groups: string[][]) =>
  groups.flatMap((group, i) => (i === 0 ? group : ['', ...group]));
write('trained_model.txt', blocks(models.slice(1).map((model) => modelLines(model, alphabet))));
write('loglik_trace.csv', bwTrace);
write('viterbi_trace.csv', vtTrace);
write('decodings.txt', decodings);
write('segments.csv', segmentLines);
write('samples.txt', samples);
write('evaluation.txt', blocks(evaluationBlocks));
write('report.txt', blocks([inputBlock, trainingBlock, ...modelBlocks]));
