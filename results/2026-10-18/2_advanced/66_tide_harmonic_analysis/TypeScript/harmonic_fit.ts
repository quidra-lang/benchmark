import type { Constituent } from './records.ts';

export const PI = 3.141592653589793;
export interface FitConstituent extends Constituent {
  a: number;
  b: number;
  amplitude: number;
  phase: number;
}
export interface Model {
  mean: number;
  unknowns: number;
  coefficients: number[];
  inverse: number[][];
  constituents: FitConstituent[];
}
export interface FitRow {
  time: number;
  value: number;
}
export function angle(speed: number, time: number): number {
  const d = speed * time;
  const d2 = d - 360 * Math.floor(d / 360);
  return (d2 * PI) / 180;
}
export function regressors(constituents: Constituent[], time: number): number[] {
  const x = [1];
  for (const c of constituents) {
    const theta = angle(c.speed, time);
    x.push(Math.cos(theta), Math.sin(theta));
  }
  return x;
}
export function normalEquations(
  rows: FitRow[],
  constituents: Constituent[],
): { matrix: number[][]; rhs: number[] } {
  const p = 2 * constituents.length + 1;
  const matrix: number[][] = Array.from({ length: p }, () => Array(p).fill(0));
  const rhs: number[] = Array(p).fill(0);
  for (const row of rows) {
    const x = regressors(constituents, row.time);
    for (let i = 0; i < p; i++) {
      for (let j = 0; j < p; j++) matrix[i][j] += x[i] * x[j];
      rhs[i] += x[i] * row.value;
    }
  }
  return { matrix, rhs };
}
export function solve(
  matrix: number[][],
  rhs: number[],
): { coefficients: number[]; inverse: number[][] } {
  const p = rhs.length;
  const m = matrix.map((row, i) =>
    row.concat(
      rhs[i],
      Array.from({ length: p }, (_, j) => (i === j ? 1 : 0)),
    ),
  );
  const inverse: number[][] = Array.from({ length: p }, () => Array(p));
  let coefficients: number[] = [];
  for (let j = 0; j < p; j++) {
    let pivot = j;
    for (let i = j + 1; i < p; i++) if (Math.abs(m[i][j]) > Math.abs(m[pivot][j])) pivot = i;
    if (pivot !== j) [m[pivot], m[j]] = [m[j], m[pivot]];
    for (let i = j + 1; i < p; i++) {
      const factor = m[i][j] / m[j][j];
      for (let c = j; c <= 2 * p; c++) m[i][c] = m[i][c] - factor * m[j][c];
    }
  }
  for (let c = p; c <= 2 * p; c++) {
    const solution: number[] = Array(p);
    for (let i = p - 1; i >= 0; i--) {
      let s = m[i][c];
      for (let j = i + 1; j < p; j++) s = s - m[i][j] * solution[j];
      solution[i] = s / m[i][i];
    }
    if (c === p) coefficients = solution;
    else for (let i = 0; i < p; i++) inverse[i][c - p - 1] = solution[i];
  }
  return { coefficients, inverse };
}
export function fit(rows: FitRow[], constituents: Constituent[]): Model {
  const { matrix, rhs } = normalEquations(rows, constituents);
  const { coefficients, inverse } = solve(matrix, rhs);
  const fitted = constituents.map((c, i) => {
    const a = coefficients[2 * i + 1];
    const b = coefficients[2 * i + 2];
    const amplitude = Math.sqrt(a * a + b * b);
    let phase = (Math.atan2(b, a) * 180) / PI;
    if (phase < 0) phase += 360;
    return { ...c, a, b, amplitude, phase };
  });
  return {
    mean: coefficients[0],
    unknowns: coefficients.length,
    coefficients,
    inverse,
    constituents: fitted,
  };
}
