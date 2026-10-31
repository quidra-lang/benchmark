'use strict';

const { Stump, prepare, discreteSearch, multiclassSearch } = require('./stumps');

function normalize(weights) {
  let total = 0;
  for (const weight of weights) total += weight;
  for (let i = 0; i < weights.length; i++) weights[i] /= total;
  return total;
}

function discrete(rows, maximumRounds, shrinkage = 1, initialWeights = null) {
  const plans = prepare(rows);
  const weights = initialWeights === null ? Array(rows.length).fill(1 / rows.length) : initialWeights.slice();
  const rounds = [];
  let bound = 1;
  let stop = 'completed';
  for (let t = 0; t < maximumRounds; t++) {
    const candidate = discreteSearch(rows, weights, plans);
    const error = candidate.error;
    if (error >= 0.5) { stop = 'weak'; break; }
    const alpha = error <= 1e-10 ? 1 : shrinkage * (0.5 * Math.log((1 - error) / error));
    const polarity = candidate.polarity;
    const stump = new Stump(candidate.feature, [candidate.threshold], [-polarity * alpha, polarity * alpha]);
    const before = weights.slice();
    for (let i = 0; i < rows.length; i++) {
      const decision = rows[i].values[candidate.feature] > candidate.threshold ? polarity : -polarity;
      weights[i] *= decision === rows[i].label ? Math.exp(-alpha) : Math.exp(alpha);
    }
    const z = normalize(weights);
    bound *= z;
    rounds.push({ stump, polarity, error, alpha, z, bound, weights: before });
    if (error <= 1e-10) { stop = 'perfect'; break; }
  }
  return { rounds, stop };
}

function samme(rows, classes, maximumRounds) {
  const plans = prepare(rows);
  const weights = Array(rows.length).fill(1 / rows.length);
  const rounds = [];
  let stop = 'completed';
  for (let t = 0; t < maximumRounds; t++) {
    const candidate = multiclassSearch(rows, weights, plans, classes);
    const { stump, error } = candidate;
    if (error >= (classes - 1) / classes) { stop = 'weak'; break; }
    const alpha = error <= 1e-10 ? 1 : Math.log((1 - error) / error) + Math.log(classes - 1);
    for (let i = 0; i < rows.length; i++) {
      if (stump.output(rows[i].values) !== rows[i].category) weights[i] *= Math.exp(alpha);
    }
    normalize(weights);
    rounds.push({ stump, error, alpha });
    if (error <= 1e-10) { stop = 'perfect'; break; }
  }
  return { rounds, stop };
}

module.exports = { normalize, discrete, samme };
