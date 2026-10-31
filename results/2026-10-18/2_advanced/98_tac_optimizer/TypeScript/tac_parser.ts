import { readFileSync } from 'node:fs';
import type { Operand, OperandSlot, Instruction, Expression, TACProgram, TACFunction } from './types.ts';
export const KINDS = ['copy', 'bin', 'load', 'store', 'goto', 'if', 'param', 'call', 'return', 'read', 'print'];
export const variable = (operand: Operand | undefined): operand is string => typeof operand === 'string';
const operand = (word: string): Operand => /^[-0-9]/.test(word) ? Number(word) : word;
export const copy = (instruction: Instruction): Instruction => ({...instruction});

function parseInstruction(words: string[]): Instruction {
  const [first, second] = words;
  if (first === 'goto') return { kind: 'goto', target: second };
  if (first === 'if') return { kind: 'if', a: operand(second), op: words[2], b: operand(words[3]), target: words[5] };
  if (first === 'param' || first === 'print') return {kind: first as 'param' | 'print', a: operand(second)};
  if (first === 'return') return second === undefined ? {kind: 'return'} : {kind: 'return', a: operand(second)};
  if (first === 'read') return { kind: 'read', dest: second };
  if (first === 'call') return { kind: 'call', name: second, count: Number(words[2]) };
  if (first.includes('[')) {
    const bracket = first.indexOf('[');
    return { kind: 'store', array: first.slice(0, bracket), a: operand(first.slice(bracket + 1, -1)), b: operand(words[2]) };
  }
  const dest = first, source = words[2];
  if (source === 'call') return { kind: 'call', dest, name: words[3], count: Number(words[4]) };
  if (words.length === 5) return { kind: 'bin', dest, a: operand(source), op: words[3], b: operand(words[4]) };
  if (source.includes('[')) {
    const bracket = source.indexOf('[');
    return { kind: 'load', dest, array: source.slice(0, bracket), a: operand(source.slice(bracket + 1, -1)) };
  }
  return { kind: 'copy', dest, a: operand(source) };
}

export function readProgram(): TACProgram {
  const program: TACProgram = {arrays: [], functions: []};
  let current: TACFunction | null = null;
  for (const line of readFileSync('input/program.tac', 'ascii').split('\n')) {
    const words = line.trim().split(/ +/);
    if (words[0] === '' || words[0].startsWith('#')) continue;
    if (words[0] === 'array') program.arrays.push({ name: words[1], size: Number(words[2]) });
    else if (words[0] === 'func') {
      current = { name: words[1], parameters: words.slice(2), code: [], temporary: 0, preheader: 0 };
      program.functions.push(current);
    } else if (words[0] === 'end') current = null;
    else current!.code.push(words.length === 1 && words[0].endsWith(':') ?
      { kind: 'label', name: words[0].slice(0, -1) } : parseInstruction(words));
  }
  return program;
}

export function definition(instruction: Instruction): string | undefined { return instruction.dest; }
export function operandSlots(instruction: Instruction): OperandSlot[] {
  if (['bin', 'if', 'store'].includes(instruction.kind)) return ['a', 'b'];
  if (['copy', 'load', 'param', 'print', 'return'].includes(instruction.kind) && instruction.a !== undefined) return ['a'];
  return [];
}
export function uses(instruction: Instruction): string[] { return operandSlots(instruction).map(slot => instruction[slot]).filter(variable); }
export function expression(instruction: Instruction): Expression | null {
  if (instruction.kind === 'bin') return {kind: 'bin', op: instruction.op!, a: instruction.a!, b: instruction.b!};
  if (instruction.kind === 'load') return {kind: 'load', array: instruction.array!, a: instruction.a!};
  return null;
}
export function expressionKey(instruction: Instruction): string | null {
  const value = expression(instruction);
  return value === null ? null : JSON.stringify(value);
}
export function expressionText(value: Expression): string { return value.kind === 'load' ? value.array + '[' + value.a + ']' : '' + value.a + value.op + value.b; }

export function operation(operator: string, a: number, b: number): number {
  switch (operator) {
    case '+': return a + b;
    case '-': return a - b;
    case '*': return a * b;
    case '/': return Math.trunc(a / b);
    case '%': return a % b;
    case '<': return Number(a < b);
    case '<=': return Number(a <= b);
    case '>': return Number(a > b);
    case '>=': return Number(a >= b);
    case '==': return Number(a === b);
    case '!=': return Number(a !== b);
  }
  throw new Error('unknown operation: ' + operator);
}

export function instructionText(instruction: Instruction): string {
  const s = instruction;
  switch (s.kind) {
    case 'label': return s.name + ':';
    case 'copy': return s.dest + ' = ' + s.a;
    case 'bin': return s.dest + ' = ' + s.a + ' ' + s.op + ' ' + s.b;
    case 'load': return s.dest + ' = ' + s.array + '[' + s.a + ']';
    case 'store': return s.array + '[' + s.a + '] = ' + s.b;
    case 'goto': return 'goto ' + s.target;
    case 'if': return 'if ' + s.a + ' ' + s.op + ' ' + s.b + ' goto ' + s.target;
    case 'param': case 'print': return s.kind + ' ' + s.a;
    case 'call': return (s.dest === undefined ? '' : s.dest + ' = ') + 'call ' + s.name + ' ' + s.count;
    case 'return': return s.a === undefined ? 'return' : 'return ' + s.a;
    case 'read': return 'read ' + s.dest;
  }
}

export function functionLines(fn: TACFunction): string[] {
  return ['func ' + [fn.name, ...fn.parameters].join(' '),
    ...fn.code.map(s => (s.kind === 'label' ? '' : '    ') + instructionText(s)), 'end'];
}
export function programLines(program: TACProgram): string[] {
  const sections: string[][] = [];
  if (program.arrays.length) sections.push(program.arrays.map(a => 'array ' + a.name + ' ' + a.size));
  sections.push(...program.functions.map(functionLines));
  return sections.flatMap((section, index) => index === 0 ? section : ['', ...section]);
}
export function cloneProgram(program: TACProgram): TACProgram {
  return { arrays: program.arrays.map(a => ({ ...a })), functions: program.functions.map(f =>
    ({ ...f, parameters: f.parameters.slice(), code: f.code.map(copy) })) };
}

