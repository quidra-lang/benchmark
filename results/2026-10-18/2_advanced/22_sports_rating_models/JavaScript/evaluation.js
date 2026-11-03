const { fraction } = require('./report');

function sigma(value) {
  return 1 / (1 + Math.exp(-value));
}

function fitLink(features, results, iterations) {
  let alpha = 0;
  let beta = 0;
  for (let iteration = 0; iteration < iterations; iteration += 1) {
    let g0 = 0;
    let g1 = 0;
    let h00 = 0;
    let h01 = 0;
    let h11 = 0;
    for (let index = 0; index < features.length; index += 1) {
      const z = features[index];
      const p = sigma(alpha + beta * z);
      const w = p * (1 - p);
      g0 += results[index] - p;
      g1 += (results[index] - p) * z;
      h00 += w;
      h01 += w * z;
      h11 += w * z * z;
    }
    const determinant = h00 * h11 - h01 * h01;
    alpha += (h11 * g0 - h01 * g1) / determinant;
    beta += (h00 * g1 - h01 * g0) / determinant;
  }
  return { alpha, beta };
}

function logLoss(probability, result) {
  if (result === 1) return -Math.log(probability);
  if (result === 0) return -Math.log(1 - probability);
  return -(Math.log(probability) / 2 + Math.log(1 - probability) / 2);
}

function brier(probability, result) {
  return (probability - result) * (probability - result);
}

function correctness(probability, result) {
  if (result === 0.5) return 0.5;
  return (probability > 0.5 && result === 1) || (probability < 0.5 && result === 0) ? 1 : 0;
}

function compareValues(first, second) {
  if (Array.isArray(first)) return Math.sign(first[0] * second[1] - second[0] * first[1]);
  return Math.sign(first - second);
}

function averageRanks(values) {
  return values.map(value => {
    let greater = 0;
    let equal = 0;
    for (const other of values) {
      const comparison = compareValues(other, value);
      if (comparison > 0) greater += 1;
      if (comparison === 0) equal += 1;
    }
    return greater + (equal + 1) / 2;
  });
}

function kendall(first, second) {
  let difference = 0;
  for (let i = 0; i < first.length; i += 1) {
    for (let j = i + 1; j < first.length; j += 1) {
      difference += compareValues(first[i], first[j]) * compareValues(second[i], second[j]);
    }
  }
  return fraction(difference, first.length * (first.length - 1) / 2);
}

function spearman(first, second) {
  const a = averageRanks(first);
  const b = averageRanks(second);
  let squared = 0;
  for (let team = 0; team < a.length; team += 1) {
    const twiceDifference = 2 * (a[team] - b[team]);
    squared += twiceDifference * twiceDifference;
  }
  const denominator = 4 * a.length * (a.length * a.length - 1);
  return fraction(denominator - 6 * squared, denominator);
}

module.exports = { sigma, fitLink, logLoss, brier, correctness, compareValues, averageRanks, kendall, spearman };
