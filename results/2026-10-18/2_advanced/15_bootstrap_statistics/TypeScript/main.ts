import { readDataset } from './dataset.ts';
import type { Dataset, Group, Pair, Settings } from './dataset.ts';
import { Minstd } from './minstd.ts';
import {
  sum,
  sorted,
  mean,
  Md,
  med,
  trim,
  moments,
  sd,
  mad,
  Qn,
  wins,
  mdiff,
  mratio,
  hl,
  sp,
  cd,
  corr,
  drawIndices,
  ordinaryIndices,
  balancedIndices,
  without,
  meanAndSe,
  Phi,
  PhiInv,
} from './resampling.ts';
import { choices, contrast, doubledRanks, tieCounts, divide, anova, kruskal } from './tests.ts';
import { real, pValue, numberList, binNumber, bar, writeLines } from './report.ts';

const GROUP_NAMES = ['mean', 'median', 'trimmed_mean', 'sd'];
const GROUP_FUNCTIONS = [mean, med, trim, sd];
const PAIR_NAMES = ['mean_diff', 'median_ratio', 'hodges_lehmann', 'cohen_d'];
const PAIR_FUNCTIONS = [mdiff, mratio, hl, cd];
const TEST_NAMES = ['mean', 'median', 'ranksum', 'absdev'];
interface BootstrapSummary {
  estimate: number;
  average: number;
  se: number;
  bias: number;
  lo: number;
  hi: number;
  basicLo: number;
  basicHi: number;
  order: number[];
  rankLo: number;
  rankHi: number;
}
interface BootstrapReplicates {
  samples: number[][];
  values: number[][];
  indices: number[][];
}
interface GroupResult extends Group {
  estimates: number[];
  ordinary: BootstrapReplicates;
  summaries: BootstrapSummary[];
  balancedSummaries: BootstrapSummary[];
}
interface PairResult {
  x: GroupResult;
  y: GroupResult;
  estimates: number[];
  values: number[][];
  summaries: BootstrapSummary[];
}
interface TailCounts {
  extreme: number;
  greater: number;
}
interface PermutationResult {
  counts: TailCounts[];
  lines: string[];
}
interface RankedValue {
  value: number;
  rank: number;
}
interface PairedSummary {
  difference: BootstrapSummary;
  correlation: BootstrapSummary;
}

function sampleStatistics(sample: number[]): number[] {
  return GROUP_FUNCTIONS.map((statistic) => statistic(sample));
}
function pairStatistics(x: number[], y: number[]): number[] {
  return PAIR_FUNCTIONS.map((statistic) => statistic(x, y));
}
function pairName(pair: Pair): string {
  return `${pair.x.name}-${pair.y.name}`;
}

