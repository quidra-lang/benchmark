import type { CompartmentModel } from './models.ts';
const STEP = 0.25;
const HALF_STEP = STEP / 2;
const SIXTH_STEP = STEP / 6;
export function rk4(model: CompartmentModel, state: number[], multiplier: number): number[] {
  const k1 = model.rate(state, multiplier);
  const k2 = model.rate(
    state.map((v, i) => v + HALF_STEP * k1[i]),
    multiplier,
  );
  const k3 = model.rate(
    state.map((v, i) => v + HALF_STEP * k2[i]),
    multiplier,
  );
  const k4 = model.rate(
    state.map((v, i) => v + STEP * k3[i]),
    multiplier,
  );
  return state.map((v, i) => v + SIXTH_STEP * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i]));
}
export function simulate(
  model: CompartmentModel,
  multipliers: number[],
  initial = model.initial,
): number[][] {
  let state = initial.slice();
  const days: number[][] = [];
  for (const multiplier of multipliers) {
    state = state.slice();
    for (const i of model.inflows) state[i] = 0;
    for (let step = 0; step < 4; step++) state = rk4(model, state, multiplier);
    days.push(state);
  }
  return days;
}
