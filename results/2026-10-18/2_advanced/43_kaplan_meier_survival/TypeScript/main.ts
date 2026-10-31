import { mkdirSync, writeFileSync } from 'node:fs';
import { fitCox } from './cox.ts';
import { readDataset, type Subject, type Variable } from './dataset.ts';
import { atRisk, kaplanMeier, lifeTable, rowAt } from './estimators.ts';
import { stratified, weightedTest, weights, type WeightedTest } from './group_tests.ts';
import { inverse, pValue, solve, z95 } from './numerics.ts';
import { plot } from './plot.ts';

const { subjects, params } = readDataset();
const groups = params.groups;
const total = subjects.length;
const sum = (values: number[]) => values.reduce((a, b) => a + b, 0);
function f(value: number | undefined, digits = 4): string {
  if (value === undefined) return 'NA';
  const text = value.toFixed(digits);
  return +text === 0 ? (0).toFixed(digits) : text;
}
const day = (value: number | undefined) => (value === undefined ? 'NA' : String(value));
const eventCount = (collection: Subject[]) => collection.filter((s) => s.event === 1).length;
const collections = [...groups, 'all'].map((name) => {
  const members = name === 'all' ? subjects : subjects.filter((s) => s.group === name);
  const rows = kaplanMeier(members);
  const life = lifeTable(members, params.lifeWidth, params.lifeCount);
  const events = eventCount(members);
  const personDays = sum(members.map((s) => s.time));
  const rate = (1000 * events) / personDays;
  const eta = z95 / Math.sqrt(events);
  const reverse = kaplanMeier(members.map((s) => ({ ...s, event: 1 - s.event })));
  const followupMedian = reverse.find((row) => row.survival <= 0.5)?.time;
  const lifeIndex = life.findIndex((row) => row.survival <= 0.5);
  let lifeMedian: number | undefined;
  if (lifeIndex >= 0) {
    const previous = lifeIndex ? life[lifeIndex - 1].survival : 1;
    lifeMedian =
      life[lifeIndex].start +
      (params.lifeWidth * (previous - 0.5)) / (previous - life[lifeIndex].survival);
  }
  const percentiles = [0.75, 0.5, 0.25].map((q) => ({
    time: rows.find((row) => row.survival <= q)?.time,
    lower: rows.find((row) => (row.survival === 0 ? 0 : (row.lower ?? 1)) <= q)?.time,
    upper: rows.find((row) => (row.survival === 0 ? 0 : (row.upper ?? 1)) <= q)?.time,
  }));
  const beforeTau = rows.filter((row) => row.time <= params.tau);
  const boundaries = [0, ...beforeTau.map((row) => row.time), params.tau];
  const rectangles = boundaries
    .slice(0, -1)
    .map((time, i) => (i ? beforeTau[i - 1].survival : 1) * (boundaries[i + 1] - time));
  const remaining = Array<number>(rectangles.length).fill(0);
  for (let i = rectangles.length - 1; i >= 0; i--) {
    remaining[i] = rectangles[i] + (i + 1 < rectangles.length ? remaining[i + 1] : 0);
  }
  let variance = 0;
  beforeTau.forEach((row, i) => {
    variance =
      variance +
      remaining[i + 1] * remaining[i + 1] * (row.events / (row.risk * (row.risk - row.events)));
  });
  const rmst = remaining[0];
  const rmstSe = Math.sqrt(variance);
  return {
    name,
    subjects: members,
    rows,
    life,
    events,
    personDays,
    rate,
    rateLower: Math.exp(Math.log(rate) - eta),
    rateUpper: Math.exp(Math.log(rate) + eta),
    maximum: Math.max(...members.map((s) => s.time)),
    followupMedian,
    lifeMedian,
    percentiles,
    rmst,
    rmstSe,
  };
});
const groupCollections = collections.slice(0, groups.length);
const control = groupCollections[0];
const kmBlocks = collections.map((c) => {
  const lines = [
    `group ${c.name} subjects ${c.subjects.length} events ${c.events} censored ${c.subjects.length - c.events} max_time ${c.maximum}`,
    `person_days ${c.personDays} rate ${f(c.rate)} lower ${f(c.rateLower)} upper ${f(c.rateUpper)}`,
    `followup_median ${day(c.followupMedian)}`,
    `life_table_median ${f(c.lifeMedian)}`,
    ...c.percentiles.map(
      (p, i) =>
        `percentile ${(i + 1) * 25} time ${day(p.time)} lower ${day(p.lower)} upper ${day(p.upper)}`,
    ),
    `rmst tau ${params.tau} estimate ${f(c.rmst)} se ${f(c.rmstSe)} lower ${f(c.rmst - z95 * c.rmstSe)} upper ${f(c.rmst + z95 * c.rmstSe)}`,
  ];
  for (const time of params.reportTimes) {
    const row = rowAt(c.rows, time);
    lines.push(
      `at ${time} at_risk ${atRisk(c.subjects, time)} events ${c.subjects.filter((s) => s.time <= time && s.event === 1).length} survival ${f(row.survival)} std_err ${f(row.se)} lower ${f(row.lower)} upper ${f(row.upper)} cum_hazard ${f(row.hazard)} hazard_se ${f(row.hazardSe)}`,
    );
  }
  lines.push(
    [
      'time',
      'at_risk',
      'events',
      'censored',
      'survival',
      'std_err',
      'lower',
      'upper',
      'cum_haz',
      'haz_se',
    ]
      .map((value) => value.padStart(9))
      .join(''),
  );
  for (const row of c.rows) {
    lines.push(
      [
        String(row.time),
        String(row.risk),
        String(row.events),
        String(row.censored),
        f(row.survival),
        f(row.se),
        f(row.lower),
        f(row.upper),
        f(row.hazard),
        f(row.hazardSe),
      ]
        .map((value) => value.padStart(9))
        .join(''),
    );
  }
  return lines;
});
const lifeLines = [
  'group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard',
  ...collections.flatMap((c) =>
    c.life.map(
      (row) =>
        `${c.name},${row.start}-${row.end},${row.risk},${row.events},${row.censored},${f(row.exposed, 1)},${f(row.q)},${f(row.survival)},${f(row.se)},${f(row.hazard)}`,
    ),
  ),
];
const baseline = ['baseline'];
for (const c of collections) {
  const ages = c.subjects.map((s) => s.age);
  const mean = sum(ages) / ages.length;
  const sd = Math.sqrt(sum(ages.map((age) => (age - mean) * (age - mean))) / (ages.length - 1));
  const sorted = [...ages].sort((a, b) => a - b);
  const median =
    (sorted[Math.floor((ages.length - 1) / 2)] + sorted[Math.floor(ages.length / 2)]) / 2;
  baseline.push(
    `  group ${c.name} subjects ${ages.length} age_mean ${f(mean)} age_sd ${f(sd)} age_median ${f(median, 1)} male ${c.subjects.filter((s) => s.sex === 'M').length} stage ${[1, 2, 3, 4].map((stage) => c.subjects.filter((s) => s.stage === stage).length).join(' ')}`,
  );
}
const ageOrder = [...subjects].sort((a, b) => a.age - b.age || a.id - b.id);
const ranks = new Map<number, number>();
let ties = 0;
for (let start = 0; start < ageOrder.length;) {
  let end = start + 1;
  while (end < ageOrder.length && ageOrder[end].age === ageOrder[start].age) end++;
  const size = end - start;
  const rank = (start + 1 + end) / 2;
  ties += size * size * size - size;
  for (let i = start; i < end; i++) ranks.set(ageOrder[i].id, rank);
  start = end;
}
const rankSums = groupCollections.map((c) => sum(c.subjects.map((s) => ranks.get(s.id)!)));
let kwSum = 0;
groups.forEach((_, g) => {
  kwSum = kwSum + (rankSums[g] * rankSums[g]) / groupCollections[g].subjects.length;
});
const w0 = (12 * kwSum) / (total * (total + 1)) - 3 * (total + 1);
const kw = w0 / (1 - ties / (total * total * total - total));
baseline.push(
  `  age kruskal_wallis chisq ${f(kw)} df ${groups.length - 1} p ${f(pValue(kw, groups.length - 1))}`,
);
function levels(variable: Variable): (string | number)[] {
  return variable === 'sex'
    ? [...new Set(subjects.map((s) => s.sex))].sort()
    : [...new Set(subjects.map((s) => s.stage))].sort((a, b) => a - b);
}
for (const variable of ['sex', 'stage'] as const) {
  const values = levels(variable);
  let chi2 = 0;
  for (const c of groupCollections) {
    for (const value of values) {
      const observed = c.subjects.filter((s) => s[variable] === value).length;
      const column = subjects.filter((s) => s[variable] === value).length;
      const expected = (c.subjects.length * column) / total;
      chi2 = chi2 + ((observed - expected) * (observed - expected)) / expected;
    }
  }
  const df = (groups.length - 1) * (values.length - 1);
  baseline.push(`  ${variable} chisq ${f(chi2)} df ${df} p ${f(pValue(chi2, df))}`);
}
const groupLines = (test: WeightedTest, names = groups) =>
  names.map(
    (name, h) =>
      `  group ${name} events ${test.events[h]} observed ${f(test.observed[h])} expected ${f(test.expected[h])} o_minus_e ${f(test.observed[h] - test.expected[h])} variance ${f(test.covariance[h][h])}`,
  );
