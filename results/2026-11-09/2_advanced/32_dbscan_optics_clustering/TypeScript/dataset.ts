import { readFileSync } from 'node:fs';

export interface Point {
  id: number;
  x: number;
  y: number;
}
export interface Parameters {
  eps: number[];
  minPts: number;
  maxEps: number;
  extract: number[];
  xi: [number, number];
  minSize: number;
  mapWidth: number;
  mapHeight: number;
  kWidth: number;
  kHeight: number;
  reachWidth: number;
}
export function readDataset(): { points: Point[]; params: Parameters } {
  const points = readFileSync('input/points.csv', 'ascii')
    .trimEnd()
    .split('\n')
    .slice(1)
    .map((line) => {
      const [id, x, y] = line.split(',').map(Number);
      return { id, x, y };
    })
    .sort((a, b) => a.id - b.id);
  const rows = readFileSync('input/params.txt', 'ascii')
    .trimEnd()
    .split('\n')
    .map((line) => line.split(' ').slice(1));
  const values = (i: number) => rows[i].map(Number);
  const [u, v] = rows[4][0].split('/').map(Number);
  const params: Parameters = {
    eps: values(0),
    minPts: +rows[1][0],
    maxEps: +rows[2][0],
    extract: values(3),
    xi: [u, v],
    minSize: +rows[5][0],
    mapWidth: +rows[6][0],
    mapHeight: +rows[6][1],
    kWidth: +rows[7][0],
    kHeight: +rows[7][1],
    reachWidth: +rows[8][0],
  };
  return { points, params };
}
