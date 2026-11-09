import type { Grid } from './types.ts';

export function symbolLines(grid: Grid): string[] {
  return grid.map(row => row.map(value => value === 1 ? '#' : '.').join(''));
}

export function pbm(grid: Grid, quiet: number, scale: number): string {
  const width = (grid.length + 2 * quiet) * scale, border = '0'.repeat(width);
  const margin = '0'.repeat(quiet * scale), lines = ['P1', width + ' ' + width];
  for (let i = 0; i < quiet * scale; i++) lines.push(border);
  for (const row of grid) {
    const pixels = margin + row.map(value => String(value).repeat(scale)).join('') + margin;
    for (let i = 0; i < scale; i++) lines.push(pixels);
  }
  for (let i = 0; i < quiet * scale; i++) lines.push(border);
  return lines.join('\n') + '\n';
}

