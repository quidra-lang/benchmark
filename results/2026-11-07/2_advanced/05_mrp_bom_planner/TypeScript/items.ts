import { readFileSync } from 'node:fs';
import type { BomRow } from './bom.ts';
import type { Operation } from './capacity.ts';
export type Lot =
  | { rule: 'LFL' }
  | { rule: 'FOQ'; fixed: number }
  | { rule: 'POQ'; periods: number }
  | { rule: 'MIN'; minimum: number; multiple: number };
export interface Requirement {
  item: string;
  week: number;
  quantity: number;
  line: number;
}
export interface Item {
  id: string;
  leadTime: number;
  lot: Lot;
  safety: number;
  onHand: number;
  material: number;
  labor: number;
  description: string;
  children: BomRow[];
  parents: BomRow[];
  routing: Operation[];
  receipts: Requirement[];
  lowLevel: number;
  cumulativeLead: number;
}
export const compareIds = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0);
export function readLines(path: string): string[] {
  const text = readFileSync(path, 'ascii');
  return text === '' ? [] : text.slice(0, -1).split('\n');
}
export function csvRows(path: string): { line: number; fields: string[] }[] {
  return readLines(path)
    .slice(1)
    .map((text, i) => ({ line: i + 2, fields: text.split(',') }));
}
function lotParameters(rule: string, text: string): Lot | null {
  const parts = text.split('/');
  if (!parts.every((p) => /^\d+$/.test(p))) return null;
  const values = parts.map(Number);
  if (rule === 'LFL' && values.length === 1 && values[0] === 0) return { rule };
  if (rule === 'FOQ' && values.length === 1 && values[0] >= 1) return { rule, fixed: values[0] };
  if (rule === 'POQ' && values.length === 1 && values[0] >= 1) return { rule, periods: values[0] };
  if (rule === 'MIN' && values.length === 2 && values.every((n) => n >= 1)) {
    return { rule, minimum: values[0], multiple: values[1] };
  }
  return null;
}
export function loadItems(path: string, errors: string[]): Map<string, Item> {
  const items = new Map<string, Item>();
  for (const {
    line,
    fields: [id, leadTime, rule, parameter, safety, onHand, material, labor, description],
  } of csvRows(path)) {
    if (items.has(id)) {
      errors.push(`items.csv line ${line}: duplicate item ${id}`);
      continue;
    }
    if (!['LFL', 'FOQ', 'POQ', 'MIN'].includes(rule)) {
      errors.push(`items.csv line ${line}: unknown lot rule ${rule}`);
      continue;
    }
    const lot = lotParameters(rule, parameter);
    if (!lot) {
      errors.push(`items.csv line ${line}: bad lot parameter ${parameter} for ${rule}`);
      continue;
    }
    items.set(id, {
      id,
      leadTime: Number(leadTime),
      lot,
      safety: Number(safety),
      onHand: Number(onHand),
      material: Number(material),
      labor: Number(labor),
      description,
      children: [],
      parents: [],
      routing: [],
      receipts: [],
      lowLevel: -1,
      cumulativeLead: -1,
    });
  }
  return items;
}
