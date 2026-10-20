import { readFileSync } from 'node:fs';

export type Cell = number | string | null;
export interface DataRow { number: number; values: Record<string, Cell> }
export interface Column { name: string; categorical: boolean }
export interface Frame { columns: Column[]; rows: DataRow[] }
export interface Parameters {
  tolerance: number; alpha: number; confidence: number; leverage: number; studentized: number; cook: number; dffits: number; vif: number;
  durbinWatson: number; heterogeneity: number; normality: number; best: number; width: number; height: number; range: number;
}
function readFrame(path: string, kinds?: Column[]): Frame {
  const lines = readFileSync(path, 'ascii').trimEnd().split('\n'), names = lines[0].split(','), cells = lines.slice(1).map(line => line.split(','));
  const columns = names.map((name, c) => ({ name, categorical: kinds ? kinds.find(column => column.name === name)!.categorical : cells.some(row => row[c] !== 'NA' && /^[A-Z]/.test(row[c])) }));
  const rows = cells.map((row, i) => {
    const values: Record<string, Cell> = {};
    columns.forEach((column, c) => { values[column.name] = row[c] === 'NA' ? null : column.categorical ? row[c] : +row[c]; });
    return { number: i + 1, values };
  });
  return { columns, rows };
}
export function numberValue(row: DataRow, column: string): number {
  const value = row.values[column]; if (typeof value !== 'number') throw new Error(`Missing numeric value ${column}`); return value;
}
export function readInputs(): { data: Frame; predictions: Frame; formulas: string[]; params: Parameters } {
  const data = readFrame('input/data.csv'), predictions = readFrame('input/predict.csv', data.columns);
  const formulas = readFileSync('input/model.txt', 'ascii').trimEnd().split('\n');
  const rows = readFileSync('input/params.txt', 'ascii').trimEnd().split('\n').map(line => line.split(' ').slice(1).map(Number));
  const params: Parameters = { tolerance: rows[0][0], alpha: rows[1][0], confidence: rows[2][0], leverage: rows[3][0], studentized: rows[4][0], cook: rows[5][0],
    dffits: rows[6][0], vif: rows[7][0], durbinWatson: rows[8][0], heterogeneity: rows[9][0], normality: rows[10][0], best: rows[11][0], width: rows[12][0], height: rows[12][1], range: rows[12][2] };
  return { data, predictions, formulas, params };
}
