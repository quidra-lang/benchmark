'use strict';

const fs = require('node:fs');
const { readDataset } = require('./dataset');
const { kaplanMeier, rowAt, lifeTable } = require('./estimators');
const { weightedTest, combineStrata } = require('./group_tests');
const { fit } = require('./cox');
const { plotLines } = require('./plot');
const { Z, solve, inverse, chiSquareP } = require('./numerics');

const WEIGHTS = ['logrank', 'gehan_wilcoxon', 'tarone_ware'];
const CONTINUOUS = new Set(['age', 'male', 'stage']);

function fixed(value, digits = 4) {
  if (value === null) return 'NA';
  const magnitude = Math.abs(value);
  const result = magnitude >= 1e21 ?
    BigInt(magnitude).toString() + '.' + '0'.repeat(digits) : magnitude.toFixed(digits);
  return value < 0 && result !== '0.' + '0'.repeat(digits) ? '-' + result : result;
}

function day(value) {
  return value === null ? 'NA' : String(value);
}

function eventCount(subjects) {
  let count = 0;
  for (const subject of subjects) count += subject.event;
  return count;
}

function levelsOf(subjects, variable) {
  return [...new Set(subjects.map(subject => subject[variable]))].sort((a, b) =>
    a < b ? -1 : a > b ? 1 : 0);
}

function firstDay(rows, predicate) {
  for (const row of rows) if (predicate(row)) return row.time;
  return null;
}

function restrictedMean(rows, tau) {
  const selected = rows.filter(row => row.time <= tau);
  const times = [0, ...selected.map(row => row.time), tau];
  const rectangles = [];
  for (let i = 0; i <= selected.length; i++) {
    const survival = i === 0 ? 1 : selected[i - 1].survival;
    rectangles.push(survival * (times[i + 1] - times[i]));
  }
  const suffix = Array(rectangles.length).fill(0);
  const last = rectangles.length - 1;
  suffix[last] = rectangles[last];
  for (let i = last - 1; i >= 0; i--) suffix[i] = rectangles[i] + suffix[i + 1];
  let variance = 0;
  for (let i = 1; i <= selected.length; i++) {
    const { atRisk: n, events: d } = selected[i - 1];
    variance += suffix[i] * suffix[i] * (d / (n * (n - d)));
  }
  const estimate = suffix[0];
  const se = Math.sqrt(variance);
  return { estimate, se, lower: estimate - Z * se, upper: estimate + Z * se };
}

function ageSummary(subjects) {
  let ageSum = 0;
  let male = 0;
  const stages = Array(4).fill(0);
  for (const subject of subjects) {
    ageSum += subject.age;
    if (subject.sex === 'M') male++;
    stages[subject.stage - 1]++;
  }
  const mean = ageSum / subjects.length;
  let squares = 0;
  for (const subject of subjects) squares += (subject.age - mean) * (subject.age - mean);
  const sd = Math.sqrt(squares / (subjects.length - 1));
  const ages = subjects.map(subject => subject.age).sort((a, b) => a - b);
  const median = (ages[Math.floor((ages.length - 1) / 2)] + ages[Math.floor(ages.length / 2)]) / 2;
  return { mean, sd, median, male, stages };
}

