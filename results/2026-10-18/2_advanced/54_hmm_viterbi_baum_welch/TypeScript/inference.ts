import type { Model } from './model_io.ts';
export function maximum(values: number[]): number {
  let best = 0;
  for (let i = 1; i < values.length; i++) if (values[i] > values[best]) best = i;
  return best;
}
export function emission(model: Model, symbol: number, state: number): number {
  return symbol < 0 ? 1 : model.b[state][symbol];
}
export function logEmission(model: Model, symbol: number, state: number): number {
  return symbol < 0 ? 0 : Math.log(model.b[state][symbol]);
}
export function forwardBackward(model: Model, obs: number[]) {
  const k = model.pi.length;
  const forward: number[][] = [];
  const scales: number[] = [];
  let loglik = 0;
  for (let t = 0; t < obs.length; t++) {
    const row = model.pi.map((pi, j) => {
      let total = 0;
      if (t === 0) total = pi;
      else for (let i = 0; i < k; i++) total += forward[t - 1][i] * model.a[i][j];
      return total * emission(model, obs[t], j);
    });
    let scale = 0;
    for (const v of row) scale += v;
    scales.push(scale);
    forward.push(row.map((v) => v / scale));
    loglik += Math.log(scale);
  }
  const backward = Array.from({ length: obs.length }, () => Array<number>(k).fill(1));
  for (let t = obs.length - 2; t >= 0; t--) {
    for (let i = 0; i < k; i++) {
      let total = 0;
      for (let j = 0; j < k; j++) {
        total += model.a[i][j] * emission(model, obs[t + 1], j) * backward[t + 1][j];
      }
      backward[t][i] = total / scales[t + 1];
    }
  }
  const gamma = forward.map((row, t) => row.map((v, i) => v * backward[t][i]));
  return {
    forward,
    backward,
    scales,
    gamma,
    loglik,
    posterior: gamma.map(maximum),
    confidence: gamma.map((r) => r[maximum(r)]),
  };
}
export function viterbi(model: Model, obs: number[]) {
  const k = model.pi.length;
  const delta = [model.pi.map((p, j) => Math.log(p) + logEmission(model, obs[0], j))];
  const psi = [Array<number>(k).fill(0)];
  for (let t = 1; t < obs.length; t++) {
    const previous = model.pi.map((_, j) =>
      maximum(delta[t - 1].map((v, i) => v + Math.log(model.a[i][j]))),
    );
    psi.push(previous);
    delta.push(
      previous.map(
        (i, j) => delta[t - 1][i] + Math.log(model.a[i][j]) + logEmission(model, obs[t], j),
      ),
    );
  }
  const path = Array<number>(obs.length);
  path[obs.length - 1] = maximum(delta[obs.length - 1]);
  for (let t = obs.length - 1; t >= 1; t--) path[t - 1] = psi[t][path[t]];
  return { path, logprob: delta[obs.length - 1][path[obs.length - 1]] };
}
export function decode(model: Model, obs: number[]) {
  return { ...forwardBackward(model, obs), viterbi: viterbi(model, obs) };
}
