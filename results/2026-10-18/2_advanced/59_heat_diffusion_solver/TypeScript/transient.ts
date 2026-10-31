import type { Mesh } from './mesh.ts';

export type Method = 'ftcs' | 'backward_euler' | 'crank_nicolson';
export interface Face {
  q: number;
  g: number;
  theta: number | null;
}
export interface ThermalModel extends Mesh {
  capacities: number[];
  faces: Face[][];
  diagonal: number[];
}
export interface Step {
  field: number[];
  intermediate: number[] | null;
}
function flow(model: ThermalModel, field: number[], p: number, start: number, end: number): number {
  let total = 0;
  let first = true;
  for (let direction = start; direction < end; direction++) {
    const face = model.faces[p][direction];
    if (face.q < 0 && face.theta === null) continue;
    const outside = face.q >= 0 ? field[face.q] : face.theta!;
    const term = face.g * (outside - field[p]);
    total = first ? term : total + term;
    first = false;
  }
  return total;
}
export const hx = (model: ThermalModel, field: number[], p: number): number =>
  flow(model, field, p, 0, 2);
export const hy = (model: ThermalModel, field: number[], p: number): number =>
  flow(model, field, p, 2, 4);
export const totalFlow = (model: ThermalModel, field: number[], p: number): number =>
  flow(model, field, p, 0, 4);
export function thomas(
  lower: number[],
  diagonal: number[],
  upper: number[],
  rhs: number[],
): number[] {
  const size = diagonal.length;
  const upperPrime = [upper[0] / diagonal[0]];
  const rhsPrime = [rhs[0] / diagonal[0]];
  for (let i = 1; i < size; i++) {
    const divisor = diagonal[i] - lower[i] * upperPrime[i - 1];
    upperPrime.push(upper[i] / divisor);
    rhsPrime.push((rhs[i] - lower[i] * rhsPrime[i - 1]) / divisor);
  }
  const answer: number[] = Array(size);
  answer[size - 1] = rhsPrime[size - 1];
  for (let i = size - 2; i >= 0; i--) answer[i] = rhsPrime[i] - upperPrime[i] * answer[i + 1];
  return answer;
}
function sweep(model: ThermalModel, tau: number, rhs: number[], horizontal: boolean): number[] {
  const lines = horizontal ? model.height : model.width;
  const size = horizontal ? model.width : model.height;
  const direction = horizontal ? 0 : 2;
  const field: number[] = Array(model.count);
  for (let line = 0; line < lines; line++) {
    const cells: number[] = [];
    const lower: number[] = [];
    const diagonal: number[] = [];
    const upper: number[] = [];
    const adjusted: number[] = [];
    for (let i = 0; i < size; i++) {
      const p = horizontal ? line * model.width + i : i * model.width + line;
      cells.push(p);
      const before = model.faces[p][direction];
      const after = model.faces[p][direction + 1];
      lower.push(before.q >= 0 ? -before.g : 0);
      diagonal.push(model.capacities[p] / tau + before.g + after.g);
      upper.push(after.q >= 0 ? -after.g : 0);
      let value = rhs[p];
      if (before.theta !== null) value += before.g * before.theta;
      if (after.theta !== null) value += after.g * after.theta;
      adjusted.push(value);
    }
    const answer = thomas(lower, diagonal, upper, adjusted);
    for (let i = 0; i < size; i++) field[cells[i]] = answer[i];
  }
  return field;
}
export const horizontalSweep = (model: ThermalModel, tau: number, rhs: number[]): number[] =>
  sweep(model, tau, rhs, true);
export const verticalSweep = (model: ThermalModel, tau: number, rhs: number[]): number[] =>
  sweep(model, tau, rhs, false);
export function ftcs(model: ThermalModel, old: number[], source: number[], dt: number): Step {
  return {
    field: old.map(
      (value, p) => value + (dt * (totalFlow(model, old, p) + source[p])) / model.capacities[p],
    ),
    intermediate: null,
  };
}
export function backwardEuler(
  model: ThermalModel,
  old: number[],
  source: number[],
  dt: number,
): Step {
  const vertical = old.map((_, p) => hy(model, old, p));
  const rhs = old.map((value, p) => (model.capacities[p] / dt) * value + vertical[p] + source[p]);
  const intermediate = horizontalSweep(model, dt, rhs);
  for (let p = 0; p < model.count; p++) {
    rhs[p] = (model.capacities[p] / dt) * intermediate[p] - vertical[p];
  }
  return { field: verticalSweep(model, dt, rhs), intermediate };
}
export function crankNicolson(
  model: ThermalModel,
  old: number[],
  source: number[],
  dt: number,
): Step {
  const tau = dt / 2;
  const rhs = old.map(
    (value, p) => (model.capacities[p] / tau) * value + hy(model, old, p) + source[p],
  );
  const intermediate = horizontalSweep(model, tau, rhs);
  for (let p = 0; p < model.count; p++) {
    rhs[p] = (model.capacities[p] / tau) * intermediate[p] + hx(model, intermediate, p) + source[p];
  }
  return { field: verticalSweep(model, tau, rhs), intermediate };
}