function describe(
  kind: string,
  name: string,
  sample: number[],
  lo: number,
  hi: number,
  stems: boolean,
): string[] {
  const order = sorted(sample);
  const n = sample.length;
  const center = mean(sample);
  const moment = moments(sample);
  const winsorized = wins(sample);
  const q1 = Qn(sample, 25);
  const q3 = Qn(sample, 75);
  const outliers: number[] = [];
  const inside: number[] = [];
  sample.forEach((value, i) => {
    if (200 * value < 5 * q1 - 3 * q3 || 200 * value > 5 * q3 - 3 * q1) outliers.push(i + 1);
    else inside.push(value);
  });
  const w1 = Math.min(...inside);
  const w2 = Math.max(...inside);
  const delta = 100 * (hi - lo);
  const position = (value: number): number =>
    Math.floor((120 * (value - 100 * lo) + delta) / (2 * delta));
  const band: string[] = Array(61).fill('.');
  for (let i = position(100 * w1); i <= position(100 * w2); i++) band[i] = '-';
  for (let i = position(q1); i <= position(q3); i++) band[i] = '=';
  band[position(Qn(sample, 50))] = '|';
  for (const i of outliers) band[position(100 * sample[i - 1])] = 'o';
  const lines = [
    `${kind} ${name}`,
    `n ${n}`,
    `mean ${real(center)}`,
    `median ${real(med(sample))}`,
    `trimmed_mean ${real(trim(sample))} trim ${Math.floor(n / 10)}`,
    `winsorized_mean ${real(mean(winsorized))} winsorized_sd ${real(sd(winsorized))}`,
    `sd ${real(moment.sd)}`,
    `se_mean ${real(moment.sd / Math.sqrt(n))}`,
    `cv ${real(moment.sd / center)}`,
    `skewness ${real(moment.m3 / (moment.m2 * Math.sqrt(moment.m2)))}`,
    `kurtosis ${real(moment.m4 / (moment.m2 * moment.m2) - 3)}`,
    `mad ${real(mad(sample))}`,
    `min ${real(order[0] / 100)}`,
    `q1 ${real(q1 / 10000)}`,
    `q3 ${real(q3 / 10000)}`,
    `iqr ${real((q3 - q1) / 10000)}`,
    `max ${real(order[n - 1] / 100)}`,
    `percentiles p05 ${real(Qn(sample, 5) / 10000)} p10 ${real(Qn(sample, 10) / 10000)} p90 ${real(Qn(sample, 90) / 10000)} p95 ${real(Qn(sample, 95) / 10000)}`,
    `whiskers ${real(w1 / 100)} ${real(w2 / 100)}`,
    `outliers ${numberList(outliers)}`,
    `box ${band.join('')}`,
  ];
  if (stems) {
    for (let stem = Math.floor(order[0] / 100); stem <= Math.floor(order[n - 1] / 100); stem++) {
      const leaves = order
        .filter((value) => Math.floor(value / 100) === stem)
        .map((value) => Math.floor((value % 100) / 10))
        .join('');
      lines.push(`stem ${stem}${leaves ? ' ' + leaves : ''}`);
    }
  }
  return lines;
}
function descriptiveLines(data: Dataset): string[] {
  const all = data.groups.flatMap((group) => group.sample);
  const lo = Math.min(...all);
  const hi = Math.max(...all);
  const lines = [`groups ${data.groups.length} observations ${all.length}`];
  for (const group of data.groups) {
    lines.push(...describe('group', group.name, group.sample, lo, hi, true));
  }
  const together = [...data.before, ...data.after];
  const pairedLo = Math.min(...together);
  const pairedHi = Math.max(...together);
  lines.push(
    `paired subjects ${data.before.length}`,
    ...describe('series', 'before', data.before, pairedLo, pairedHi, false),
    ...describe('series', 'after', data.after, pairedLo, pairedHi, false),
    ...describe(
      'series',
      'diff',
      data.differences,
      Math.min(...data.differences),
      Math.max(...data.differences),
      false,
    ),
  );
  return lines;
}
function bootstrapSamples(sample: number[], indices: number[][]): BootstrapReplicates {
  const samples: number[][] = [];
  const values: number[][] = GROUP_NAMES.map(() => []);
  for (const chosen of indices) {
    const replicate = chosen.map((i) => sample[i]);
    const statistics = sampleStatistics(replicate);
    samples.push(replicate);
    for (let s = 0; s < 4; s++) values[s].push(statistics[s]);
  }
  return { samples, values, indices };
}
function bootstrapSummary(
  estimate: number,
  values: number[],
  confidence: number,
): BootstrapSummary {
  const { average, se } = meanAndSe(values);
  const order = sorted(values);
  const rankLo = Math.floor(((values.length + 1) * (100 - confidence)) / 200);
  const rankHi = values.length + 1 - rankLo;
  const lo = order[rankLo - 1];
  const hi = order[rankHi - 1];
  return {
    estimate,
    average,
    se,
    bias: average - estimate,
    lo,
    hi,
    basicLo: 2 * estimate - hi,
    basicHi: 2 * estimate - lo,
    order,
    rankLo,
    rankHi,
  };
}
function bootstrapLines(groups: GroupResult[], pairs: PairResult[]): string[] {
  const lines = ['group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi'];
  function append(name: string, statistic: string, summary: BootstrapSummary): void {
    lines.push(
      [
        name,
        statistic,
        ...[
          summary.estimate,
          summary.se,
          summary.bias,
          summary.lo,
          summary.hi,
          summary.basicLo,
          summary.basicHi,
        ].map(real),
      ].join(','),
    );
  }
  for (const group of groups) {
    for (let s = 0; s < 4; s++) append(group.name, GROUP_NAMES[s], group.summaries[s]);
    for (let s = 0; s < 4; s++) {
      append(group.name, `balanced_${GROUP_NAMES[s]}`, group.balancedSummaries[s]);
    }
  }
  for (const pair of pairs) {
    for (let s = 0; s < 4; s++) append(pairName(pair), PAIR_NAMES[s], pair.summaries[s]);
  }
  return lines;
}
function histogram(
  name: string,
  statistic: string,
  values: number[],
  summary: BootstrapSummary,
  bins: number,
): string[] {
  const lo = summary.order[0];
  const hi = summary.order[summary.order.length - 1];
  const counts: number[] = Array(bins).fill(0);
  for (const value of values) counts[binNumber(value, lo, hi, bins) - 1]++;
  const top = Math.max(...counts);
  const estimateBin =
    summary.estimate < lo || summary.estimate > hi
      ? null
      : binNumber(summary.estimate, lo, hi, bins);
  const lowerBin = binNumber(summary.lo, lo, hi, bins);
  const upperBin = binNumber(summary.hi, lo, hi, bins);
  const lines = [
    `histogram ${name} ${statistic} min ${real(lo)} max ${real(hi)} width ${real((hi - lo) / bins)} top ${top} estimate_bin ${estimateBin ?? 'none'}`,
  ];
  const convergence: string[] = [];
  for (let j = 1; j <= 4; j++) {
    const count = Math.floor((j * values.length) / 4);
    convergence.push(`${count}:${real(meanAndSe(values.slice(0, count)).se)}`);
  }
  lines.push(`convergence ${convergence.join(' ')}`);
  for (let j = 0; j < bins; j++) {
    let line = `bin ${j + 1} ${real(lo + ((hi - lo) * j) / bins)} ${counts[j]}`;
    if (counts[j]) line += ` ${bar(counts[j], top)}`;
    if (j + 1 === lowerBin) line += ' L';
    if (j + 1 === estimateBin) line += ' E';
    if (j + 1 === upperBin) line += ' H';
    lines.push(line);
  }
  return lines;
}
function histogramLines(groups: GroupResult[], pairs: PairResult[], bins: number): string[] {
  const lines: string[] = [];
  for (const group of groups) {
    for (let s = 0; s < 4; s++) {
      lines.push(
        ...histogram(
          group.name,
          GROUP_NAMES[s],
          group.ordinary.values[s],
          group.summaries[s],
          bins,
        ),
      );
    }
  }
  for (const pair of pairs) {
    for (let s = 0; s < 4; s++) {
      lines.push(
        ...histogram(pairName(pair), PAIR_NAMES[s], pair.values[s], pair.summaries[s], bins),
      );
    }
  }
  return lines;
}
function jackknifeSummary(values: number[], estimate: number) {
  const average = sum(values) / values.length;
  let squared = 0;
  for (const value of values) {
    const e = value - average;
    squared += e * e;
  }
  const variance = ((values.length - 1) * squared) / values.length;
  return {
    average,
    bias: (values.length - 1) * (average - estimate),
    variance,
    se: Math.sqrt(variance),
  };
}
function groupJackknife(group: GroupResult, zL: number): string[] {
  const sample = group.sample;
  const n = sample.length;
  const deleted = sample.map((_, i) => sampleStatistics(without(sample, i)));
  const values = GROUP_NAMES.map((_, s) => deleted.map((row) => row[s]));
  const summaries = values.map((column, s) => jackknifeSummary(column, group.estimates[s]));
  const lines = [`group ${group.name} n ${n}`];
  for (let s = 0; s < 4; s++) {
    const jack = summaries[s];
    lines.push(
      `jackknife ${GROUP_NAMES[s]} estimate ${real(group.estimates[s])} average ${real(jack.average)} bias ${real(jack.bias)} se ${real(jack.se)}`,
    );
  }
  for (let s = 0; s < 4; s++) {
    const replicates = group.ordinary.values[s];
    const count = replicates.filter((value) => value < group.estimates[s]).length;
    const z0 = PhiInv(count / replicates.length);
    let v2 = 0;
    let v3 = 0;
    for (const value of values[s]) {
      const u = summaries[s].average - value;
      v2 += u * u;
      v3 += u * u * u;
    }
    const acceleration = v3 / (6 * v2 * Math.sqrt(v2));
    const alpha = (z: number): number => Phi(z0 + (z0 + z) / (1 - acceleration * (z0 + z)));
    const b = replicates.length;
    const first = Math.max(1, Math.min(b, Math.floor((b + 1) * alpha(zL))));
    const second = Math.max(1, Math.min(b, b + 1 - Math.floor((b + 1) * (1 - alpha(-zL)))));
    const order = group.summaries[s].order;
    lines.push(
      `bca ${GROUP_NAMES[s]} below ${count} z0 ${real(z0)} acceleration ${real(acceleration)} ranks ${first} ${second} interval ${real(order[first - 1])} ${real(order[second - 1])}`,
    );
  }
  const missing: number[][] = sample.map(() => []);
  group.ordinary.indices.forEach((indices, r) => {
    const chosen = new Set(indices);
    for (let i = 0; i < n; i++) if (!chosen.has(i)) missing[i].push(r);
  });
  const errors = group.ordinary.values.map((column) =>
    missing.map((indices) => meanAndSe(indices.map((i) => column[i])).se),
  );
  for (let s = 0; s < 4; s++) {
    const summary = jackknifeSummary(errors[s], 0);
    lines.push(
      `after_bootstrap ${GROUP_NAMES[s]} se ${real(group.summaries[s].se)} average ${real(summary.average)} se_of_se ${real(summary.se)}`,
    );
  }
  const counts = missing.map((indices) => indices.length);
  const total = sum(sample);
  lines.push(`without min ${Math.min(...counts)} max ${Math.max(...counts)}`);
  const influenceOrder = sample
    .map((_, i) => i)
    .sort((a, b) => Math.abs(n * sample[b] - total) - Math.abs(n * sample[a] - total) || a - b);
  influenceOrder.slice(0, 5).forEach((i, rank) => {
    const deviations = sorted(
      missing[i].map((r) => group.ordinary.values[0][r] - group.estimates[0]),
    );
    const quantile = (p: number): number => deviations[Math.floor((p * counts[i] + 99) / 100) - 1];
    const influence = (n - 1) * (summaries[0].average - values[0][i]);
    lines.push(
      `influence ${rank + 1} obs ${i + 1} value ${real(sample[i] / 100)} l ${real(influence)} without ${counts[i]} se ${real(errors[0][i])} q05 ${real(quantile(5))} q50 ${real(quantile(50))} q95 ${real(quantile(95))}`,
    );
  });
  return lines;
}
function pairJackknife(pair: PairResult): string[] {
  const x = pair.x.sample;
  const y = pair.y.sample;
  const deletedX = x.map((_, i) => pairStatistics(without(x, i), y));
  const deletedY = y.map((_, i) => pairStatistics(x, without(y, i)));
  const lines: string[] = [];
  for (let s = 0; s < 4; s++) {
    let bias = 0;
    let variance = 0;
    for (const deleted of [deletedX, deletedY]) {
      const part = jackknifeSummary(
        deleted.map((row) => row[s]),
        pair.estimates[s],
      );
      bias += part.bias;
      variance += part.variance;
    }
    lines.push(
      `pair ${pairName(pair)} ${PAIR_NAMES[s]} estimate ${real(pair.estimates[s])} bias ${real(bias)} se ${real(Math.sqrt(variance))}`,
    );
  }
  return lines;
}
function rankedSample(sample: number[]): RankedValue[] {
  const ranks = doubledRanks(sample);
  return sample.map((value, i) => ({ value, rank: ranks[i] }));
}
function permutationStatistics(items: RankedValue[], firstSize: number) {
  const x = items.slice(0, firstSize).map((item) => item.value);
  const y = items.slice(firstSize).map((item) => item.value);
  const mx = Md(x);
  const my = Md(y);
  const ax = sum(x.map((value) => Math.abs(2 * value - mx)));
  const ay = sum(y.map((value) => Math.abs(2 * value - my)));
  const rankSum = sum(items.slice(0, firstSize).map((item) => item.rank));
  return {
    values: [
      contrast(x, y),
      mx - my,
      rankSum - firstSize * (items.length + 1),
      y.length * ax - x.length * ay,
    ],
    w: rankSum / 2,
    u: (rankSum - firstSize * (firstSize + 1)) / 2,
  };
}
function countComparisons(observed: number[], trial: number[], counts: TailCounts[]): void {
  for (let s = 0; s < observed.length; s++) {
    if (Math.abs(trial[s]) >= Math.abs(observed[s])) counts[s].extreme++;
    if (trial[s] >= observed[s]) counts[s].greater++;
  }
}
function resultText(count: TailCounts, trials: number, correction = 1): string {
  return `extreme ${count.extreme} greater ${count.greater} p_two ${pValue(count.extreme + correction, trials + correction)} p_greater ${pValue(count.greater + correction, trials + correction)}`;
}
function twoGroupPermutation(pair: Pair, settings: Settings, rng: Minstd): PermutationResult {
  const x = pair.x.sample;
  const y = pair.y.sample;
  const combined = rankedSample([...x, ...y]);
  const observed = permutationStatistics(combined, x.length);
  const counts = TEST_NAMES.map(() => ({ extreme: 0, greater: 0 }));
  for (let r = 0; r < settings.permutations; r++) {
    const trial = permutationStatistics(rng.shuffle(combined.slice()), x.length);
    countComparisons(observed.values, trial.values, counts);
  }
  return {
    counts,
    lines: [
      `mean diff ${real(mdiff(x, y))} ${resultText(counts[0], settings.permutations)}`,
      `median diff ${real(observed.values[1] / 200)} ${resultText(counts[1], settings.permutations)}`,
      `ranksum w ${real(observed.w)} u ${real(observed.u)} ${resultText(counts[2], settings.permutations)}`,
      `absdev diff ${real(observed.values[3] / (200 * x.length * y.length))} ${resultText(counts[3], settings.permutations)}`,
    ],
  };
}
function powerSimulation(pair: Pair, settings: Settings, rng: Minstd): string {
  const x = pair.x.sample;
  const y = pair.y.sample;
  let rejections = 0;
  for (let e = 0; e < settings.simulations; e++) {
    const first = drawIndices(x.length, rng).map((i) => x[i]);
    const second = drawIndices(y.length, rng).map((i) => y[i]);
    const combined = [...first, ...second];
    const observed = Math.abs(contrast(first, second));
    let extreme = 0;
    for (let r = 0; r < settings.innerPermutations; r++) {
      const shuffled = rng.shuffle(combined.slice());
      if (Math.abs(contrast(shuffled.slice(0, x.length), shuffled.slice(x.length))) >= observed) {
        extreme++;
      }
    }
    if (100 * (extreme + 1) <= (100 - settings.confidence) * (settings.innerPermutations + 1)) {
      rejections++;
    }
  }
  const power = rejections / settings.simulations;
  return `power sims ${settings.simulations} perms ${settings.innerPermutations} rejections ${rejections} power ${real(power)} se ${real(Math.sqrt((power * (1 - power)) / settings.simulations))}`;
}
function exactPermutation(pair: Pair, settings: Settings): string[] {
  const q = settings.pilot;
  const x = pair.x.sample.slice(0, q);
  const y = pair.y.sample.slice(0, q);
  const combined = rankedSample([...x, ...y]);
  const original = permutationStatistics(combined, q);
  const observed = [original.values[0], original.values[2]];
  const counts = observed.map(() => ({ extreme: 0, greater: 0 }));
  const total = sum(combined.map((item) => item.value));
  const absoluteCounts = new Map<number, number>();
  let splits = 0;
  for (const positions of choices(2 * q, q)) {
    let firstSum = 0;
    let firstRanks = 0;
    for (const i of positions) {
      firstSum += combined[i].value;
      firstRanks += combined[i].rank;
    }
    const statistic = q * firstSum - q * (total - firstSum);
    countComparisons(observed, [statistic, firstRanks - q * (2 * q + 1)], counts);
    const absolute = Math.abs(statistic);
    absoluteCounts.set(absolute, (absoluteCounts.get(absolute) ?? 0) + 1);
    splits++;
  }
  let attained = 0;
  let cumulative = 0;
  let critical: number | null = null;
  for (const value of [...absoluteCounts.keys()].sort((a, b) => b - a)) {
    cumulative += absoluteCounts.get(value)!;
    if (100 * cumulative > (100 - settings.confidence) * splits) break;
    critical = value / (100 * q * q);
    attained = cumulative;
  }
  return [
    `exact size ${q} splits ${splits}`,
    `mean diff ${real(mdiff(x, y))} ${resultText(counts[0], splits, 0)}`,
    `ranksum w ${real(original.w)} u ${real(original.u)} ${resultText(counts[1], splits, 0)}`,
    critical === null
      ? 'critical diff none attained none'
      : `critical diff ${real(critical)} attained ${pValue(attained, splits)}`,
  ];
}
function studentizedLines(pair: PairResult, settings: Settings): string[] {
  const x = pair.x.sample;
  const y = pair.y.sample;
  const k = x.length;
  const m = y.length;
  const sx = sd(x);
  const sy = sd(y);
  const vx = (sx * sx) / k;
  const vy = (sy * sy) / m;
  const se0 = Math.sqrt(vx + vy);
  const estimate = pair.estimates[0];
  const t = estimate / se0;
  const replicates: number[] = [];
  let extreme = 0;
  for (let r = 0; r < settings.bootstrap; r++) {
    const sx = pair.x.ordinary.values[3][r];
    const sy = pair.y.ordinary.values[3][r];
    const value = (pair.values[0][r] - estimate) / Math.sqrt((sx * sx) / k + (sy * sy) / m);
    if (Math.abs(value) >= Math.abs(t)) extreme++;
    replicates.push(value);
  }
  const order = sorted(replicates);
  const lo = estimate - order[pair.summaries[0].rankHi - 1] * se0;
  const hi = estimate - order[pair.summaries[0].rankLo - 1] * se0;
  const df = ((vx + vy) * (vx + vy)) / ((vx * vx) / (k - 1) + (vy * vy) / (m - 1));
  const pooled = sp(x, y);
  const d = pair.estimates[3];
  const g = d * (1 - 3 / (4 * (k + m - 2) - 1));
  let greater = 0;
  let equal = 0;
  for (const first of x) {
    for (const second of y) {
      if (first > second) greater++;
      if (first === second) equal++;
    }
  }
  const cles = (2 * greater + equal) / (2 * k * m);
  return [
    `bootstrap_t t ${real(t)} df ${real(df)} extreme ${extreme} p ${pValue(extreme + 1, settings.bootstrap + 1)} interval ${real(lo)} ${real(hi)}`,
    `effect pooled_sd ${real(pooled)} cohen_d ${real(d)} hedges_g ${real(g)} cles ${real(cles)}`,
  ];
}
function holmLines(
  pairs: PairResult[],
  results: PermutationResult[],
  settings: Settings,
): string[] {
  const lines: string[] = [];
  for (let s = 0; s < 4; s++) {
    const order = pairs
      .map((pair, i) => ({ pair, i, extreme: results[i].counts[s].extreme }))
      .sort((a, b) => a.extreme - b.extreme || a.i - b.i);
    let adjusted = 0;
    order.forEach(({ pair, extreme }, i) => {
      adjusted = Math.max(
        adjusted,
        Math.min(settings.permutations + 1, (order.length - i) * (extreme + 1)),
      );
      const decision =
        100 * adjusted <= (100 - settings.confidence) * (settings.permutations + 1)
          ? 'reject'
          : 'retain';
      lines.push(
        `holm ${TEST_NAMES[s]} rank ${i + 1} ${pair.x.name} ${pair.y.name} p ${pValue(extreme + 1, settings.permutations + 1)} adjusted ${pValue(adjusted, settings.permutations + 1)} ${decision}`,
      );
    });
  }
  return lines;
}
function intervalText(summary: BootstrapSummary): string {
  return `se ${real(summary.se)} bias ${real(summary.bias)} percentile ${real(summary.lo)} ${real(summary.hi)} basic ${real(summary.basicLo)} ${real(summary.basicHi)}`;
}
function pairedLines(data: Dataset, paired: PairedSummary, zL: number, rng: Minstd): string[] {
  const d = data.differences;
  const m = d.length;
  const differenceMean = mean(d);
  const differenceSd = sd(d);
  const positive = d.filter((value) => value > 0).length;
  const negative = d.filter((value) => value < 0).length;
  const zero = d.filter((value) => value === 0).length;
  const correlation = paired.correlation.estimate;
  const z = 0.5 * Math.log((1 + correlation) / (1 - correlation));
  const halfWidth = -zL / Math.sqrt(m - 3);
  const tanh = (value: number): number => {
    const exponential = Math.exp(2 * value);
    return (exponential - 1) / (exponential + 1);
  };
  const lines = [
    `paired subjects ${m} positive ${positive} negative ${negative} zero ${zero}`,
    `paired before ${real(mean(data.before))} after ${real(mean(data.after))} diff ${real(differenceMean)} sd_diff ${real(differenceSd)} t ${real(differenceMean / (differenceSd / Math.sqrt(m)))} dz ${real(differenceMean / differenceSd)}`,
    `paired_bootstrap ${intervalText(paired.difference)}`,
    `correlation r ${real(correlation)} ${intervalText(paired.correlation)} fisher ${real(tanh(z - halfWidth))} ${real(tanh(z + halfWidth))}`,
  ];
  const ranks = doubledRanks(d.filter((value) => value !== 0).map(Math.abs));
  let position = 0;
  let positiveRanks = 0;
  const signedRanks = d.map((value) => {
    if (value === 0) return 0;
    const rank = ranks[position++];
    if (value > 0) positiveRanks += rank;
    return value > 0 ? rank : -rank;
  });
  const observed = [sum(d), sum(signedRanks)];
  const counts = observed.map(() => ({ extreme: 0, greater: 0 }));
  for (let r = 0; r < data.settings.permutations; r++) {
    let total = 0;
    let rankTotal = 0;
    for (let i = 0; i < m; i++) {
      const sign = rng.draw() % 2 === 1 ? -1 : 1;
      total += sign * d[i];
      rankTotal += sign * signedRanks[i];
    }
    countComparisons(observed, [total, rankTotal], counts);
  }
  lines.push(
    `signflip flips ${data.settings.permutations}`,
    `mean diff ${real(differenceMean)} ${resultText(counts[0], data.settings.permutations)}`,
    `signedrank w_plus ${real(positiveRanks / 2)} ${resultText(counts[1], data.settings.permutations)}`,
  );
  return lines;
}
function anovaLines(groups: GroupResult[], settings: Settings, rng: Minstd): string[] {
  const samples = groups.map((group) => group.sample);
  const sizes = samples.map((sample) => sample.length);
  const original = anova(samples);
  const n = original.count;
  const g = groups.length;
  const msw = original.ssw / (n - g);
  const eta = original.ssb / (original.ssb + original.ssw);
  const omega = (original.ssb - (g - 1) * msw) / (original.ssb + original.ssw + msw);
  const etaReplicates: number[] = [];
  for (let r = 0; r < settings.bootstrap; r++) {
    const result = anova(groups.map((group) => group.ordinary.samples[r]));
    etaReplicates.push(result.ssb / (result.ssb + result.ssw));
  }
  const etaSummary = bootstrapSummary(eta, etaReplicates, settings.confidence);
  const weights = samples.map((sample) => {
    const s = sd(sample);
    return sample.length / (s * s);
  });
  const weightTotal = sum(weights);
  let weightedMean = 0;
  for (let i = 0; i < g; i++) weightedMean += weights[i] * original.means[i];
  weightedMean /= weightTotal;
  let aw = 0;
  let lambda = 0;
  for (let i = 0; i < g; i++) {
    const difference = original.means[i] - weightedMean;
    const part = 1 - weights[i] / weightTotal;
    aw += weights[i] * (difference * difference);
    lambda += (part * part) / (sizes[i] - 1);
  }
  aw /= g - 1;
  const welch = aw / (1 + (2 * (g - 2) * lambda) / (g * g - 1));
  const df2 = (g * g - 1) / (3 * lambda);
  const combinedValues = samples.flat();
  const combined = rankedSample(combinedValues);
  const ties = tieCounts(combinedValues);
  const correction = 1 - ties.correction / (n * n * n - n);
  const h = kruskal(
    divide(
      combined.map((item) => item.rank),
      sizes,
    ),
    correction,
  );
  const lines = [
    `anova groups ${g} observations ${n} ssb ${real(original.ssb)} ssw ${real(original.ssw)} df ${g - 1} ${n - g} f ${real(original.f)} eta_squared ${real(eta)} omega_squared ${real(omega)}`,
    `eta_bootstrap ${intervalText(etaSummary)}`,
    `welch f ${real(welch)} df ${g - 1} ${real(df2)}`,
    `kruskal h ${real(h)} tie_groups ${ties.groups}`,
  ];
  interface Comparison {
    first: number;
    second: number;
    numerator: number;
    denominator: number;
    extreme: number;
    maximum: number;
  }
  const totals = samples.map(sum);
  const pairs: Comparison[] = [];
  for (let i = 0; i < g; i++) {
    for (let j = i + 1; j < g; j++) {
      pairs.push({
        first: i,
        second: j,
        numerator: Math.abs(sizes[j] * totals[i] - sizes[i] * totals[j]),
        denominator: sizes[i] * sizes[j],
        extreme: 0,
        maximum: 0,
      });
    }
  }
  let fExtreme = 0;
  let hExtreme = 0;
  for (let r = 0; r < settings.permutations; r++) {
    const divided = divide(rng.shuffle(combined.slice()), sizes);
    const trialSamples = divided.map((items) => items.map((item) => item.value));
    const trial = anova(trialSamples);
    const trialH = kruskal(
      divided.map((items) => items.map((item) => item.rank)),
      correction,
    );
    if (trial.f >= original.f - 0.000000001 * original.f) fExtreme++;
    if (trialH >= h - 0.000000001 * h) hExtreme++;
    const trialTotals = trialSamples.map(sum);
    const deltas = pairs.map((pair) => ({
      numerator: Math.abs(
        sizes[pair.second] * trialTotals[pair.first] - sizes[pair.first] * trialTotals[pair.second],
      ),
      denominator: pair.denominator,
    }));
    let maximum = deltas[0];
    for (const delta of deltas) {
      if (delta.numerator * maximum.denominator > maximum.numerator * delta.denominator) {
        maximum = delta;
      }
    }
    pairs.forEach((pair, i) => {
      const delta = deltas[i];
      if (delta.numerator * pair.denominator >= pair.numerator * delta.denominator) pair.extreme++;
      if (maximum.numerator * pair.denominator >= pair.numerator * maximum.denominator) {
        pair.maximum++;
      }
    });
  }
  lines.push(
    `anova_permutation perms ${settings.permutations} f_extreme ${fExtreme} f_p ${pValue(fExtreme + 1, settings.permutations + 1)} h_extreme ${hExtreme} h_p ${pValue(hExtreme + 1, settings.permutations + 1)}`,
  );
  for (const pair of pairs) {
    lines.push(
      `pairwise ${groups[pair.first].name} ${groups[pair.second].name} diff ${real(mdiff(samples[pair.first], samples[pair.second]))} extreme ${pair.extreme} p ${pValue(pair.extreme + 1, settings.permutations + 1)} maxt ${pair.maximum} adjusted ${pValue(pair.maximum + 1, settings.permutations + 1)}`,
    );
  }
  return lines;
}
function main(): void {
  const data = readDataset();
  const settings = data.settings;
  const rng = new Minstd(settings.seed);
  const b = settings.bootstrap;
  const zL = PhiInv((100 - settings.confidence) / 200);
  // Keep one random stream: all ordinary groups, all balanced groups, then subjects.
  const ordinary = data.groups.map((group) => {
    const estimates = sampleStatistics(group.sample);
    const replicates = bootstrapSamples(group.sample, ordinaryIndices(group.sample.length, b, rng));
    return {
      ...group,
      estimates,
      ordinary: replicates,
      summaries: replicates.values.map((values, s) =>
        bootstrapSummary(estimates[s], values, settings.confidence),
      ),
    };
  });
  const groups: GroupResult[] = ordinary.map((group) => {
    const balanced = bootstrapSamples(group.sample, balancedIndices(group.sample.length, b, rng));
    return {
      ...group,
      balancedSummaries: balanced.values.map((values, s) =>
        bootstrapSummary(group.estimates[s], values, settings.confidence),
      ),
    };
  });
  const groupByName = new Map(groups.map((group) => [group.name, group]));
  const pairs: PairResult[] = data.pairs.map((pair) => {
    const x = groupByName.get(pair.x.name)!;
    const y = groupByName.get(pair.y.name)!;
    const estimates = pairStatistics(x.sample, y.sample);
    const values: number[][] = PAIR_NAMES.map(() => []);
    for (let r = 0; r < b; r++) {
      const statistics = pairStatistics(x.ordinary.samples[r], y.ordinary.samples[r]);
      for (let s = 0; s < 4; s++) values[s].push(statistics[s]);
    }
    return {
      x,
      y,
      estimates,
      values,
      summaries: values.map((column, s) =>
        bootstrapSummary(estimates[s], column, settings.confidence),
      ),
    };
  });
  const differences: number[] = [];
  const correlations: number[] = [];
  for (let r = 0; r < b; r++) {
    const indices = drawIndices(data.before.length, rng);
    differences.push(mean(indices.map((i) => data.differences[i])));
    correlations.push(
      corr(
        indices.map((i) => data.before[i]),
        indices.map((i) => data.after[i]),
      ),
    );
  }
  const paired: PairedSummary = {
    difference: bootstrapSummary(mean(data.differences), differences, settings.confidence),
    correlation: bootstrapSummary(corr(data.before, data.after), correlations, settings.confidence),
  };
  const jackknife: string[] = [];
  for (const group of groups) jackknife.push(...groupJackknife(group, zL));
  for (const pair of pairs) jackknife.push(...pairJackknife(pair));
  const tests: string[] = [];
  const permutationResults: PermutationResult[] = [];
  for (const pair of pairs) {
    const permutation = twoGroupPermutation(pair, settings, rng);
    permutationResults.push(permutation);
    const power = powerSimulation(pair, settings, rng);
    tests.push(
      `compare ${pair.x.name} ${pair.y.name}`,
      `permutation n ${pair.x.sample.length} ${pair.y.sample.length} perms ${settings.permutations}`,
      ...permutation.lines,
      power,
      ...exactPermutation(pair, settings),
      ...studentizedLines(pair, settings),
    );
  }
  tests.push(
    ...holmLines(pairs, permutationResults, settings),
    ...pairedLines(data, paired, zL, rng),
    ...anovaLines(groups, settings, rng),
  );
  writeLines('descriptives.txt', descriptiveLines(data));
  writeLines('bootstrap.csv', bootstrapLines(groups, pairs));
  writeLines('jackknife.txt', jackknife);
  writeLines('tests.txt', tests);
  writeLines('histograms.txt', histogramLines(groups, pairs, settings.bins));
}
main();
