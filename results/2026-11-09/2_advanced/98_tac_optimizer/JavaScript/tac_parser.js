'use strict';

const fs = require('node:fs');
const KINDS = ['copy', 'bin', 'load', 'store', 'goto', 'if', 'param', 'call', 'return', 'read', 'print'];
const variable = operand => typeof operand === 'string';
const operand = word => /^[-0-9]/.test(word) ? Number(word) : word;
const copy = instruction => ({ ...instruction });

function parseInstruction(words) {
  const [first, second] = words;
  if (first === 'goto') return { kind: 'goto', target: second };
  if (first === 'if') return { kind: 'if', a: operand(second), op: words[2], b: operand(words[3]), target: words[5] };
  if (first === 'param' || first === 'print') return { kind: first, a: operand(second) };
  if (first === 'return') return second === undefined ? { kind: first } : { kind: first, a: operand(second) };
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

function readProgram() {
  const program = { arrays: [], functions: [] };
  let current = null;
  for (const line of fs.readFileSync('input/program.tac', 'ascii').split('\n')) {
    const words = line.trim().split(/ +/);
    if (words[0] === '' || words[0].startsWith('#')) continue;
    if (words[0] === 'array') program.arrays.push({ name: words[1], size: Number(words[2]) });
    else if (words[0] === 'func') {
      current = { name: words[1], parameters: words.slice(2), code: [], temporary: 0, preheader: 0 };
      program.functions.push(current);
    } else if (words[0] === 'end') current = null;
    else current.code.push(words.length === 1 && words[0].endsWith(':') ?
      { kind: 'label', name: words[0].slice(0, -1) } : parseInstruction(words));
  }
  return program;
}

function definition(instruction) { return instruction.dest; }
function operandSlots(instruction) {
  if (['bin', 'if', 'store'].includes(instruction.kind)) return ['a', 'b'];
  if (['copy', 'load', 'param', 'print', 'return'].includes(instruction.kind) && instruction.a !== undefined) return ['a'];
  return [];
}
function uses(instruction) { return operandSlots(instruction).map(slot => instruction[slot]).filter(variable); }
function expression(instruction) {
  if (instruction.kind === 'bin') return { kind: 'bin', op: instruction.op, a: instruction.a, b: instruction.b };
  if (instruction.kind === 'load') return { kind: 'load', array: instruction.array, a: instruction.a };
  return null;
}
function expressionKey(instruction) {
  const value = expression(instruction);
  return value === null ? null : JSON.stringify(value);
}
function expressionText(value) { return value.kind === 'load' ? value.array + '[' + value.a + ']' : '' + value.a + value.op + value.b; }

function operation(operator, a, b) {
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
}

function instructionText(instruction) {
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

function functionLines(fn) {
  return ['func ' + [fn.name, ...fn.parameters].join(' '),
    ...fn.code.map(s => (s.kind === 'label' ? '' : '    ') + instructionText(s)), 'end'];
}
function programLines(program) {
  const sections = [];
  if (program.arrays.length) sections.push(program.arrays.map(a => 'array ' + a.name + ' ' + a.size));
  sections.push(...program.functions.map(functionLines));
  return sections.flatMap((section, index) => index === 0 ? section : ['', ...section]);
}
function cloneProgram(program) {
  return { arrays: program.arrays.map(a => ({ ...a })), functions: program.functions.map(f =>
    ({ ...f, parameters: f.parameters.slice(), code: f.code.map(copy) })) };
}

module.exports = { KINDS, variable, copy, readProgram, definition, operandSlots, uses,
  expression, expressionKey, expressionText, operation, instructionText, functionLines, programLines, cloneProgram };
