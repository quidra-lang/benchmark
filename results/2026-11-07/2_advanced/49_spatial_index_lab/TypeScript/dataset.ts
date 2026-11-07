import { readFileSync } from 'node:fs';

export type Box = [number, number, number, number];
export interface SpatialObject {
  id: number;
  box: Box;
}
export interface Point extends SpatialObject {
  x: number;
  y: number;
}
export interface Settings {
  world: number;
  bucket: number;
  maximum: number;
  minimum: number;
  cell: number;
}
export interface Command {
  name: string;
  args: number[];
}
export function point(id: number, x: number, y: number): Point {
  return { id, x, y, box: [x, y, x, y] };
}
const lines = (name: string): string[] =>
  readFileSync('input/' + name, 'ascii')
    .trimEnd()
    .split('\n');
export function readDataset() {
  const points = lines('points.csv')
    .slice(1)
    .map((line) => {
      const [id, x, y] = line.split(',').map(Number);
      return point(id, x, y);
    });
  const rectangles: SpatialObject[] = lines('rects.csv')
    .slice(1)
    .map((line): SpatialObject => {
      const [id, x1, y1, x2, y2] = line.split(',').map(Number);
      return { id, box: [x1, y1, x2, y2] };
    });
  const params = lines('params.txt').map((line) => line.split(' ').slice(1).map(Number));
  const settings: Settings = {
    world: params[0][0],
    bucket: params[1][0],
    maximum: params[2][0],
    minimum: params[2][1],
    cell: params[3][0],
  };
  const commands: Command[] = lines('queries.txt').map((line) => {
    const [name, ...values] = line.split(' ');
    return { name, args: values.map(Number) };
  });
  return { points, rectangles, settings, commands };
}