function makeCollection(name, subjects, params) {
  const km = kaplanMeier(subjects);
  const life = lifeTable(subjects, params.lifeWidth, params.lifeCount);
  const events = eventCount(subjects);
  let personDays = 0;
  let maxTime = 0;
  for (const subject of subjects) {
    personDays += subject.time;
    if (subject.time > maxTime) maxTime = subject.time;
  }
  const rate = (1000 * events) / personDays;
  const eta = Z / Math.sqrt(events);
  const rateLower = Math.exp(Math.log(rate) - eta);
  const rateUpper = Math.exp(Math.log(rate) + eta);
  const reverse = subjects.map(subject => ({ ...subject, event: 1 - subject.event }));
  const followupMedian = firstDay(kaplanMeier(reverse), row => row.survival <= 0.5);
  let lifeMedian = null;
  let previous = 1;
  for (const row of life) {
    if (row.survival <= 0.5) {
      lifeMedian = row.start + params.lifeWidth * (previous - 0.5) / (previous - row.survival);
      break;
    }
    previous = row.survival;
  }
  const percentiles = [];
  for (const [percentile, q] of [[25, 0.75], [50, 0.5], [75, 0.25]]) {
    percentiles.push({
      percentile,
      time: firstDay(km, row => row.survival <= q),
      lower: firstDay(km, row => (row.survival === 0 ? 0 : row.lower) <= q),
      upper: firstDay(km, row => (row.survival === 0 ? 0 : row.upper) <= q)
    });
  }
  const reports = [];
  for (const time of params.reportTimes) {
    let atRisk = 0;
    let cumulativeEvents = 0;
    for (const subject of subjects) {
      if (subject.time >= time) atRisk++;
      if (subject.time <= time && subject.event === 1) cumulativeEvents++;
    }
    reports.push({ time, atRisk, events: cumulativeEvents, row: rowAt(km, time) });
  }
  return {
    name, subjects, km, life, events, personDays, maxTime, rate, rateLower, rateUpper,
    followupMedian, lifeMedian, percentiles, reports,
    rmst: restrictedMean(km, params.tau), age: ageSummary(subjects)
  };
}

function kmReport(collections, params) {
  const blocks = [];
  const header = ['time', 'at_risk', 'events', 'censored', 'survival', 'std_err', 'lower', 'upper', 'cum_haz', 'haz_se'];
  for (const collection of collections) {
    const { name, subjects, events, personDays, maxTime, rmst } = collection;
    const lines = [
      `group ${name} subjects ${subjects.length} events ${events} censored ${subjects.length - events} max_time ${maxTime}`,
      `person_days ${personDays} rate ${fixed(collection.rate)} lower ${fixed(collection.rateLower)} upper ${fixed(collection.rateUpper)}`,
      `followup_median ${day(collection.followupMedian)}`,
      `life_table_median ${fixed(collection.lifeMedian)}`
    ];
    for (const percentile of collection.percentiles) {
      lines.push(`percentile ${percentile.percentile} time ${day(percentile.time)} lower ${day(percentile.lower)} upper ${day(percentile.upper)}`);
    }
    lines.push(`rmst tau ${params.tau} estimate ${fixed(rmst.estimate)} se ${fixed(rmst.se)} lower ${fixed(rmst.lower)} upper ${fixed(rmst.upper)}`);
    for (const report of collection.reports) {
      const row = report.row;
      lines.push(`at ${report.time} at_risk ${report.atRisk} events ${report.events}` +
        ` survival ${fixed(row.survival)} std_err ${fixed(row.stdErr)} lower ${fixed(row.lower)} upper ${fixed(row.upper)}` +
        ` cum_hazard ${fixed(row.cumHazard)} hazard_se ${fixed(row.hazardSe)}`);
    }
    lines.push(header.map(field => field.padStart(9)).join(''));
    for (const row of collection.km) {
      const fields = [row.time, row.atRisk, row.events, row.censored,
        fixed(row.survival), fixed(row.stdErr), fixed(row.lower), fixed(row.upper),
        fixed(row.cumHazard), fixed(row.hazardSe)];
      lines.push(fields.map(field => String(field).padStart(9)).join(''));
    }
    blocks.push(lines.join('\n'));
  }
  return blocks.join('\n\n');
}

function lifeReport(collections) {
  const lines = ['group,interval,at_risk,events,withdrawn,exposed,q,survival,std_err,hazard'];
  for (const collection of collections) {
    for (const row of collection.life) {
      lines.push([collection.name, `${row.start}-${row.end}`, row.atRisk, row.events,
        row.withdrawn, fixed(row.exposed, 1), fixed(row.q), fixed(row.survival),
        fixed(row.stdErr), fixed(row.hazard)].join(','));
    }
  }
  return lines.join('\n');
}

function statistic(chisq, degrees) {
  return { chisq, degrees, p: chiSquareP(chisq, degrees) };
}

function testFields(test) {
  return `chisq ${fixed(test.chisq)} df ${test.degrees} p ${fixed(test.p)}`;
}