const overallTests = weights.map((weight) => weightedTest(subjects, groups, weight, total));
const overall: string[] = [];
overallTests.forEach((test, i) =>
  overall.push(
    `test ${weights[i]} chisq ${f(test.chi2)} df ${test.df} p ${f(test.p)}`,
    ...groupLines(test),
  ),
);
const logrank = overallTests[0];
let trendU = 0;
let trendV = 0;
for (let g = 0; g < groups.length; g++) {
  trendU = trendU + (g + 1) * (logrank.observed[g] - logrank.expected[g]);
  let inner = 0;
  for (let h = 0; h < groups.length; h++) {
    inner = inner + (g + 1) * (h + 1) * logrank.covariance[g][h];
  }
  trendV = trendV + inner;
}
const trendChi2 = (trendU * trendU) / trendV;
overall.push(`test logrank_trend chisq ${f(trendChi2)} df 1 p ${f(pValue(trendChi2, 1))}`);
const stratifiedLines: string[] = [];
const strata = levels(params.strata).map((value) => ({
  value,
  members: subjects.filter((s) => s[params.strata] === value),
}));
for (const weight of weights) {
  const tests = strata.map((stratum) => weightedTest(stratum.members, groups, weight, total));
  const combined = stratified(tests);
  stratifiedLines.push(
    `stratified ${weight} by ${params.strata} chisq ${f(combined.chi2)} df ${combined.df} p ${f(combined.p)}`,
  );
  strata.forEach((stratum, i) =>
    stratifiedLines.push(
      `  stratum ${stratum.value} subjects ${stratum.members.length} events ${eventCount(stratum.members)} chisq ${f(tests[i].chi2)} p ${f(tests[i].p)}`,
    ),
  );
  stratifiedLines.push(...groupLines(combined));
}
const landmarkMembers = subjects.filter((s) => s.time > params.landmark);
const landmarkTest = weightedTest(landmarkMembers, groups, 'logrank', total);
const landmark = [
  `landmark ${params.landmark} subjects ${landmarkMembers.length} chisq ${f(landmarkTest.chi2)} df ${landmarkTest.df} p ${f(landmarkTest.p)}`,
  ...groupLines(landmarkTest),
];
function twoGroup(members: Subject[], a: string, b: string) {
  const test = weightedTest(members, [a, b], 'logrank', total);
  const hr = test.observed[1] / test.expected[1] / (test.observed[0] / test.expected[0]);
  const phi = 1 / test.expected[0] + 1 / test.expected[1];
  const logHr = Math.log(hr);
  const se = Math.sqrt(phi);
  return {
    test,
    hr,
    phi,
    logHr,
    lower: Math.exp(logHr - z95 * se),
    upper: Math.exp(logHr + z95 * se),
  };
}
const pairs: { a: string; b: string; comparison: ReturnType<typeof twoGroup>; holm: number }[] = [];
for (let a = 0; a < groups.length; a++) {
  for (let b = a + 1; b < groups.length; b++) {
    pairs.push({
      a: groups[a],
      b: groups[b],
      comparison: twoGroup(
        subjects.filter((s) => s.group === groups[a] || s.group === groups[b]),
        groups[a],
        groups[b],
      ),
      holm: 0,
    });
  }
}
let previousHolm = 0;
[...pairs]
  .sort((a, b) => a.comparison.test.p - b.comparison.test.p)
  .forEach((pair, i) => {
    previousHolm = Math.max(previousHolm, Math.min(1, (pairs.length - i) * pair.comparison.test.p));
    pair.holm = previousHolm;
  });
