import type { Model } from './model_io.ts';
export class Random {
  constructor(private state: number) {}
  uniform(): number {
    this.state = (48271 * this.state) % 2147483647;
    return this.state / 2147483647;
  }
  draw(weights: number[]): number {
    let total = 0;
    for (const w of weights) total += w;
    const target = this.uniform() * total;
    let cumulative = 0;
    for (let i = 0; i < weights.length; i++) {
      cumulative += weights[i];
      if (target < cumulative) return i;
    }
    return weights.length - 1;
  }
}
export function synthetic(model: Model, length: number, random: Random) {
  const path: number[] = [];
  const obs: number[] = [];
  for (let t = 0; t < length; t++) {
    const state = random.draw(t === 0 ? model.pi : model.a[path[t - 1]]);
    path.push(state);
    obs.push(random.draw(model.b[state]));
  }
  return { path, obs };
}
export function posteriorPath(model: Model, forward: number[][], random: Random): number[] {
  const path = Array<number>(forward.length);
  path[path.length - 1] = random.draw(forward[path.length - 1]);
  for (let t = path.length - 2; t >= 0; t--) {
    path[t] = random.draw(forward[t].map((v, i) => v * model.a[i][path[t + 1]]));
  }
  return path;
}