function baselineReport(subjects, groups, collections) {
  const lines = ['baseline'];
  for (const collection of collections) {
    const age = collection.age;
    lines.push(`  group ${collection.name} subjects ${collection.subjects.length}` +
      ` age_mean ${fixed(age.mean)} age_sd ${fixed(age.sd)} age_median ${fixed(age.median, 1)}` +
      ` male ${age.male} stage ${age.stages.join(' ')}`);
  }
  const byAge = subjects.slice().sort((a, b) => a.age - b.age || a.id - b.id);
  const ranks = new Map();
  let ties = 0;
  let p = 0;
  while (p < byAge.length) {
    let q = p + 1;
    while (q < byAge.length && byAge[q].age === byAge[p].age) q++;
    const rank = (p + 1 + q) / 2;
    for (let i = p; i < q; i++) ranks.set(byAge[i].id, rank);
    const count = q - p;
    ties += count * count * count - count;
    p = q;
  }
  const indices = new Map(groups.map((group, index) => [group, index]));
  const rankSums = Array(groups.length).fill(0);
  for (const subject of subjects) rankSums[indices.get(subject.group)] += ranks.get(subject.id);
  let rankTerm = 0;
  for (let g = 0; g < groups.length; g++) {
    rankTerm += rankSums[g] * rankSums[g] / collections[g].subjects.length;
  }
  const n = subjects.length;
  const w0 = 12 * rankTerm / (n * (n + 1)) - 3 * (n + 1);
  const w = w0 / (1 - ties / (n * n * n - n));
  lines.push(`  age kruskal_wallis ${testFields(statistic(w, groups.length - 1))}`);
  for (const variable of ['sex', 'stage']) {
    const levels = levelsOf(subjects, variable);
    const counts = levels.map(level => subjects.filter(subject => subject[variable] === level).length);
    let chisq = 0;
    for (let g = 0; g < groups.length; g++) {
      const groupSubjects = collections[g].subjects;
      for (let j = 0; j < levels.length; j++) {
        const observed = groupSubjects.filter(subject => subject[variable] === levels[j]).length;
        const expected = (groupSubjects.length * counts[j]) / n;
        chisq += (observed - expected) * (observed - expected) / expected;
      }
    }
    lines.push(`  ${variable} ${testFields(statistic(chisq, (groups.length - 1) * (levels.length - 1)))}`);
  }
  return lines.join('\n');
}

function groupLines(test, groups) {
  return groups.map((name, h) =>
    `  group ${name} events ${test.events[h]} observed ${fixed(test.observed[h])}` +
    ` expected ${fixed(test.expected[h])} o_minus_e ${fixed(test.observed[h] - test.expected[h])}` +
    ` variance ${fixed(test.covariance[h][h])}`);
}

function overallReport(subjects, groups) {
  const lines = [];
  let logrank = null;
  for (const weight of WEIGHTS) {
    const test = weightedTest(subjects, groups, weight, subjects.length);
    if (weight === 'logrank') logrank = test;
    lines.push(`test ${weight} ${testFields(test)}`, ...groupLines(test, groups));
  }
  let difference = 0;
  let variance = 0;
  for (let g = 0; g < groups.length; g++) {
    difference += (g + 1) * (logrank.observed[g] - logrank.expected[g]);
    let inner = 0;
    for (let h = 0; h < groups.length; h++) inner += ((g + 1) * (h + 1)) * logrank.covariance[g][h];
    variance += inner;
  }
  lines.push(`test logrank_trend ${testFields(statistic(difference * difference / variance, 1))}`);
  return lines.join('\n');
}

function stratifiedReport(subjects, params) {
  const levels = levelsOf(subjects, params.strata);
  const strata = levels.map(level => subjects.filter(subject => subject[params.strata] === level));
  const lines = [];
  for (const weight of WEIGHTS) {
    const tests = strata.map(stratum => weightedTest(stratum, params.groups, weight, subjects.length));
    const combined = combineStrata(tests);
    lines.push(`stratified ${weight} by ${params.strata} ${testFields(combined)}`);
    for (let i = 0; i < strata.length; i++) {
      lines.push(`  stratum ${levels[i]} subjects ${strata[i].length} events ${eventCount(strata[i])}` +
        ` chisq ${fixed(tests[i].chisq)} p ${fixed(tests[i].p)}`);
    }
    lines.push(...groupLines(combined, params.groups));
  }
  return lines.join('\n');
}

