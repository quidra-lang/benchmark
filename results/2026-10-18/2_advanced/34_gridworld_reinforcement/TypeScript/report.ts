import { mkdirSync, writeFileSync } from 'node:fs';
import { ACTIONS, type World } from './environment.ts';
import { floorDivide } from './dynamic_programming.ts';
export function fixed(v: number | null): string {
  if (v === null) return '-';
  const n = Math.abs(v);
  return `${v < 0 ? '-' : ''}${floorDivide(n, 10000)}.${String(n % 10000).padStart(4, '0')}`;
}
export function average(total: number, count: number): string {
  return fixed(floorDivide(10000 * total, count));
}
export function cell(world: World, position: number): string {
  return `${floorDivide(position, world.width)},${position % world.width}`;
}
export function grid(
  world: World,
  content: (state: number, position: number) => string | number,
  separated = false,
): string[] {
  return Array.from({ length: world.height }, (_, row) =>
    Array.from({ length: world.width }, (_, col) => {
      const p = row * world.width + col;
      const state = world.index[p];
      return state < 0 ? world.cells[p] : String(content(state, p));
    }).join(separated ? ' ' : ''),
  );
}
export function policyGrid(world: World, policy: number[]): string[] {
  return grid(world, (s) => '^>v<'[policy[s]]);
}
export function qRows(
  name: string,
  world: World,
  table: number[][],
  visits: number[][] | null = null,
): string[] {
  return world.states.flatMap((p, s) =>
    ACTIONS.map(
      (a, i) =>
        `${name},${cell(world, p)},${a},${fixed(table[s][i])},${visits === null ? '-' : visits[s][i]}`,
    ),
  );
}
export function writeReports(reports: Record<string, string[]>): void {
  mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(reports)) {
    writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
  }
}
