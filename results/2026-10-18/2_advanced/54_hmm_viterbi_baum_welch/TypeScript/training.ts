import { normalize, type Model } from './model_io.ts';
import { forwardBackward, emission } from './inference.ts';
export interface PathPair { obs: number[]; path: number[] }
function counts(k: number, m: number) { return { pi: Array<number>(k).fill(0), a: Array.from({ length: k }, () => Array<number>(k).fill(0)), b: Array.from({ length: k }, () => Array<number>(m).fill(0)) }; }
function smoothed(c: ReturnType<typeof counts>, alpha: number, name: string): Model { return { name, pi: normalize(c.pi.map(v => v + alpha)), a: c.a.map(r => normalize(r.map(v => v + alpha))), b: c.b.map(r => normalize(r.map(v => v + alpha))) }; }
export function baumWelch(model: Model, observations: number[][], pseudocount: number): Model {
  const k = model.pi.length, c = counts(k, model.b[0].length);
  for (const obs of observations) {
    const f = forwardBackward(model, obs);
    for (let i = 0; i < k; i++) c.pi[i] += f.gamma[0][i];
    for (let t = 0; t < obs.length; t++) {
      for (let i = 0; i < k; i++) if (obs[t] >= 0) c.b[i][obs[t]] += f.gamma[t][i];
      if (t + 1 < obs.length) for (let i = 0; i < k; i++) for (let j = 0; j < k; j++) c.a[i][j] += f.forward[t][i] * model.a[i][j] * emission(model, obs[t + 1], j) * f.backward[t + 1][j] / f.scales[t + 1];
    }
  }
  return smoothed(c, pseudocount, 'BAUM_WELCH');
}
export function counting(pairs: PathPair[], k: number, m: number, alpha: number, name = 'SUPERVISED'): Model {
  const c = counts(k, m);
  for (const { obs, path } of pairs) {
    c.pi[path[0]]++;
    for (let t = 0; t < obs.length; t++) { if (obs[t] >= 0) c.b[path[t]][obs[t]]++; if (t + 1 < obs.length) c.a[path[t]][path[t + 1]]++; }
  }
  return smoothed(c, alpha, name);
}
export function totalLoglik(model: Model, observations: number[][]): number { let total = 0; for (const obs of observations) total += forwardBackward(model, obs).loglik; return total; }