const pairwise = [
  'pairwise logrank adjust holm',
  ...pairs.map(
    ({ a, b, comparison: c, holm }) =>
      `  ${a} ${b} chisq ${f(c.test.chi2)} p ${f(c.test.p)} p_holm ${f(holm)} hr ${f(c.hr)} lower ${f(c.lower)} upper ${f(c.upper)}`,
  ),
];
const subgroups = [`subgroups reference ${groups[0]}`];
for (const variable of params.subgroups) {
  for (const group of groups.slice(1)) {
    const comparisons = levels(variable).map((value) => {
      const members = subjects.filter(
        (s) => s[variable] === value && (s.group === groups[0] || s.group === group),
      );
      const c = twoGroup(members, groups[0], group);
      subgroups.push(
        `  ${variable} ${value} ${group} subjects ${members.length} events ${eventCount(members)} hr ${f(c.hr)} lower ${f(c.lower)} upper ${f(c.upper)} p ${f(c.test.p)}`,
      );
      return c;
    });
    let weightSum = 0;
    let weightedLog = 0;
    for (const c of comparisons) {
      const weight = 1 / c.phi;
      weightSum += weight;
      weightedLog += weight * c.logHr;
    }
    const mean = weightedLog / weightSum;
    let chi2 = 0;
    for (const c of comparisons) chi2 = chi2 + (1 / c.phi) * (c.logHr - mean) * (c.logHr - mean);
    subgroups.push(
      `  ${variable} ${group} heterogeneity chisq ${f(chi2)} df ${comparisons.length - 1} p ${f(pValue(chi2, comparisons.length - 1))}`,
    );
  }
}
function differenceText(delta: number, se: number): string {
  const statistic = delta / se;
  return `difference ${f(delta)} se ${f(se)} lower ${f(delta - z95 * se)} upper ${f(delta + z95 * se)} z ${f(statistic)} p ${f(pValue(statistic * statistic, 1))}`;
}
const rmstDifferences = [
  `rmst_difference tau ${params.tau} reference ${groups[0]}`,
  ...groupCollections
    .slice(1)
    .map(
      (c) =>
        `  ${c.name} ${differenceText(c.rmst - control.rmst, Math.sqrt(c.rmstSe * c.rmstSe + control.rmstSe * control.rmstSe))}`,
    ),
];
const rateRatios = [
  `rate_ratio reference ${groups[0]}`,
  ...groupCollections.slice(1).map((c) => {
    const ratio = c.rate / control.rate;
    const se = Math.sqrt(1 / c.events + 1 / control.events);
    const log = Math.log(ratio);
    const statistic = log / se;
    return `  ${c.name} ratio ${f(ratio)} lower ${f(Math.exp(log - z95 * se))} upper ${f(Math.exp(log + z95 * se))} z ${f(statistic)} p ${f(pValue(statistic * statistic, 1))}`;
  }),
];
const survivalDifferences = [`survival_difference reference ${groups[0]}`];
for (const time of params.reportTimes) {
  for (const c of groupCollections.slice(1)) {
    const a = rowAt(c.rows, time);
    const b = rowAt(control.rows, time);
    survivalDifferences.push(
      `  at ${time} ${c.name} ${differenceText(a.survival - b.survival, Math.sqrt(a.se! * a.se! + b.se! * b.se!))}`,
    );
  }
}
const x = subjects.map((subject) =>
  params.covariates.map((name) =>
    name === 'age'
      ? subject.age
      : name === 'male'
        ? subject.sex === 'M'
          ? 1
          : 0
        : name === 'stage'
          ? subject.stage
          : subject.group === name
            ? 1
            : 0,
  ),
);
const fit = fitCox(subjects, x);
const p = params.covariates.length;
const covariance = inverse(fit.final.information);
const eventTotal = eventCount(subjects);
const coxLines = [
  `cox covariates ${params.covariates.join(' ')} subjects ${total} events ${eventTotal} event_times ${fit.final.risks.length}`,
  ...fit.iterations.map(
    (iteration, i) =>
      `iter ${i + 1} loglik ${f(iteration.loglik)} beta ${iteration.beta.map((value) => f(value)).join(' ')}`,
  ),
  `final loglik ${f(fit.final.loglik)} null_loglik ${f(fit.null.loglik)}`,
];
function coefficientText(coef: number, se: number): string {
  const statistic = coef / se;
  return `coef ${f(coef)} se ${f(se)} z ${f(statistic)} p ${f(pValue(statistic * statistic, 1))} hr ${f(Math.exp(coef))} lower ${f(Math.exp(coef - z95 * se))} upper ${f(Math.exp(coef + z95 * se))}`;
}
params.covariates.forEach((name, c) =>
  coxLines.push(`term ${name} ${coefficientText(fit.beta[c], Math.sqrt(covariance[c][c]))}`),
);
for (let a = 0; a < p; a++) {
  for (let b = a + 1; b < p; b++) {
    if (groups.includes(params.covariates[a]) && groups.includes(params.covariates[b])) {
      coxLines.push(
        `contrast ${params.covariates[b]} vs ${params.covariates[a]} ${coefficientText(fit.beta[b] - fit.beta[a], Math.sqrt(covariance[b][b] + covariance[a][a] - 2 * covariance[a][b]))}`,
      );
    }
  }
}
let wald = 0;
for (let c = 0; c < p; c++) {
  let inner = 0;
  for (let d = 0; d < p; d++) inner += fit.final.information[c][d] * fit.beta[d];
  wald += fit.beta[c] * inner;
}
const scoreSolution = solve(fit.null.information, fit.null.score);
let score = 0;
for (let c = 0; c < p; c++) score += fit.null.score[c] * scoreSolution[c];
for (const [name, chi2] of [
  ['likelihood_ratio', 2 * (fit.final.loglik - fit.null.loglik)],
  ['wald', wald],
  ['score', score],
] as const) {
  coxLines.push(`${name} chisq ${f(chi2)} df ${p} p ${f(pValue(chi2, p))}`);
}
params.covariates.forEach((name, c) => {
  const loglik =
    p === 1
      ? fit.null.loglik
      : fitCox(
          subjects,
          x.map((row) => row.filter((_, d) => d !== c)),
        ).final.loglik;
  const chi2 = 2 * (fit.final.loglik - loglik);
  coxLines.push(`drop ${name} loglik ${f(loglik)} chisq ${f(chi2)} df 1 p ${f(pValue(chi2, 1))}`);
});
let comparable = 0;
let concordant = 0;
let tied = 0;
subjects.forEach((a, i) => {
  if (a.event === 1) {
    subjects.forEach((b, j) => {
      if (i === j || !(a.time < b.time || (a.time === b.time && b.event === 0))) return;
      comparable++;
      if (x[i].every((value, c) => value === x[j][c])) tied++;
      else if (fit.final.theta[i] > fit.final.theta[j]) concordant++;
    });
  }
});
coxLines.push(
  `concordance ${f((2 * concordant + tied) / (2 * comparable))} comparable ${comparable} concordant ${concordant} tied ${tied}`,
);
const riskByTime = new Map(fit.final.risks.map((risk) => [risk.time, risk]));
const eventOrder = subjects
  .map((s, i) => ({ s, i }))
  .filter(({ s }) => s.event === 1)
  .sort((a, b) => a.s.time - b.s.time || a.s.id - b.s.id);
