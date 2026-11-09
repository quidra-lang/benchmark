import type { Column, Options, Input, Cell } from './types.ts';

import * as fs from 'node:fs';

function leap(year: number): boolean {
  return year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
}

function monthLengths(year: number): number[] {
  return [31, leap(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
}

function beforeYear(year: number): number {
  const previous = year - 1;
  return 365 * previous + Math.floor(previous / 4) - Math.floor(previous / 100) + Math.floor(previous / 400);
}

export function dayNumber(text: string): number {
  const [year, month, day] = text.split('-').map(Number);
  let result = beforeYear(year) - beforeYear(1970) + day - 1;
  const lengths = monthLengths(year);
  for (let index = 0; index < month - 1; index++) result += lengths[index];
  return result;
}

export function dateText(value: number): string {
  let year = 1970;
  while (value < 0) {
    year--;
    value += leap(year) ? 366 : 365;
  }
  while (value >= (leap(year) ? 366 : 365)) {
    value -= leap(year) ? 366 : 365;
    year++;
  }
  const lengths = monthLengths(year);
  let month = 0;
  while (value >= lengths[month]) value -= lengths[month++];
  return `${String(year).padStart(4, '0')}-${String(month + 1).padStart(2, '0')}-${String(value + 1).padStart(2, '0')}`;
}

export function convert(text: string, type: string): Cell {
  if (text === '') return null;
  if (type === 'DATE') return dayNumber(text);
  if (type === 'INT') return Number(text);
  if (type === 'BOOL') return text === 'true';
  return text;
}

export function valueText(value: any, type: string, recovered: boolean = false): string {
  if (value === null) return recovered ? '' : 'NULL';
  return type === 'DATE' ? dateText(value) : String(value);
}

export function readInputs(): Input {
  const lines = (name: string): string[] => fs.readFileSync('input/' + name, 'ascii').slice(0, -1).split('\n');
  const schema = lines('schema.txt').map((line, number) => {
    const [name, type, nullability] = line.split(' ');
    return {name, type, nullable: nullability === 'NULLABLE', number};
  });
  const table = lines('table.csv').slice(1).map(line =>
    line.split(',').map((field, index) => convert(field, schema[index].type)));
  const options: Partial<Options> = {encodings: new Map<string, string>()};
  for (const line of lines('options.txt')) {
    const fields = line.split(' ');
    if (fields[0] === 'encoding') options.encodings.set(fields[1], fields[2]);
    else options[fields[0]] = Number(fields[1]);
  }
  return {schema, table, options: options as Options, queries: lines('queries.txt'),
    damaged: Buffer.from(lines('damaged.hex').join(''), 'hex')};
}

export function writeFiles(files: Record<string, string[]>): void {
  fs.mkdirSync('output', {recursive: true});
  for (const [name, lines] of Object.entries(files)) {
    fs.writeFileSync('output/' + name, lines.join('\n') + (lines.length ? '\n' : ''), 'ascii');
  }
}