function twoGroup(subjects, a, b, totalSubjects) {
  const test = weightedTest(subjects, [a, b], 'logrank', totalSubjects);
  const hr = (test.observed[1] / test.expected[1]) / (test.observed[0] / test.expected[0]);
  const phi = 1 / test.expected[0] + 1 / test.expected[1];
  const logHr = Math.log(hr);
  const lower = Math.exp(logHr - Z * Math.sqrt(phi));
  const upper = Math.exp(logHr + Z * Math.sqrt(phi));
  return { ...test, hr, phi, logHr, lower, upper };
}

function hazardFields(test) {
  return `hr ${fixed(test.hr)} lower ${fixed(test.lower)} upper ${fixed(test.upper)}`;
}

function pairwiseReport(subjects, groups) {
  const pairs = [];
  for (let a = 0; a < groups.length; a++) {
    for (let b = a + 1; b < groups.length; b++) {
      const selected = subjects.filter(subject => subject.group === groups[a] || subject.group === groups[b]);
      pairs.push({ a, b, order: pairs.length, ...twoGroup(selected, groups[a], groups[b], subjects.length) });
    }
  }
  const sorted = pairs.slice().sort((a, b) => a.p - b.p || a.order - b.order);
  let preceding = 0;
  for (let i = 0; i < sorted.length; i++) {
    const candidate = (sorted.length - i) * sorted[i].p;
    sorted[i].adjusted = Math.max(preceding, Math.min(1, candidate));
    preceding = sorted[i].adjusted;
  }
  const lines = ['pairwise logrank adjust holm'];
  for (const pair of pairs) {
    lines.push(`  ${groups[pair.a]} ${groups[pair.b]} chisq ${fixed(pair.chisq)} p ${fixed(pair.p)}` +
      ` p_holm ${fixed(pair.adjusted)} ${hazardFields(pair)}`);
  }
  return lines.join('\n');
}

function subgroupReport(subjects, params) {
  const control = params.groups[0];
  const lines = [`subgroups reference ${control}`];
  for (const variable of params.subgroups) {
    const levels = levelsOf(subjects, variable);
    for (const group of params.groups.slice(1)) {
      const tests = [];
      for (const level of levels) {
        const selected = subjects.filter(subject => subject[variable] === level &&
          (subject.group === control || subject.group === group));
        const test = twoGroup(selected, control, group, subjects.length);
        tests.push(test);
        lines.push(`  ${variable} ${level} ${group} subjects ${selected.length} events ${eventCount(selected)}` +
          ` ${hazardFields(test)} p ${fixed(test.p)}`);
      }
      let numerator = 0;
      let denominator = 0;
      for (const test of tests) {
        const psi = 1 / test.phi;
        numerator += psi * test.logHr;
        denominator += psi;
      }
      const mean = numerator / denominator;
      let heterogeneity = 0;
      for (const test of tests) heterogeneity += (1 / test.phi) * (test.logHr - mean) * (test.logHr - mean);
      lines.push(`  ${variable} ${group} heterogeneity ${testFields(statistic(heterogeneity, levels.length - 1))}`);
    }
  }
  return lines.join('\n');
}

function differenceFields(difference, se) {
  const zeta = difference / se;
  return `difference ${fixed(difference)} se ${fixed(se)} lower ${fixed(difference - Z * se)}` +
    ` upper ${fixed(difference + Z * se)} z ${fixed(zeta)} p ${fixed(chiSquareP(zeta * zeta, 1))}`;
}