const meanTime = sum(eventOrder.map(({ s }) => s.time)) / eventOrder.length;
for (let c = 0; c < p; c++) {
  const residuals = eventOrder.map(({ s, i }) => {
    const risk = riskByTime.get(s.time)!;
    return x[i][c] - risk.s1[c] / risk.s0;
  });
  const mean = sum(residuals) / eventOrder.length;
  let sxy = 0;
  let sxx = 0;
  let syy = 0;
  eventOrder.forEach(({ s }, i) => {
    sxy += (residuals[i] - mean) * (s.time - meanTime);
    sxx += (residuals[i] - mean) * (residuals[i] - mean);
    syy += (s.time - meanTime) * (s.time - meanTime);
  });
  const rho = sxy / Math.sqrt(sxx * syy);
  const statistic = 0.5 * Math.log((1 + rho) / (1 - rho)) * Math.sqrt(eventOrder.length - 3);
  coxLines.push(
    `ph_check ${params.covariates[c]} rho ${f(rho)} z ${f(statistic)} p ${f(pValue(statistic * statistic, 1))}`,
  );
}
let cumulative = 0;
const hazards = [...fit.final.risks]
  .sort((a, b) => a.time - b.time)
  .map((risk) => {
    cumulative += risk.events / risk.s0;
    return { time: risk.time, hazard: cumulative };
  });
