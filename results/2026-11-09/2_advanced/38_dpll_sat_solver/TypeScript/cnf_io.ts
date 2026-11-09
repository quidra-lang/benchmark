import { readFileSync } from 'node:fs';

export interface Formula {
  variables: number;
  clauses: number[][];
}
export type Model = boolean[];
export class InputError extends Error {}
export const wellFormedNumber = (text: string): boolean => /^(?:0|[1-9][0-9]{0,5})$/.test(text);

export function readDimacs(filename: string): Formula {
  const clauses: number[][] = [];
  let header: { variables: number; count: number } | undefined;
  let pending: number[] = [];
  const lines = readFileSync(filename, 'ascii').split('\n');
  for (let index = 0; index < lines.length; index++) {
    const line = lines[index];
    const n = index + 1;
    if (line.startsWith('c') || line.trim() === '') continue;
    const tokens = line.trim().split(/ +/);
    if (tokens[0] === 'p') {
      if (header !== undefined) throw new InputError(`duplicate header at line ${n}`);
      if (
        tokens.length !== 4 ||
        tokens[1] !== 'cnf' ||
        !wellFormedNumber(tokens[2]) ||
        !wellFormedNumber(tokens[3])
      ) {
        throw new InputError(`bad header at line ${n}`);
      }
      header = { variables: Number(tokens[2]), count: Number(tokens[3]) };
      continue;
    }
    if (header === undefined) throw new InputError('missing header');
    for (const token of tokens) {
      if (!/^(?:0|-?[1-9][0-9]{0,5})$/.test(token)) {
        throw new InputError(`bad token ${token} at line ${n}`);
      }
      const literal = Number(token);
      if (Math.abs(literal) > header.variables) {
        throw new InputError(`literal out of range ${token} at line ${n}`);
      }
      if (literal === 0) {
        clauses.push(pending);
        pending = [];
      } else pending.push(literal);
    }
  }
  if (header === undefined) throw new InputError('missing header');
  if (pending.length > 0) throw new InputError('unterminated clause');
  if (clauses.length !== header.count) {
    throw new InputError(`clause count mismatch header=${header.count} found=${clauses.length}`);
  }
  return { variables: header.variables, clauses };
}
export function modelLines(model: Model): string[] {
  const tokens: number[] = [];
  for (let x = 1; x < model.length; x++) tokens.push(model[x] ? x : -x);
  tokens.push(0);
  const lines: string[] = [];
  for (let i = 0; i < tokens.length; i += 10) lines.push('v ' + tokens.slice(i, i + 10).join(' '));
  return lines;
}
