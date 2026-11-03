import type { Station, Parameters } from './waveform_io.ts';
import type { Pick } from './picker.ts';
export interface Point {
  x: number;
  y: number;
  z: number;
  t0: number;
}
export interface Observation {
  station: Station;
  time: number;
  pick: Pick;
}
export function distance(p: Omit<Point, 't0'>, s: Station) {
  const dx = p.x - s.x;
  const dy = p.y - s.y;
  const dz = p.z + s.elevation;
  return Math.sqrt(dx * dx + dy * dy + dz * dz);
}
export function evaluate(point: Point, observations: Observation[], velocity: number) {
  const distances: number[] = [];
  const residuals: number[] = [];
  let squares = 0;
  for (const o of observations) {
    const d = distance(point, o.station);
    const r = o.time - point.t0 - d / velocity;
    distances.push(d);
    residuals.push(r);
    squares += r * r;
  }
  return { distances, residuals, squares, rms: Math.sqrt(squares / observations.length) };
}
function normalEquations(point: Point, obs: Observation[], v: number) {
  const evaluation = evaluate(point, obs, v);
  const g = obs.map((o, j) => {
    const denominator = v * evaluation.distances[j];
    return [
      (point.x - o.station.x) / denominator,
      (point.y - o.station.y) / denominator,
      (point.z + o.station.elevation) / denominator,
      1,
    ];
  });
  const matrix: number[][] = Array.from({ length: 4 }, () => Array(4).fill(0));
  const rhs: number[] = Array(4).fill(0);
  for (let a = 0; a < 4; a++) {
    for (let c = 0; c < 4; c++) {
      for (let j = 0; j < obs.length; j++) matrix[a][c] += g[j][a] * g[j][c];
    }
    for (let j = 0; j < obs.length; j++) rhs[a] += g[j][a] * evaluation.residuals[j];
  }
  return { matrix, rhs, evaluation };
}
function cholesky(a: number[][]) {
  const l: number[][] = Array.from({ length: 4 }, () => Array(4).fill(0));
  for (let i = 0; i < 4; i++) {
    for (let j = 0; j <= i; j++) {
      let sum = 0;
      for (let k = 0; k < j; k++) sum += l[i][k] * l[j][k];
      l[i][j] = i === j ? Math.sqrt(a[i][i] - sum) : (a[i][j] - sum) / l[j][j];
    }
  }
  return l;
}
function solve(l: number[][], b: number[]) {
  const u: number[] = Array(4).fill(0);
  const d: number[] = Array(4).fill(0);
  for (let a = 0; a < 4; a++) {
    let sum = 0;
    for (let k = 0; k < a; k++) sum += l[a][k] * u[k];
    u[a] = (b[a] - sum) / l[a][a];
  }
  for (let a = 3; a >= 0; a--) {
    let sum = 0;
    for (let k = a + 1; k < 4; k++) sum += l[k][a] * d[k];
    d[a] = (u[a] - sum) / l[a][a];
  }
  return d;
}
function gridSearch(obs: Observation[], p: Parameters) {
  const [xmin, xmax, xs] = p.gridX;
  const [ymin, ymax, ys] = p.gridY;
  const [zmin, zmax, zs] = p.gridZ;
  const profile: number[] = Array(Math.floor((zmax - zmin) / zs) + 1).fill(Infinity);
  let best: { point: Point; squares: number } | null = null;
  for (let a = 0; xmin + a * xs <= xmax; a++) {
    for (let b = 0; ymin + b * ys <= ymax; b++) {
      for (let c = 0; zmin + c * zs <= zmax; c++) {
        const point: Point = { x: xmin + a * xs, y: ymin + b * ys, z: zmin + c * zs, t0: 0 };
        const deltas: number[] = [];
        let total = 0;
        for (const o of obs) {
          const delta = o.time - distance(point, o.station) / p.velocity;
          deltas.push(delta);
          total += delta;
        }
        point.t0 = total / obs.length;
        let squares = 0;
        for (const d of deltas) squares += (d - point.t0) * (d - point.t0);
        if (!best || squares < best.squares) best = { point, squares };
        profile[c] = Math.min(profile[c], squares);
      }
    }
  }
  return {
    point: best!.point,
    rms: Math.sqrt(best!.squares / obs.length),
    profile: profile.map((s) => Math.sqrt(s / obs.length)),
  };
}
export function geiger(initial: Point, obs: Observation[], velocity: number) {
  let point = { ...initial };
  const iterations: { point: Point; rms: number }[] = [];
  for (let i = 0; i < 8; i++) {
    const eq = normalEquations(point, obs, velocity);
    const d = solve(cholesky(eq.matrix), eq.rhs);
    point = {
      x: point.x + d[0],
      y: point.y + d[1],
      z: Math.max(0, point.z + d[2]),
      t0: point.t0 + d[3],
    };
    iterations.push({ point, rms: evaluate(point, obs, velocity).rms });
  }
  return { point, iterations, ...evaluate(point, obs, velocity) };
}
export function locationRun(obs: Observation[], p: Parameters) {
  const grid = gridSearch(obs, p);
  return { grid, observations: obs, ...geiger(grid.point, obs, p.velocity) };
}
export function uncertainty(point: Point, obs: Observation[], velocity: number) {
  const { matrix, evaluation } = normalEquations(point, obs, velocity);
  const l = cholesky(matrix);
  const variance = evaluation.squares / (obs.length - 4);
  const covariance: number[][] = Array.from({ length: 4 }, () => Array(4).fill(0));
  for (let c = 0; c < 4; c++) {
    const unit = [0, 0, 0, 0];
    unit[c] = 1;
    const column = solve(l, unit);
    for (let a = 0; a < 4; a++) covariance[a][c] = variance * column[a];
  }
  const xx = covariance[0][0];
  const yy = covariance[1][1];
  const xy = covariance[0][1];
  const mu = (xx + yy) / 2;
  const half = (xx - yy) / 2;
  const rho = Math.sqrt(half * half + xy * xy);
  const theta = ((Math.atan2(2 * xy, xx - yy) / 2) * 180) / 3.141592653589793;
  let az = 90 - theta;
  if (az >= 180) az -= 180;
  return {
    smaj: Math.sqrt(mu + rho),
    smin: Math.sqrt(mu - rho),
    az,
    erz: Math.sqrt(covariance[2][2]),
    ert: Math.sqrt(covariance[3][3]),
  };
}
