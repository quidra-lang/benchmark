import { readFileSync } from 'node:fs';
export interface Point {
  id: string;
  x: number;
  y: number;
}
export interface Position {
  x: number;
  y: number;
}
export interface Covariance {
  a: number;
  b: number;
  c: number;
}
export interface Component extends Covariance {
  w: number;
  mx: number;
  my: number;
}
export type CovarianceType = 'FULL' | 'TIED' | 'DIAG' | 'SPHERICAL';
export interface Params {
  ks: number[];
  types: CovarianceType[];
  iterations: number;
  eps: number;
  tau: number;
  kmeansMax: number;
  folds: number;
  uncertain: number;
  lowDensity: number;
  edges: number[];
  xmin: number;
  xmax: number;
  ymin: number;
  ymax: number;
  width: number;
  height: number;
}
export function read() {
  const lines = (name: string) =>
    readFileSync('input/' + name, 'ascii')
      .slice(0, -1)
      .split('\n');
  const points: Point[] = lines('points.csv')
    .slice(1)
    .map((line) => {
      const [id, x, y] = line.split(',');
      return { id, x: +x, y: +y };
    });
  const fields = new Map(
    lines('params.txt').map((line) => {
      const [name, ...v] = line.split(' ');
      return [name, v];
    }),
  );
  const p = (k: string) => fields.get(k)!;
  const v = (k: string) => p(k).map(Number);
  const n = (k: string) => +p(k)[0];
  const params: Params = {
    ks: v('K'),
    types: p('TYPES') as CovarianceType[],
    iterations: n('ITERATIONS'),
    eps: n('REGULARIZATION'),
    tau: n('SETTLE_TOLERANCE'),
    kmeansMax: n('KMEANS_MAX_ITERATIONS'),
    folds: n('CV_FOLDS'),
    uncertain: n('UNCERTAIN_THRESHOLD'),
    lowDensity: n('LOW_DENSITY_THRESHOLD'),
    edges: v('GOF_EDGES'),
    xmin: v('MAP_X')[0],
    xmax: v('MAP_X')[1],
    ymin: v('MAP_Y')[0],
    ymax: v('MAP_Y')[1],
    width: v('MAP_SIZE')[0],
    height: v('MAP_SIZE')[1],
  };
  const initial = new Map<number, Component[]>();
  for (const block of lines('init.txt').join('\n').split('\n\n')) {
    const rows = block.split('\n');
    const k = +rows[0].split(' ')[1];
    const weights = rows[1].split(' ').slice(1).map(Number);
    initial.set(
      k,
      rows.slice(2).map((line, j) => {
        const [, , mx, my, a, b, c] = line.split(' ').map(Number);
        return { w: weights[j], mx, my, a, b, c };
      }),
    );
  }
  return { points, params, initial };
}
