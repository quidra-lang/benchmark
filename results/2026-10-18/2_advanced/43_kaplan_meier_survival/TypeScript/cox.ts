import type { Subject } from './dataset.ts';
import { solve } from './numerics.ts';

export interface RiskSums {
  time: number;
  events: number;
  s0: number;
  s1: number[];
}
export interface Evaluation {
  loglik: number;
  score: number[];
  information: number[][];
  theta: number[];
  risks: RiskSums[];
}
export function evaluate(subjects: Subject[], x: number[][], beta: number[]): Evaluation {
  const p = beta.length;
  const theta = x.map((row) => {
    let value = 0;
    for (let c = 0; c < p; c++) value += beta[c] * row[c];
    return value;
  });
  const relativeRisk = theta.map(Math.exp);
  const order = subjects
    .map((_, j) => j)
    .sort((a, b) => subjects[b].time - subjects[a].time || subjects[a].id - subjects[b].id);
  const score = Array<number>(p).fill(0);
  const information = Array.from({ length: p }, () => Array<number>(p).fill(0));
  const s1 = Array<number>(p).fill(0);
  const s2 = Array.from({ length: p }, () => Array<number>(p).fill(0));
  const risks: RiskSums[] = [];
  let s0 = 0;
  let loglik = 0;
  for (let start = 0; start < order.length;) {
    const time = subjects[order[start]].time;
    let end = start;
    while (end < order.length && subjects[order[end]].time === time) end++;
    const events: number[] = [];
    for (let position = start; position < end; position++) {
      const j = order[position];
      const r = relativeRisk[j];
      s0 = s0 + r;
      for (let c = 0; c < p; c++) {
        s1[c] = s1[c] + r * x[j][c];
        for (let d = 0; d < p; d++) s2[c][d] = s2[c][d] + r * x[j][c] * x[j][d];
      }
      if (subjects[j].event === 1) events.push(j);
    }
    if (events.length) {
      const e = events.length;
      let sumTheta = 0;
      for (const j of events) sumTheta += theta[j];
      loglik = loglik + (sumTheta - e * Math.log(s0));
      for (let c = 0; c < p; c++) {
        let sumX = 0;
        for (const j of events) sumX += x[j][c];
        score[c] = score[c] + (sumX - (e * s1[c]) / s0);
        for (let d = 0; d < p; d++) {
          information[c][d] = information[c][d] + e * (s2[c][d] / s0 - (s1[c] / s0) * (s1[d] / s0));
        }
      }
      risks.push({ time, events: e, s0, s1: [...s1] });
    }
    start = end;
  }
  return { loglik, score, information, theta, risks };
}
export interface CoxFit {
  beta: number[];
  iterations: { loglik: number; beta: number[] }[];
  final: Evaluation;
  null: Evaluation;
}
export function fitCox(subjects: Subject[], x: number[][]): CoxFit {
  let beta = Array<number>(x[0].length).fill(0);
  const nullEvaluation = evaluate(subjects, x, beta);
  const iterations: CoxFit['iterations'] = [];
  for (let s = 1; s <= 25; s++) {
    const evaluation = evaluate(subjects, x, beta);
    const delta = solve(evaluation.information, evaluation.score);
    beta = beta.map((value, c) => value + delta[c]);
    iterations.push({ loglik: evaluation.loglik, beta: [...beta] });
  }
  return { beta, iterations, final: evaluate(subjects, x, beta), null: nullEvaluation };
}