function comparisonsReport(subjects, params, collections) {
  const groups = params.groups;
  const parts = [baselineReport(subjects, groups, collections), overallReport(subjects, groups),
    stratifiedReport(subjects, params)];
  const landmarkSubjects = subjects.filter(subject => subject.time > params.landmark);
  const landmark = weightedTest(landmarkSubjects, groups, 'logrank', subjects.length);
  parts.push([`landmark ${params.landmark} subjects ${landmarkSubjects.length} ${testFields(landmark)}`,
    ...groupLines(landmark, groups)].join('\n'));
  parts.push(pairwiseReport(subjects, groups), subgroupReport(subjects, params));
  const control = collections[0];
  const rmstLines = [`rmst_difference tau ${params.tau} reference ${groups[0]}`];
  const rateLines = [`rate_ratio reference ${groups[0]}`];
  for (let g = 1; g < groups.length; g++) {
    const collection = collections[g];
    const difference = collection.rmst.estimate - control.rmst.estimate;
    const se = Math.sqrt(collection.rmst.se * collection.rmst.se + control.rmst.se * control.rmst.se);
    rmstLines.push(`  ${groups[g]} ${differenceFields(difference, se)}`);
    const ratio = collection.rate / control.rate;
    const rateSe = Math.sqrt(1 / collection.events + 1 / control.events);
    const logarithm = Math.log(ratio);
    const zeta = logarithm / rateSe;
    rateLines.push(`  ${groups[g]} ratio ${fixed(ratio)} lower ${fixed(Math.exp(logarithm - Z * rateSe))}` +
      ` upper ${fixed(Math.exp(logarithm + Z * rateSe))} z ${fixed(zeta)} p ${fixed(chiSquareP(zeta * zeta, 1))}`);
  }
  parts.push(rmstLines.join('\n'), rateLines.join('\n'));
  const survivalLines = [`survival_difference reference ${groups[0]}`];
  for (let i = 0; i < params.reportTimes.length; i++) {
    const reference = control.reports[i].row;
    for (let g = 1; g < groups.length; g++) {
      const row = collections[g].reports[i].row;
      const difference = row.survival - reference.survival;
      const se = Math.sqrt(row.stdErr * row.stdErr + reference.stdErr * reference.stdErr);
      survivalLines.push(`  at ${params.reportTimes[i]} ${groups[g]} ${differenceFields(difference, se)}`);
    }
  }
  parts.push(survivalLines.join('\n'));
  return parts.join('\n\n');
}

function covariateValue(subject, name) {
  if (name === 'age') return subject.age;
  if (name === 'male') return subject.sex === 'M' ? 1 : 0;
  if (name === 'stage') return subject.stage;
  return subject.group === name ? 1 : 0;
}

function coefficientFields(coefficient, se) {
  const zeta = coefficient / se;
  return `coef ${fixed(coefficient)} se ${fixed(se)} z ${fixed(zeta)} p ${fixed(chiSquareP(zeta * zeta, 1))}` +
    ` hr ${fixed(Math.exp(coefficient))} lower ${fixed(Math.exp(coefficient - Z * se))}` +
    ` upper ${fixed(Math.exp(coefficient + Z * se))}`;
}

function concordanceLine(subjects, vectors, predictors) {
  let comparable = 0;
  let concordant = 0;
  let tied = 0;
  for (let i = 0; i < subjects.length; i++) {
    if (subjects[i].event !== 1) continue;
    for (let j = 0; j < subjects.length; j++) {
      if (i === j || !(subjects[i].time < subjects[j].time ||
          (subjects[i].time === subjects[j].time && subjects[j].event === 0))) continue;
      comparable++;
      if (vectors[i].every((value, c) => value === vectors[j][c])) tied++;
      else if (predictors[i] > predictors[j]) concordant++;
    }
  }
  const value = (2 * concordant + tied) / (2 * comparable);
  return `concordance ${fixed(value)} comparable ${comparable} concordant ${concordant} tied ${tied}`;
}

function proportionalHazardsLines(subjects, vectors, covariates, evaluation) {
  const order = subjects.map((subject, index) => index).filter(index => subjects[index].event === 1);
  order.sort((a, b) => subjects[a].time - subjects[b].time || subjects[a].id - subjects[b].id);
  let totalTime = 0;
  for (const index of order) totalTime += subjects[index].time;
  const meanTime = totalTime / order.length;
  const lines = [];
  for (let c = 0; c < covariates.length; c++) {
    const residuals = [];
    let residualSum = 0;
    for (const index of order) {
      const row = evaluation.eventRows.get(subjects[index].time);
      const residual = vectors[index][c] - row.s1[c] / row.s0;
      residuals.push(residual);
      residualSum += residual;
    }
    const meanResidual = residualSum / order.length;
    let sxy = 0;
    let sxx = 0;
    let syy = 0;
    for (let i = 0; i < order.length; i++) {
      const centeredResidual = residuals[i] - meanResidual;
      const centeredTime = subjects[order[i]].time - meanTime;
      sxy += centeredResidual * centeredTime;
      sxx += centeredResidual * centeredResidual;
      syy += centeredTime * centeredTime;
    }
    const rho = sxy / Math.sqrt(sxx * syy);
    const zeta = 0.5 * Math.log((1 + rho) / (1 - rho)) * Math.sqrt(order.length - 3);
    lines.push(`ph_check ${covariates[c]} rho ${fixed(rho)} z ${fixed(zeta)} p ${fixed(chiSquareP(zeta * zeta, 1))}`);
  }
  return lines;
}

