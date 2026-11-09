import type { Point, Fit } from './dataset.ts';
export interface Curve {
  g: number[];
  gamma: number[];
}
export interface SplineFit extends Fit {
  kind: 'spline';
  yhat: number[];
  system: SmoothingSpline;
  curve: Curve;
}
export class SmoothingSpline {
  positions: number[];
  x: number[];
  h: number[];
  lower1: number[] = [];
  lower2: number[] = [];
  diagonal: number[] = [];
  constructor(
    points: Point[],
    public lambda: number,
  ) {
    this.positions = points.map((p) => p.X);
    this.x = points.map((p) => p.x);
    this.h = this.x.slice(1).map((v, i) => v - this.x[i]);
    const count = points.length - 2;
    const a = Array.from({ length: count }, (_, k) => 1 / this.h[k]);
    const c = Array.from({ length: count }, (_, k) => 1 / this.h[k + 1]);
    const b = a.map((v, k) => -(v + c[k]));
    const diagonal = a.map(
      (v, k) => (this.h[k] + this.h[k + 1]) / 3 + lambda * (v * v + b[k] * b[k] + c[k] * c[k]),
    );
    const first = Array.from(
      { length: count - 1 },
      (_, k) => this.h[k + 1] / 6 + lambda * c[k] * (b[k] + b[k + 1]),
    );
    const second = Array.from({ length: count - 2 }, (_, k) => lambda * c[k] * c[k + 1]);
    for (let k = 0; k < count; k++) {
      const d1 = this.diagonal[k - 1] ?? 0;
      const d2 = this.diagonal[k - 2] ?? 0;
      const l2 = k >= 2 ? second[k - 2] / d2 : 0;
      const l1 = k >= 1 ? (first[k - 1] - l2 * d2 * this.lower1[k - 1]) / d1 : 0;
      this.lower1.push(l1);
      this.lower2.push(l2);
      this.diagonal.push(diagonal[k] - l1 * l1 * d1 - l2 * l2 * d2);
    }
  }
  fit(values: number[]): Curve {
    const z: number[] = [];
    for (let k = 0; k < values.length - 2; k++) {
      const phi =
        (values[k + 2] - values[k + 1]) / this.h[k + 1] - (values[k + 1] - values[k]) / this.h[k];
      z.push(phi - this.lower1[k] * (z[k - 1] ?? 0) - this.lower2[k] * (z[k - 2] ?? 0));
    }
    const gamma: number[] = Array(values.length).fill(0);
    for (let k = z.length - 1; k >= 0; k--) {
      gamma[k + 1] =
        z[k] / this.diagonal[k] -
        (this.lower1[k + 1] ?? 0) * gamma[k + 2] -
        (this.lower2[k + 2] ?? 0) * (gamma[k + 3] ?? 0);
    }
    const g = values.map((v, i) => {
      const omega =
        i === 0
          ? (gamma[1] - gamma[0]) / this.h[0]
          : i === values.length - 1
            ? 0 - (gamma[i] - gamma[i - 1]) / this.h[i - 1]
            : (gamma[i + 1] - gamma[i]) / this.h[i] - (gamma[i] - gamma[i - 1]) / this.h[i - 1];
      return v - this.lambda * omega;
    });
    return { g, gamma };
  }
  evaluate({ g, gamma }: Curve, position: number): number {
    const x0 = position / 100;
    const last = this.x.length - 1;
    if (position < this.positions[0]) {
      const tau = (g[1] - g[0]) / this.h[0] - (this.h[0] * gamma[1]) / 6;
      return g[0] - (this.x[0] - x0) * tau;
    }
    if (position > this.positions[last]) {
      const tau =
        (g[last] - g[last - 1]) / this.h[last - 1] + (this.h[last - 1] * gamma[last - 1]) / 6;
      return g[last] + (x0 - this.x[last]) * tau;
    }
    let low = 0;
    let high = this.positions.length;
    while (low < high) {
      const mid = Math.floor((low + high) / 2);
      if (this.positions[mid] < position) low = mid + 1;
      else high = mid;
    }
    if (this.positions[low] === position) return g[low];
    const i = low - 1;
    const pl = x0 - this.x[i];
    const pr = this.x[i + 1] - x0;
    return (
      (pl * g[i + 1] + pr * g[i]) / this.h[i] -
      (pl * pr * ((1 + pl / this.h[i]) * gamma[i + 1] + (1 + pr / this.h[i]) * gamma[i])) / 6
    );
  }
  unitFits(): Curve[] {
    return this.positions.map((_, i) => {
      const v = this.positions.map(() => 0);
      v[i] = 1;
      return this.fit(v);
    });
  }
}
export function fit(points: Point[], lambda: number, withWeights = true): SplineFit {
  const system = new SmoothingSpline(points, lambda);
  const curve = system.fit(points.map((p) => p.y));
  const units = withWeights ? system.unitFits() : null;
  const lev = units === null ? null : units.map((u, i) => u.g[i]);
  let edf: number | null = null;
  if (lev) {
    edf = 0;
    for (const v of lev) edf += v;
  }
  return {
    kind: 'spline',
    system,
    curve,
    yhat: curve.g,
    lev,
    edf,
    at: (position: number) => ({
      value: system.evaluate(curve, position),
      weights: units === null ? null : units.map((u) => system.evaluate(u, position)),
    }),
  };
}
