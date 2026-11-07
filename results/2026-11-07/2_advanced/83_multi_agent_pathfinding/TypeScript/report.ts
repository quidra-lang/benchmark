import { mkdirSync, writeFileSync } from 'node:fs';
import type { Grid } from './grid_map.ts';
import type { Conflict, Path } from './types.ts';

export function cell(grid: Grid, value: number): string {
  return `${value % grid.width},${Math.floor(value / grid.width)}`;
}

export function name(number: number): string {
  return String.fromCharCode(65 + number);
}

export function conflict(grid: Grid, value: Conflict): string {
  const prefix = `${value.kind} t ${value.time} ${name(value.a)} ${name(value.b)}`;
  return value.kind === 'vertex' ? `${prefix} at ${cell(grid, value.v)}` :
    `${prefix} from ${cell(grid, value.u)} to ${cell(grid, value.v)}`;
}

export function actions(grid: Grid, path: Path): string {
  let result = '';
  for (let index = 1; index < path.length; index++) {
    const delta = path[index] - path[index - 1];
    result += delta === 0 ? '.' : delta === -grid.width ? 'N' : delta === 1 ? 'E' : delta === grid.width ? 'S' : 'W';
  }
  return result;
}

export function fraction(numerator: number, denominator: number): string {
  let first = numerator;
  let second = denominator;
  while (second !== 0) [first, second] = [second, first % second];
  return `${numerator / first}/${denominator / first}`;
}

export function csv(values: (string | number | null)[]): string {
  return values.join(',');
}

export function writeFiles(files: Record<string, string[]>): void {
  mkdirSync('output', {recursive: true});
  for (const [filename, contents] of Object.entries(files)) {
    writeFileSync(`output/${filename}`, contents.join('\n') + '\n', 'ascii');
  }
}

