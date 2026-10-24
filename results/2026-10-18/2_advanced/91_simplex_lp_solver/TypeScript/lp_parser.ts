import { readFileSync } from 'node:fs';
import { one, parseNumber } from './rational.ts';
import type { Rational } from './rational.ts';
import type {
  RawModel, RawObjective, RawConstraint, RawBound, ParseSettings, Term, Direction,
} from './types.ts';
const reserved = new Set(['bounds', 'integer', 'binary', 'free', 'inf']);

function fullMatch(pattern: RegExp, text: string | undefined): boolean {
  if (typeof text !== 'string') return false;
  const match = pattern.exec(text);
  return match !== null && match[0].length === text.length;
}

export function isName(text: string | undefined): boolean {
  return fullMatch(/^[a-z][a-z0-9_]*$/, text) && !reserved.has(text);
}

export function number(text: string | undefined, signed = false): Rational | null {
  if (typeof text !== 'string') return null;
  const unsigned = signed && text.startsWith('-') ? text.slice(1) : text;
  if (!fullMatch(/^[0-9]+(?:\.[0-9]+|\/[0-9]+)?$/, unsigned)) return null;
  if (unsigned.includes('/') && BigInt(unsigned.split('/')[1]) === 0n) return null;
  return parseNumber(text);
}

export function expression(items: string[]): Term[] | null {
  let index = 0;
  let sign = 1;
  if (items[index] === '-') {
    sign = -1;
    index++;
  }
  const terms: Term[] = [];
  while (true) {
    const coefficient = number(items[index]);
    if (coefficient !== null && isName(items[index + 1])) {
      terms.push({name: items[index + 1], coefficient: coefficient.multiply(sign)});
      index += 2;
    } else if (isName(items[index])) {
      terms.push({name: items[index], coefficient: one.multiply(sign)});
      index++;
    } else return null;
    if (index === items.length) return terms;
    if (items[index] !== '+' && items[index] !== '-') return null;
    sign = items[index++] === '-' ? -1 : 1;
  }
}

function label(text: string | undefined): string | null {
  return typeof text === 'string' && text.endsWith(':') && isName(text.slice(0, -1)) ? text.slice(0, -1) : null;
}

function objective(items: string[], line: number): RawObjective | null {
  const name = label(items[0]);
  if (items.length < 2 || name === null) return null;
  const terms = expression(items.slice(1));
  return terms === null ? null : {name, terms, line};
}

export function constraint(items: string[], line: number): RawConstraint | null {
  const name = label(items[0]);
  if (items.length < 4 || name === null || !['<=', '>=', '='].includes(items.at(-2)!)) return null;
  const rhs = number(items.at(-1), true);
  const terms = expression(items.slice(1, -2));
  return rhs === null || terms === null ? null : {name, terms, op: items.at(-2)!, rhs, line};
}

function limitValue(text: string | undefined, lower: boolean): {value: Rational | null} | null {
  if (text === (lower ? '-inf' : 'inf')) return {value: null};
  const value = number(text, true);
  return value === null ? null : {value};
}

export function bound(items: string[], line: number): RawBound | null {
  if (items.length === 2 && isName(items[0]) && items[1] === 'free') {
    return {name: items[0], kind: 'both', lower: null, upper: null, line};
  }
  if (items.length === 3 && isName(items[0])) {
    const [name, op, text] = items;
    if (op === '=') {
      const value = number(text, true);
      return value === null ? null : {name, kind: 'both', lower: value, upper: value, line};
    }
    if (op === '>=' || op === '<=') {
      const lower = op === '>=';
      const parsed = limitValue(text, lower);
      return parsed === null ? null : {name, kind: (lower ? 'lower' : 'upper') as 'lower'|'upper', value: parsed.value, line};
    }
  }
  if (items.length === 5 && items[1] === '<=' && items[3] === '<=' && isName(items[2])) {
    const lower = limitValue(items[0], true);
    const upper = limitValue(items[4], false);
    if (lower !== null && upper !== null) return {name: items[2], kind: 'both', lower: lower.value, upper: upper.value, line};
  }
  return null;
}

function parseModel(block: {name: string; body: {text: string; line: number}[]; endLine: number}): RawModel {
  const result: RawModel = {name: block.name, direction: 'maximize', objective: null,
    constraints: [], bounds: [], integers: [], binaries: [], error: null};
  let state = 'A';
  for (const {text, line} of block.body) {
    const items = text.split(' ');
    let accepted = false;
    if (state === 'A') {
      if (text === 'maximize' || text === 'minimize') {
        result.direction = text as Direction;
        state = 'B';
        accepted = true;
      }
    } else if (state === 'B') {
      result.objective = objective(items, line);
      if (result.objective !== null) {
        state = 'C';
        accepted = true;
      }
    } else if (state === 'C') {
      if (text === 'subject to') {
        state = 'D';
        accepted = true;
      }
    } else if (state === 'E' && text === 'bounds') {
      state = 'F';
      accepted = true;
    } else if (['E', 'F'].includes(state) && text === 'integer') {
      state = 'G';
      accepted = true;
    } else if (['E', 'F', 'G'].includes(state) && text === 'binary') {
      state = 'H';
      accepted = true;
    } else if (state === 'D' || state === 'E') {
      const parsed = constraint(items, line);
      if (parsed !== null) {
        result.constraints.push(parsed);
        state = 'E';
        accepted = true;
      }
    } else if (state === 'F') {
      const parsed = bound(items, line);
      if (parsed !== null) {
        result.bounds.push(parsed);
        accepted = true;
      }
    } else if ((state === 'G' || state === 'H') && items.every(isName)) {
      result[state === 'G' ? 'integers' : 'binaries'].push({names: items, line});
      accepted = true;
    }
    if (!accepted) {
      result.error = {line, message: 'syntax error'};
      return result;
    }
  }
  if (['A', 'B', 'C', 'D'].includes(state)) result.error = {line: block.endLine, message: 'syntax error'};
  return result;
}

export function readInputs(): {models: RawModel[]; settings: ParseSettings} {
  const lines = readFileSync('input/models.lp', 'ascii').slice(0, -1).split('\n');
  const models: RawModel[] = [];
  let block: {name: string; body: {text: string; line: number}[]; endLine: number} | null = null;
  for (let index = 0; index < lines.length; index++) {
    const text = lines[index];
    if (text === '' || text.startsWith('#')) continue;
    if (block === null) block = {name: text.split(' ')[1], body: [], endLine: 0};
    else if (text === 'end') {
      block.endLine = index + 1;
      models.push(parseModel(block));
      block = null;
    } else block.body.push({text, line: index + 1});
  }
  const settings: ParseSettings = {logs: new Map<string, number>(), limits: new Map<string, number>(), log_level: 0, node_limit: 0};
  for (const line of readFileSync('input/params.txt', 'ascii').slice(0, -1).split('\n')) {
    const [kind, first, second] = line.split(' ');
    if (kind === 'log') settings.logs.set(first, Number(second));
    else if (kind === 'limit') settings.limits.set(first, Number(second));
    else if (kind === 'log_level') settings.log_level = Number(first);
    else if (kind === 'node_limit') settings.node_limit = Number(first);
  }
  return {models, settings};
}