const hazardAt = (time: number) => {
  let value = 0;
  for (const row of hazards) {
    if (row.time > time) break;
    value = row.hazard;
  }
  return value;
};
const residuals = subjects
  .map((subject, j) => {
    const martingale = subject.event - hazardAt(subject.time) * Math.exp(fit.final.theta[j]);
    let deviance =
      subject.event === 1
        ? Math.sqrt(-2 * (martingale + Math.log(1 - martingale)))
        : Math.sqrt(-2 * martingale);
    if (!(martingale > 0)) deviance = -deviance;
    return { subject, martingale, deviance };
  })
  .sort((a, b) => Math.abs(b.deviance) - Math.abs(a.deviance) || a.subject.id - b.subject.id);
coxLines.push(
  `residuals top ${params.residuals}`,
  ...residuals
    .slice(0, params.residuals)
    .map(
      ({ subject: s, martingale, deviance }) =>
        `  id ${s.id} group ${s.group} time ${s.time} event ${s.event} martingale ${f(martingale)} deviance ${f(deviance)}`,
    ),
);
const means = params.covariates.map((_, c) => sum(x.map((row) => row[c])) / total);
const meanEntries = params.covariates.flatMap((name, c) =>
  ['age', 'male', 'stage'].includes(name) ? [`${name} ${f(means[c])}`] : [],
);
const representativeRisks = groups.map((group) => {
  let theta = 0;
  params.covariates.forEach((name, c) => {
    theta += fit.beta[c] * (groups.includes(name) ? (name === group ? 1 : 0) : means[c]);
  });
  return Math.exp(theta);
});
coxLines.push(`adjusted_survival mean ${meanEntries.join(' ') || 'none'}`);
for (const time of params.reportTimes) {
  coxLines.push(
    `  at ${time} ${groups.map((group, g) => `${group} ${f(Math.exp(-hazardAt(time) * representativeRisks[g]))}`).join(' ')}`,
  );
}
coxLines.push(
  `  median ${groups.map((group, g) => `${group} ${day(hazards.find((row) => Math.exp(-row.hazard * representativeRisks[g]) <= 0.5)?.time)}`).join(' ')}`,
);
const plotLines = plot(groupCollections, params);
const riskTimes = Array.from(
  { length: params.divisions + 1 },
  (_, i) => i * (params.plotTime / params.divisions),
);
plotLines.push(
  `at_risk ${riskTimes.join(' ')}`,
  ...groupCollections.map(
    (c) => `${c.name} ${riskTimes.map((time) => atRisk(c.subjects, time)).join(' ')}`,
  ),
);
const joinBlocks = (blocks: string[][]) =>
  blocks.flatMap((block, i) => (i ? ['', ...block] : block));
mkdirSync('output', { recursive: true });
for (const [name, lines] of [
  ['km_tables.txt', joinBlocks(kmBlocks)],
  ['life_table.csv', lifeLines],
  [
    'tests.txt',
    joinBlocks([
      baseline,
      overall,
      stratifiedLines,
      landmark,
      pairwise,
      subgroups,
      rmstDifferences,
      rateRatios,
      survivalDifferences,
    ]),
  ],
  ['cox.txt', coxLines],
  ['km_plot.txt', plotLines],
] as const) {
  writeFileSync(`output/${name}`, lines.join('\n') + '\n', 'ascii');
}
