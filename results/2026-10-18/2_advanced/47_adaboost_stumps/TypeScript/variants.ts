import { Stump, prepare, regressionSearch, realPlans, realSearch } from './stumps.ts';
import { normalize } from './adaboost.ts';
import type { Training, RealRound, GentleRound, LogitRound, Stop } from './adaboost.ts';
import type { BinaryRow, Parameters } from './dataset.ts';
function exponentialUpdate(rows: BinaryRow[], weights: number[], stump: Stump): void {
  rows.forEach((row, i) => {
    weights[i] *= Math.exp(-row.label * stump.output(row.values));
  });
  normalize(weights);
}
export function real(rows: BinaryRow[], params: Parameters): Training {
  const plans = realPlans(rows, params.bins);
  const weights = Array<number>(rows.length).fill(1 / rows.length);
  const rounds: RealRound[] = [];
  let bound = 1;
  let stop: Stop = 'completed';
  for (let t = 0; t < params.rounds; t++) {
    const c = realSearch(rows, weights, plans, params.bins);
    const z = c.error;
    if (z >= 1 - params.convergence) {
      stop = 'converged';
      break;
    }
    const values = c.positive.map(
      (p, b) => 0.5 * Math.log((p + params.smoothing) / (c.negative[b] + params.smoothing)),
    );
    const stump = new Stump(c.feature, c.cuts, values);
    bound *= z;
    rounds.push({ kind: 'real', stump, z, bound, weights: weights.slice() });
    exponentialUpdate(rows, weights, stump);
  }
  return { rounds, stop, cuts: plans.map((p) => p.cuts) };
}
export function gentle(rows: BinaryRow[], params: Parameters): Training {
  const plans = prepare(rows);
  const targets = rows.map((r) => r.label);
  const weights = Array<number>(rows.length).fill(1 / rows.length);
  const rounds: GentleRound[] = [];
  for (let t = 0; t < params.rounds; t++) {
    const { stump, error } = regressionSearch(rows, targets, weights, plans);
    rounds.push({ kind: 'gentle', stump, error, weights: weights.slice() });
    exponentialUpdate(rows, weights, stump);
  }
  return { rounds, stop: 'completed' };
}
export function logit(rows: BinaryRow[], params: Parameters): Training {
  const plans = prepare(rows);
  const scores = Array<number>(rows.length).fill(0);
  const probabilities = Array<number>(rows.length).fill(0.5);
  const rounds: LogitRound[] = [];
  for (let t = 0; t < params.rounds; t++) {
    const responses: number[] = [];
    const weights: number[] = [];
    rows.forEach((row, i) => {
      const p = probabilities[i];
      const q = p * (1 - p);
      let z = ((row.label === 1 ? 1 : 0) - p) / q;
      if (z > params.clip) z = params.clip;
      if (z < -params.clip) z = -params.clip;
      responses.push(z);
      weights.push(q);
    });
    normalize(weights);
    const selected = regressionSearch(rows, responses, weights, plans);
    const stump = new Stump(
      selected.stump.feature,
      selected.stump.thresholds,
      selected.stump.values.map((v) => v / 2),
    );
    rows.forEach((row, i) => {
      scores[i] += stump.output(row.values);
      probabilities[i] = 1 / (1 + Math.exp(-2 * scores[i]));
    });
    let loss = 0;
    rows.forEach((row, i) => {
      loss += Math.log(1 + Math.exp(-2 * row.label * scores[i]));
    });
    rounds.push({
      kind: 'logit',
      stump,
      error: selected.error,
      loss: loss / rows.length,
      weights: weights.slice(),
    });
  }
  return { rounds, stop: 'completed' };
}
