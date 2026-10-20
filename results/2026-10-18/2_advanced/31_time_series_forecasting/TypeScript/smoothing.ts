import { mean } from './decomposition.ts';
export type SmoothName = 'ses' | 'holt' | 'damped' | 'hw_add' | 'hw_mult';
export interface Parameters {
  alpha: number;
  beta: number;
  gamma: number;
  phi: number;
}
export interface State {
  level: number;
  slope: number;
  seasonal: number[];
}
export function smooth(name: SmoothName, values: number[], season: number, p: Parameters) {
  const { alpha, beta, gamma, phi } = p;
  const winters = name === 'hw_add' || name === 'hw_mult';
  let level = winters ? mean(values.slice(0, season)) : values[0];
  let slope =
    name === 'ses'
      ? 0
      : winters
        ? (mean(values.slice(season, 2 * season)) - level) / season
        : (values[season] - values[0]) / season;
  const seasonal = winters
    ? values.slice(0, season).map((v) => (name === 'hw_add' ? v - level : v / level))
    : [];
  const snapshot = (): State => ({ level, slope, seasonal: seasonal.slice() });
  const states = [snapshot()];
  const residuals: number[] = [];
  for (let t = 0; t < values.length; t++) {
    const value = values[t];
    let nextLevel: number;
    let nextSlope = slope;
    if (name === 'ses') {
      residuals.push(value - level);
      nextLevel = alpha * value + (1 - alpha) * level;
    } else if (!winters) {
      const f = level + phi * slope;
      residuals.push(value - f);
      nextLevel = alpha * value + (1 - alpha) * f;
      nextSlope = beta * (nextLevel - level) + (1 - beta) * phi * slope;
    } else {
      const j = t % season;
      const u = level + slope;
      const q = seasonal[j];
      if (name === 'hw_add') {
        residuals.push(value - (u + q));
        nextLevel = alpha * (value - q) + (1 - alpha) * u;
        seasonal[j] = gamma * (value - u) + (1 - gamma) * q;
      } else {
        residuals.push(value - u * q);
        nextLevel = alpha * (value / q) + (1 - alpha) * u;
        seasonal[j] = gamma * (value / u) + (1 - gamma) * q;
      }
      nextSlope = beta * (nextLevel - level) + (1 - beta) * slope;
    }
    level = nextLevel;
    slope = nextSlope;
    states.push(snapshot());
  }
  return { states, residuals };
}
export function forecast(
  name: SmoothName,
  state: State,
  origin: number,
  steps: number,
  season: number,
  p: Parameters,
) {
  const values: number[] = [];
  let power = p.phi;
  let cumulative = power;
  for (let k = 1; k <= steps; k++) {
    if (name === 'ses') values.push(state.level);
    else if (name === 'holt' || name === 'damped') {
      if (k > 1) {
        power *= p.phi;
        cumulative += power;
      }
      values.push(state.level + cumulative * state.slope);
    } else {
      const seasonal = state.seasonal[(origin + k - 1) % season];
      values.push(
        name === 'hw_add'
          ? state.level + k * state.slope + seasonal
          : (state.level + k * state.slope) * seasonal,
      );
    }
  }
  return values;
}