function baselineHazard(evaluation) {
  const rows = [...evaluation.eventRows.values()].sort((a, b) => a.time - b.time);
  const baseline = [];
  let cumulative = 0;
  for (const row of rows) {
    cumulative += row.events / row.s0;
    baseline.push({ time: row.time, cumulative });
  }
  return baseline;
}

function hazardAt(baseline, time) {
  let cumulative = 0;
  for (const row of baseline) {
    if (row.time > time) break;
    cumulative = row.cumulative;
  }
  return cumulative;
}

function residualLines(subjects, evaluation, baseline, count) {
  const residuals = subjects.map((subject, index) => {
    const martingale = subject.event - hazardAt(baseline, subject.time) * Math.exp(evaluation.predictors[index]);
    let deviance = subject.event === 1 ?
      Math.sqrt(-2 * (martingale + Math.log(1 - martingale))) : Math.sqrt(-2 * martingale);
    if (!(martingale > 0)) deviance = -deviance;
    return { subject, martingale, deviance };
  });
  residuals.sort((a, b) => Math.abs(b.deviance) - Math.abs(a.deviance) || a.subject.id - b.subject.id);
  const lines = [`residuals top ${count}`];
  for (const residual of residuals.slice(0, count)) {
    const subject = residual.subject;
    lines.push(`  id ${subject.id} group ${subject.group} time ${subject.time} event ${subject.event}` +
      ` martingale ${fixed(residual.martingale)} deviance ${fixed(residual.deviance)}`);
  }
  return lines;
}

function adjustedLines(subjects, params, vectors, beta, baseline) {
  const means = Array(params.covariates.length).fill(null);
  const meanFields = [];
  for (let c = 0; c < params.covariates.length; c++) {
    if (!CONTINUOUS.has(params.covariates[c])) continue;
    let total = 0;
    for (const vector of vectors) total += vector[c];
    means[c] = total / subjects.length;
    meanFields.push(params.covariates[c], fixed(means[c]));
  }
  const risks = params.groups.map(group => {
    let predictor = 0;
    for (let c = 0; c < params.covariates.length; c++) {
      const value = means[c] === null ? (params.covariates[c] === group ? 1 : 0) : means[c];
      predictor += beta[c] * value;
    }
    return Math.exp(predictor);
  });
  const lines = ['adjusted_survival mean ' + (meanFields.length === 0 ? 'none' : meanFields.join(' '))];
  for (const time of params.reportTimes) {
    const fields = [];
    const cumulative = hazardAt(baseline, time);
    for (let g = 0; g < params.groups.length; g++) {
      fields.push(params.groups[g], fixed(Math.exp(-cumulative * risks[g])));
    }
    lines.push(`  at ${time} ${fields.join(' ')}`);
  }
  const medianFields = [];
  for (let g = 0; g < params.groups.length; g++) {
    const median = firstDay(baseline, row => Math.exp(-row.cumulative * risks[g]) <= 0.5);
    medianFields.push(params.groups[g], day(median));
  }
  lines.push('  median ' + medianFields.join(' '));
  return lines;
}

