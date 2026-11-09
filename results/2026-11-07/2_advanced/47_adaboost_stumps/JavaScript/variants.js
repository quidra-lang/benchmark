'use strict';

const { Stump, prepare, regressionSearch, realPlans, realSearch } = require('./stumps');
const { normalize } = require('./adaboost');

function exponentialUpdate(rows, weights, stump) {
  for (let i = 0; i < rows.length; i++) weights[i] *= Math.exp(-rows[i].label * stump.output(rows[i].values));
  normalize(weights);
}

function real(rows, params) {
  const plans = realPlans(rows, params.bins);
  const weights = Array(rows.length).fill(1 / rows.length);
  const rounds = [];
  let bound = 1;
  let stop = 'completed';
  for (let t = 0; t < params.rounds; t++) {
    const candidate = realSearch(rows, weights, plans, params.bins);
    const z = candidate.error;
    if (z >= 1 - params.convergence) { stop = 'converged'; break; }
    const values = candidate.positive.map((positive, b) =>
      0.5 * Math.log((positive + params.smoothing) / (candidate.negative[b] + params.smoothing)));
    const stump = new Stump(candidate.feature, candidate.cuts, values);
    bound *= z;
    rounds.push({ stump, z, bound, weights: weights.slice() });
    exponentialUpdate(rows, weights, stump);
  }
  return { rounds, stop, cuts: plans.map(plan => plan.cuts) };
}

function gentle(rows, params) {
  const plans = prepare(rows);
  const targets = rows.map(row => row.label);
  const weights = Array(rows.length).fill(1 / rows.length);
  const rounds = [];
  for (let t = 0; t < params.rounds; t++) {
    const { stump, error } = regressionSearch(rows, targets, weights, plans);
    rounds.push({ stump, error, weights: weights.slice() });
    exponentialUpdate(rows, weights, stump);
  }
  return { rounds, stop: 'completed' };
}

function logit(rows, params) {
  const plans = prepare(rows);
  const scores = Array(rows.length).fill(0);
  const probabilities = Array(rows.length).fill(0.5);
  const rounds = [];
  for (let t = 0; t < params.rounds; t++) {
    const responses = [];
    const weights = [];
    for (let i = 0; i < rows.length; i++) {
      const probability = probabilities[i];
      const q = probability * (1 - probability);
      let response = ((rows[i].label === 1 ? 1 : 0) - probability) / q;
      if (response > params.clip) response = params.clip;
      if (response < -params.clip) response = -params.clip;
      responses.push(response);
      weights.push(q);
    }
    normalize(weights);
    const selected = regressionSearch(rows, responses, weights, plans);
    const stump = new Stump(selected.stump.feature, selected.stump.thresholds, selected.stump.values.map(value => value / 2));
    for (let i = 0; i < rows.length; i++) {
      scores[i] += stump.output(rows[i].values);
      probabilities[i] = 1 / (1 + Math.exp(-2 * scores[i]));
    }
    let loss = 0;
    for (let i = 0; i < rows.length; i++) loss += Math.log(1 + Math.exp(-2 * rows[i].label * scores[i]));
    loss /= rows.length;
    rounds.push({ stump, error: selected.error, loss, weights: weights.slice() });
  }
  return { rounds, stop: 'completed' };
}

module.exports = { real, gentle, logit };
