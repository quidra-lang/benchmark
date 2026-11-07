'use strict';

const { solve } = require('./numerics');

function evaluate(subjects, vectors, beta) {
  const p = beta.length;
  const predictors = [];
  const risks = [];
  for (let j = 0; j < subjects.length; j++) {
    let predictor = 0;
    for (let c = 0; c < p; c++) predictor += beta[c] * vectors[j][c];
    predictors.push(predictor);
    risks.push(Math.exp(predictor));
  }
  const order = subjects.map((subject, index) => index);
  order.sort((a, b) => subjects[b].time - subjects[a].time || subjects[a].id - subjects[b].id);
  let s0 = 0;
  const s1 = Array(p).fill(0);
  const s2 = Array.from({ length: p }, () => Array(p).fill(0));
  let loglik = 0;
  const score = Array(p).fill(0);
  const information = Array.from({ length: p }, () => Array(p).fill(0));
  const eventRows = new Map();
  let position = 0;
  while (position < order.length) {
    const time = subjects[order[position]].time;
    const deaths = [];
    while (position < order.length && subjects[order[position]].time === time) {
      const j = order[position++];
      s0 += risks[j];
      for (let c = 0; c < p; c++) {
        s1[c] += risks[j] * vectors[j][c];
        for (let d = 0; d < p; d++) s2[c][d] += risks[j] * vectors[j][c] * vectors[j][d];
      }
      if (subjects[j].event === 1) deaths.push(j);
    }
    const e = deaths.length;
    if (e === 0) continue;
    let predictorSum = 0;
    const covariateSum = Array(p).fill(0);
    for (const j of deaths) {
      predictorSum += predictors[j];
      for (let c = 0; c < p; c++) covariateSum[c] += vectors[j][c];
    }
    loglik += predictorSum - e * Math.log(s0);
    for (let c = 0; c < p; c++) {
      score[c] += covariateSum[c] - e * s1[c] / s0;
      for (let d = 0; d < p; d++) {
        information[c][d] += e * (s2[c][d] / s0 - (s1[c] / s0) * (s1[d] / s0));
      }
    }
    eventRows.set(time, { time, events: e, s0, s1: s1.slice() });
  }
  return { loglik, score, information, predictors, risks, eventRows };
}

function fit(subjects, vectors) {
  const beta = Array(vectors[0].length).fill(0);
  const iterations = [];
  let nullEvaluation = null;
  for (let s = 1; s <= 25; s++) {
    const current = evaluate(subjects, vectors, beta);
    if (s === 1) nullEvaluation = current;
    const delta = solve(current.information, current.score);
    for (let c = 0; c < beta.length; c++) beta[c] += delta[c];
    iterations.push({ iteration: s, loglik: current.loglik, beta: beta.slice() });
  }
  return { beta, iterations, nullEvaluation, finalEvaluation: evaluate(subjects, vectors, beta) };
}

module.exports = { evaluate, fit };
