import type { Parameters, Subject } from './dataset.ts';
import { rowAt, type KmRow } from './estimators.ts';

export interface PlotCollection { name: string; subjects: Subject[]; rows: KmRow[] }
export function plot(collections: PlotCollection[], params: Parameters): string[] {
  const { width, height, plotTime } = params;
  const cells = Array.from({ length: height }, () => Array.from({ length: width }, () => new Set<number>()));
  collections.forEach((collection, g) => {
    const maximum = Math.max(...collection.subjects.map(s => s.time));
    let previous: number | undefined;
    for (let i = 0; i < width; i++) {
      const time = i * (plotTime / width); if (time > maximum) break;
      const band = Math.min(height - 1, Math.floor(rowAt(collection.rows, time).survival * height));
      cells[band][i].add(g);
      if (previous !== undefined && previous - 1 > band) for (let q = band + 1; q < previous; q++) cells[q][i].add(g);
      previous = band;
    }
  });
  const border = '   +' + '-'.repeat(width) + '+';
  const lines = [`km_plot width ${width} height ${height} time ${plotTime}`, `legend ${collections.map((collection, g) => `${String.fromCharCode(65 + g)} ${collection.name}`).join(' ')}`, border];
  for (let q = height - 1; q >= 0; q--) lines.push(String(Math.floor(100 * q / height)).padStart(3) + '|' + cells[q].map(cell => !cell.size ? ' ' : cell.size > 1 ? '*' : String.fromCharCode(65 + [...cell][0])).join('') + '|');
  lines.push(border, `time 0 to ${plotTime} days, ${plotTime / width} days per column`);
  return lines;
}
