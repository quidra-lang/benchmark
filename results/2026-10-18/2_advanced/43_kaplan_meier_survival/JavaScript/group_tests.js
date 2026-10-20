'use strict';

const { riskSets } = require('./estimators');
const { solve, chiSquareP } = require('./numerics');

function emptySums(count) {
  return {
    events: Array(count).fill(0),
    observed: Array(count).fill(0),
    expected: Array(count).fill(0),
    covariance: Array.from({ length: count }, () => Array(count).fill(0))
  };
}

function finishTest(sums) {
  const degrees = sums.events.length - 1;
  const difference = [];
  for (let h = 0; h < degrees; h++) difference.push(sums.observed[h] - sums.expected[h]);
  const matrix = sums.covariance.slice(0, degrees).map(row => row.slice(0, degrees));
  const solution = solve(matrix, difference);
  let chisq = 0;
  for (let h = 0; h < degrees; h++) chisq += difference[h] * solution[h];
  return { ...sums, chisq, degrees, p: chiSquareP(chisq, degrees) };
}

function weightedTest(subjects, groups, weight, totalSubjects) {
  const count = groups.length;
  const indices = new Map(groups.map((name, index) => [name, index]));
  const sums = emptySums(count);
  for (const row of riskSets(subjects)) {
    if (row.events === 0) continue;
    const atRisk = Array(count).fill(0);
    const events = Array(count).fill(0);
    for (const subject of subjects) {
      const h = indices.get(subject.group);
      if (subject.time >= row.time) atRisk[h]++;
      if (subject.time === row.time && subject.event === 1) events[h]++;
    }
    let n = 0;
    let d = 0;
    for (let h = 0; h < count; h++) {
      n += atRisk[h];
      d += events[h];
    }
    const nu = weight === 'logrank' ? 1 :
      weight === 'gehan_wilcoxon' ? n / totalSubjects : Math.sqrt(n / totalSubjects);
    for (let h = 0; h < count; h++) {
      sums.events[h] += events[h];
      sums.observed[h] += nu * events[h];
      sums.expected[h] += nu * ((d * atRisk[h]) / n);
      if (n < 2) continue;
      for (let l = 0; l < count; l++) {
        const multiplier = h === l ? atRisk[h] * (n - atRisk[h]) : -(atRisk[h] * atRisk[l]);
        sums.covariance[h][l] += nu * nu * ((d * (n - d)) / ((n - 1) * n * n)) * multiplier;
      }
    }
  }
  return finishTest(sums);
}

function combineStrata(tests) {
  const count = tests[0].events.length;
  const totals = emptySums(count);
  for (const test of tests) {
    for (let h = 0; h < count; h++) {
      totals.events[h] += test.events[h];
      totals.observed[h] += test.observed[h];
      totals.expected[h] += test.expected[h];
      for (let l = 0; l < count; l++) totals.covariance[h][l] += test.covariance[h][l];
    }
  }
  return finishTest(totals);
}

module.exports = { weightedTest, combineStrata };