function coxReport(subjects, params) {
  const covariates = params.covariates;
  const vectors = subjects.map(subject => covariates.map(name => covariateValue(subject, name)));
  const model = fit(subjects, vectors);
  const { beta, finalEvaluation: final, nullEvaluation: initial } = model;
  const covariance = inverse(final.information);
  const lines = [`cox covariates ${covariates.join(' ')} subjects ${subjects.length}` +
    ` events ${eventCount(subjects)} event_times ${final.eventRows.size}`];
  for (const iteration of model.iterations) {
    lines.push(`iter ${iteration.iteration} loglik ${fixed(iteration.loglik)} beta ${iteration.beta.map(value => fixed(value)).join(' ')}`);
  }
  lines.push(`final loglik ${fixed(final.loglik)} null_loglik ${fixed(initial.loglik)}`);
  for (let c = 0; c < covariates.length; c++) {
    lines.push(`term ${covariates[c]} ${coefficientFields(beta[c], Math.sqrt(covariance[c][c]))}`);
  }
  for (let a = 0; a < covariates.length; a++) {
    if (CONTINUOUS.has(covariates[a])) continue;
    for (let b = a + 1; b < covariates.length; b++) {
      if (CONTINUOUS.has(covariates[b])) continue;
      const coefficient = beta[b] - beta[a];
      const se = Math.sqrt(covariance[b][b] + covariance[a][a] - 2 * covariance[a][b]);
      lines.push(`contrast ${covariates[b]} vs ${covariates[a]} ${coefficientFields(coefficient, se)}`);
    }
  }
  const likelihoodRatio = 2 * (final.loglik - initial.loglik);
  let wald = 0;
  for (let c = 0; c < covariates.length; c++) {
    let inner = 0;
    for (let d = 0; d < covariates.length; d++) inner += final.information[c][d] * beta[d];
    wald += beta[c] * inner;
  }
  const scoreSolution = solve(initial.information, initial.score);
  let score = 0;
  for (let c = 0; c < covariates.length; c++) score += initial.score[c] * scoreSolution[c];
  for (const [name, value] of [['likelihood_ratio', likelihoodRatio], ['wald', wald], ['score', score]]) {
    lines.push(`${name} ${testFields(statistic(value, covariates.length))}`);
  }
  for (let c = 0; c < covariates.length; c++) {
    const reduced = covariates.length === 1 ? null : vectors.map(vector => vector.filter((value, index) => index !== c));
    const loglik = reduced === null ? initial.loglik : fit(subjects, reduced).finalEvaluation.loglik;
    const test = statistic(2 * (final.loglik - loglik), 1);
    lines.push(`drop ${covariates[c]} loglik ${fixed(loglik)} ${testFields(test)}`);
  }
  lines.push(concordanceLine(subjects, vectors, final.predictors));
  lines.push(...proportionalHazardsLines(subjects, vectors, covariates, final));
  const baseline = baselineHazard(final);
  lines.push(...residualLines(subjects, final, baseline, params.residuals));
  lines.push(...adjustedLines(subjects, params, vectors, beta, baseline));
  return lines.join('\n');
}

function kmPlotReport(collections, params) {
  const { width, height, time, divisions } = params.plot;
  const groups = collections.slice(0, params.groups.length);
  const legend = [];
  for (let g = 0; g < groups.length; g++) legend.push(String.fromCharCode(65 + g), groups[g].name);
  const lines = [`km_plot width ${width} height ${height} time ${time}`, 'legend ' + legend.join(' '),
    ...plotLines(groups, width, height, time)];
  const riskTimes = [];
  for (let i = 0; i <= divisions; i++) riskTimes.push(i * (time / divisions));
  lines.push('at_risk ' + riskTimes.join(' '));
  for (const group of groups) {
    const counts = riskTimes.map(sampleTime => group.subjects.filter(subject => subject.time >= sampleTime).length);
    lines.push(group.name + ' ' + counts.join(' '));
  }
  return lines.join('\n');
}

function main() {
  const { subjects, params } = readDataset();
  const collections = params.groups.map(name =>
    makeCollection(name, subjects.filter(subject => subject.group === name), params));
  collections.push(makeCollection('all', subjects, params));
  const outputs = [
    ['km_tables.txt', kmReport(collections, params)],
    ['life_table.csv', lifeReport(collections)],
    ['tests.txt', comparisonsReport(subjects, params, collections)],
    ['cox.txt', coxReport(subjects, params)],
    ['km_plot.txt', kmPlotReport(collections, params)]
  ];
  fs.mkdirSync('output', { recursive: true });
  for (const [name, content] of outputs) fs.writeFileSync('output/' + name, content + '\n', 'ascii');
}

main();
