import { Stump, prepare, discreteSearch, multiclassSearch } from './stumps.ts';
import type { BinaryRow, MultiRow } from './dataset.ts';
export type Stop = 'completed' | 'weak' | 'perfect' | 'converged';
interface WeightedRound { stump: Stump; weights: number[] }
export interface DiscreteRound extends WeightedRound { kind: 'discrete'; polarity: number; error: number; alpha: number; z: number; bound: number }
export interface RealRound extends WeightedRound { kind: 'real'; z: number; bound: number }
export interface GentleRound extends WeightedRound { kind: 'gentle'; error: number }
export interface LogitRound extends WeightedRound { kind: 'logit'; error: number; loss: number }
export type Round = DiscreteRound | RealRound | GentleRound | LogitRound;
export interface Training { rounds: Round[]; stop: Stop; cuts?: number[][] }
export interface SammeRound { stump: Stump; error: number; alpha: number }
export function normalize(weights: number[]): number {
  let total = 0;
  for (const w of weights) total += w;
  for (let i = 0; i < weights.length; i++) weights[i] /= total;
  return total;
}
export function discrete(rows: BinaryRow[], maximumRounds: number, shrinkage = 1, initialWeights: number[] | null = null): Training {
  const plans = prepare(rows), weights = initialWeights === null ? Array<number>(rows.length).fill(1 / rows.length) : initialWeights.slice();
  const rounds: DiscreteRound[] = [];
  let bound = 1, stop: Stop = 'completed';
  for (let t = 0; t < maximumRounds; t++) {
    const candidate = discreteSearch(rows, weights, plans), error = candidate.error;
    if (error >= 0.5) { stop = 'weak'; break; }
    const alpha = error <= 1e-10 ? 1 : shrinkage * (0.5 * Math.log((1 - error) / error)), polarity = candidate.polarity;
    const stump = new Stump(candidate.feature, [candidate.threshold], [-polarity * alpha, polarity * alpha]), before = weights.slice();
    rows.forEach((row, i) => {
      const decision = row.values[candidate.feature] > candidate.threshold ? polarity : -polarity;
      weights[i] *= decision === row.label ? Math.exp(-alpha) : Math.exp(alpha);
    });
    const z = normalize(weights);
    bound *= z;
    rounds.push({ kind: 'discrete', stump, polarity, error, alpha, z, bound, weights: before });
    if (error <= 1e-10) { stop = 'perfect'; break; }
  }
  return { rounds, stop };
}
export function samme(rows: MultiRow[], classes: number, maximumRounds: number): { rounds: SammeRound[]; stop: Stop } {
  const plans = prepare(rows), weights = Array<number>(rows.length).fill(1 / rows.length), rounds: SammeRound[] = [];
  let stop: Stop = 'completed';
  for (let t = 0; t < maximumRounds; t++) {
    const { stump, error } = multiclassSearch(rows, weights, plans, classes);
    if (error >= (classes - 1) / classes) { stop = 'weak'; break; }
    const alpha = error <= 1e-10 ? 1 : Math.log((1 - error) / error) + Math.log(classes - 1);
    rows.forEach((row, i) => { if (stump.output(row.values) !== row.category) weights[i] *= Math.exp(alpha); });
    normalize(weights); rounds.push({ stump, error, alpha });
    if (error <= 1e-10) { stop = 'perfect'; break; }
  }
  return { rounds, stop };
}
