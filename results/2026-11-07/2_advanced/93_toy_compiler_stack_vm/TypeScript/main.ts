import * as fs from 'node:fs';
import { CompileError, positionCompare, lex } from './lexer.ts';
import { Parser, statementChildren, resolve } from './parser.ts';
import { Semantic, canComplete, isArray } from './semantic.ts';
import { generate } from './codegen.ts';
import { run } from './vm.ts';

const RULES = ['const-jump', 'not-compare', 'not-jump', 'invert-branch', 'thread', 'jump-next', 'unreachable'];
const JUMPS = new Set(['JUMP', 'JUMPF', 'JUMPT']), CONDITIONAL = new Set(['JUMPF', 'JUMPT']);
const TRANSFERS = new Set(['JUMP', 'RET', 'RETV', 'HALT']);
const NEGATIONS = { LT: 'GE', GE: 'LT', LE: 'GT', GT: 'LE', EQ: 'NE', NE: 'EQ' };
const inverse = op => op === 'JUMPF' ? 'JUMPT' : 'JUMPF';
const jumpsOn = (op, value) => op === 'JUMPF' ? value === 0 : value !== 0;
const asciiCompare = (a, b) => a < b ? -1 : a > b ? 1 : 0;
const positionText = position => position.line + ':' + position.column;
const spelling = instruction => instruction.op + instruction.args.map(value => ' ' + value).join('');

function readInputs() {
  const source = fs.readFileSync('input/program.src', 'ascii').split('\n').slice(0, -1), programs = [], byName = new Map();
  let current;
  source.forEach((text, index) => {
    if (text.startsWith('#program ')) {
      current = { name: text.slice(9), lines: [], input: [] }; programs.push(current); byName.set(current.name, current);
    } else current.lines.push({ text, line: index + 1 });
  });
  for (const text of fs.readFileSync('input/input.txt', 'ascii').split('\n').slice(0, -1)) {
    if (text.startsWith('#input ')) current = byName.get(text.slice(7));
    else current.input.push(...text.split(' ').map(Number));
  }
  return { programs, source };
}

function reachableFrom(start) {
  const reached = new Set(), pending = [start];
  while (pending.length) {
    const declaration = pending.pop();
    if (reached.has(declaration)) continue;
    reached.add(declaration); pending.push(...declaration.calls);
  }
  return reached;
}

function warnings(analysis, reachable) {
  const result = [];
  for (const variable of analysis.variables) if (variable.reads === 0) {
    const kind = variable.kind === 'parameter' ? 'parameter' : 'variable';
    result.push({ position: variable.namePosition, message: `unused ${kind} '${variable.name}'` });
  }
  for (const declaration of analysis.functions) {
    const pending = [declaration.body];
    while (pending.length) {
      const statement = pending.pop();
      if (statement.kind === 'block') {
        const first = statement.statements.findIndex(child => !canComplete(child));
        if (first >= 0 && first + 1 < statement.statements.length) result.push({ position: statement.statements[first + 1].position, message: 'unreachable statement' });
      }
      const children = statementChildren(statement);
      for (let i = children.length - 1; i >= 0; i--) pending.push(children[i]);
    }
    if (!reachable.has(declaration)) result.push({ position: declaration.namePosition, message: `function '${declaration.name}' is never called` });
  }
  return result.sort((a, b) => positionCompare(a.position, b.position));
}

class Folder {
  declare count: any;
  constructor() { this.count = 0; }
  literal(node, value) { this.count++; return { kind: 'literal', type: node.type, value: value === 0 ? 0 : value, position: node.position }; }
  value(operator, a, b) {
    let result;
    switch (operator) {
      case '+': result = a + b; break;
      case '-': result = a - b; break;
      case '*': result = a * b; break;
      case '/': if (b === 0) return null; result = Math.trunc(a / b); break;
      case '%': if (b === 0) return null; result = a % b; break;
      case '<': return Number(a < b);
      case '<=': return Number(a <= b);
      case '>': return Number(a > b);
      case '>=': return Number(a >= b);
      case '==': return Number(a === b);
      case '!=': return Number(a !== b);
      case '&&': return Number(a !== 0 && b !== 0);
      case '||': return Number(a !== 0 || b !== 0);
    }
    return result >= -2147483648 && result <= 2147483647 ? result : null;
  }
  expression(node) { return resolve(this.foldExpression(node)); }
  *foldExpression(node) {
    if (node.kind === 'index') node.index = yield this.foldExpression(node.index);
    else if (node.kind === 'call') {
      for (let i = 0; i < node.args.length; i++) node.args[i] = yield this.foldExpression(node.args[i]);
    }
    else if (node.kind === 'unary') {
      node.operand = yield this.foldExpression(node.operand);
      if (node.operand.kind === 'literal') {
        const value = node.operator === '-' ? -node.operand.value : Number(node.operand.value === 0);
        if (value >= -2147483648 && value <= 2147483647) return this.literal(node, value);
      }
    } else if (node.kind === 'binary') {
      node.left = yield this.foldExpression(node.left); node.right = yield this.foldExpression(node.right);
      const left = node.left, right = node.right, op = node.operator;
      if (left.kind === 'literal' && right.kind === 'literal') {
        const value = this.value(op, left.value, right.value);
        if (value !== null) return this.literal(node, value);
      }
      if (left.kind === 'literal') {
        if ((op === '&&' && left.value === 0) || (op === '||' && left.value === 1)) return this.literal(node, left.value);
        if ((op === '&&' && left.value === 1) || (op === '||' && left.value === 0)
            || (op === '+' && left.value === 0) || (op === '*' && left.value === 1)) { this.count++; return right; }
      }
      if (right.kind === 'literal' && ((['+', '-', '||'].includes(op) && right.value === 0)
          || (['*', '/', '&&'].includes(op) && right.value === 1))) { this.count++; return left; }
    }
    return node;
  }
  statement(node) { return resolve(this.foldStatement(node)); }
  *foldStatement(node) {
    switch (node.kind) {
      case 'block':
        for (let i = 0; i < node.statements.length; i++) node.statements[i] = yield this.foldStatement(node.statements[i]);
        break;
      case 'declaration': if (node.initializer !== null) node.initializer = this.expression(node.initializer); break;
      case 'assignment':
        if (node.index !== null) node.index = this.expression(node.index);
        node.value = this.expression(node.value); break;
      case 'call-statement': node.expression = this.expression(node.expression); break;
      case 'print': node.values = node.values.map(value => this.expression(value)); break;
      case 'return': if (node.value !== null) node.value = this.expression(node.value); break;
      case 'if':
        node.condition = this.expression(node.condition);
        if (node.condition.kind === 'literal') {
          const chosen = node.condition.value !== 0 ? node.then : node.otherwise;
          const replacement = chosen === null ? { kind: 'empty', position: node.position } : (yield this.foldStatement(chosen));
          this.count++; return replacement;
        }
        node.then = yield this.foldStatement(node.then); if (node.otherwise !== null) node.otherwise = yield this.foldStatement(node.otherwise); break;
      case 'while':
        node.condition = this.expression(node.condition);
        if (node.condition.kind === 'literal' && node.condition.value === 0) { this.count++; return { kind: 'empty', position: node.position }; }
        node.body = yield this.foldStatement(node.body); break;
      case 'for':
        if (node.initialization !== null) node.initialization = yield this.foldStatement(node.initialization);
        if (node.condition !== null) node.condition = this.expression(node.condition);
        if (node.update !== null) node.update = yield this.foldStatement(node.update);
        node.body = yield this.foldStatement(node.body); break;
    }
    return node;
  }
}

function erase(code, index) {
  code.splice(index, 1);
  for (const instruction of code) if (JUMPS.has(instruction.op) && instruction.args[0] > index) instruction.args[0]--;
}

function applyRule(code, i, targets) {
  const a = code[i], b = code[i + 1], free = b !== undefined && !targets.has(i + 1);
  if (a.op === 'PUSH' && free && CONDITIONAL.has(b.op)) {
    if (jumpsOn(b.op, a.args[0])) {
      code[i] = { ...a, op: 'JUMP', args: [b.args[0]], position: b.position }; erase(code, i + 1);
    } else { erase(code, i + 1); erase(code, i); }
    return 0;
  }
  if (Object.hasOwn(NEGATIONS, a.op) && free && b.op === 'NOT') { a.op = NEGATIONS[a.op]; erase(code, i + 1); return 1; }
  if (a.op === 'NOT' && free && CONDITIONAL.has(b.op)) {
    code[i] = { ...a, op: inverse(b.op), args: [b.args[0]], position: b.position }; erase(code, i + 1); return 2;
  }
  if (CONDITIONAL.has(a.op) && a.args[0] === i + 2 && free && b.op === 'JUMP') {
    code[i] = { ...a, op: inverse(a.op), args: [b.args[0]] }; erase(code, i + 1); return 3;
  }
  if (JUMPS.has(a.op) && a.args[0] < code.length) {
    const target = a.args[0], instruction = code[target];
    let next = null;
    if (instruction.op === 'JUMP') next = instruction.args[0];
    else if (instruction.op === 'PUSH' && target + 1 < code.length && CONDITIONAL.has(code[target + 1].op)) {
      next = jumpsOn(code[target + 1].op, instruction.args[0]) ? code[target + 1].args[0] : target + 2;
    }
    if (next !== null && next !== target) { a.args[0] = next; return 4; }
  }
  if (JUMPS.has(a.op) && a.args[0] === i + 1) {
    if (a.op === 'JUMP') erase(code, i); else { a.op = 'POP'; a.args = []; }
    return 5;
  }
  if (TRANSFERS.has(a.op) && free) { erase(code, i + 1); return 6; }
  return -1;
}

function peephole(code, counts) {
  while (true) {
    const targets = new Set(code.filter(instruction => JUMPS.has(instruction.op)).map(instruction => instruction.args[0]));
    let applied = false;
    for (let i = 0; i < code.length; i++) {
      const rule = applyRule(code, i, targets);
      if (rule >= 0) { counts[rule]++; applied = true; break; }
    }
    if (!applied) return;
  }
}

function arrange(units) {
  let address = 0;
  const starts = new Map();
  for (const unit of units) { unit.start = address; starts.set(unit.name, address); address += unit.code.length; }
  const result = [];
  for (const unit of units) for (const instruction of unit.code) {
    const args = instruction.args.slice();
    if (JUMPS.has(instruction.op)) args[0] += unit.start;
    if (instruction.op === 'CALL') args[0] = starts.get(instruction.callee);
    result.push({ ...instruction, args, address: result.length, unit });
  }
  return result;
}

function successors(code, index) {
  const instruction = code[index], result = [];
  if (!TRANSFERS.has(instruction.op) && index + 1 < code.length) result.push(index + 1);
  if (JUMPS.has(instruction.op) && instruction.args[0] < code.length && !result.includes(instruction.args[0])) result.push(instruction.args[0]);
  return result;
}

function stackEffect(instruction, analysis) {
  const { op, args } = instruction;
  if (['PUSH', 'LOADG', 'LOADL', 'READ'].includes(op)) return 1;
  if (['POP', 'STOREG', 'STOREL', 'JUMPF', 'JUMPT', 'RETV', 'ADD', 'SUB', 'MUL', 'DIV', 'MOD'].includes(op) || Object.hasOwn(NEGATIONS, op)) return -1;
  if (op === 'STOREA') return -2;
  if (op === 'PRINT') return -args[0];
  if (op === 'CALL') return -args[1] + Number(analysis.names.get(instruction.callee).type !== 'void');
  return 0;
}

function analyzeUnit(unit, analysis) {
  const code = unit.code, leaders = new Set([0]);
  code.forEach((instruction, i) => {
    if (JUMPS.has(instruction.op) && instruction.args[0] < code.length) leaders.add(instruction.args[0]);
    if ((JUMPS.has(instruction.op) || TRANSFERS.has(instruction.op)) && i + 1 < code.length) leaders.add(i + 1);
  });
  const starts = Array.from(leaders).sort((a, b) => a - b), membership = Array(code.length);
  unit.blocks = starts.map((start, i) => ({ start, end: i + 1 < starts.length ? starts[i + 1] - 1 : code.length - 1, successors: [] }));
  unit.blocks.forEach((block, i) => { for (let j = block.start; j <= block.end; j++) membership[j] = i; });
  for (const block of unit.blocks) block.successors = Array.from(new Set(successors(code, block.end).map(index => membership[index])));
  const depths = Array(code.length).fill(null), queue = [0]; depths[0] = 0; unit.stack = 0;
  for (let front = 0; front < queue.length; front++) {
    const index = queue[front], nextDepth = depths[index] + stackEffect(code[index], analysis);
    unit.stack = Math.max(unit.stack, nextDepth);
    for (const next of successors(code, index)) if (depths[next] === null) { depths[next] = nextDepth; queue.push(next); }
  }
}

function compile(program) {
  try { program.analysis = new Semantic(new Parser(lex(program.lines)).parse()).analyze(); }
  catch (error) { if (!(error instanceof CompileError)) throw error; program.error = error; return; }
  const analysis = program.analysis, reachable = reachableFrom(analysis.names.get('main'));
  program.warnings = warnings(analysis, reachable);
  program.recursive = new Set(analysis.functions.filter(declaration => Array.from(declaration.calls).some(callee => reachableFrom(callee).has(declaration))));
  const functions = analysis.functions.filter(declaration => reachable.has(declaration)), folder = new Folder();
  for (const variable of analysis.globals) if (variable.initializer !== null) variable.initializer = folder.expression(variable.initializer);
  for (const declaration of functions) declaration.body = folder.statement(declaration.body);
  program.folds = folder.count;
  const generated = generate(analysis, functions);
  program.beforeUnits = generated.units; program.before = arrange(program.beforeUnits);
  program.afterUnits = program.beforeUnits.map(unit => ({ ...unit, code: unit.code.map(instruction => ({ ...instruction, args: instruction.args.slice() })) }));
  program.peephole = Array(RULES.length).fill(0);
  for (const unit of program.afterUnits) peephole(unit.code, program.peephole);
  program.after = arrange(program.afterUnits);
  for (const unit of program.afterUnits) analyzeUnit(unit, analysis);
  program.mainRun = run(program.after, generated.globalSize, program.input);
  program.comparisonRun = run(program.before, generated.globalSize, program.input);
}

function disassembly(lines, label, units, code) {
  lines.push(`${label}: ${code.length} instructions`);
  for (const unit of units) {
    lines.push(unit.name + ':');
    for (let address = unit.start; address < unit.start + unit.code.length; address++) lines.push(String(address).padStart(5, ' ') + '  ' + spelling(code[address]));
  }
}

function listing(program) {
  const analysis = program.analysis, lines = [];
  if (analysis.globals.length === 0) lines.push('globals: none');
  else {
    lines.push('globals:');
    for (const variable of analysis.globals) lines.push(`  ${variable.address} ${variable.name} ${isArray(variable) ? 'int[' + variable.size + ']' : variable.type}`);
  }
  lines.push('functions:');
  program.afterUnits.forEach((unit, index) => {
    const before = program.beforeUnits[index], declaration = unit.declaration;
    const signature = declaration === null ? '' : ' ' + declaration.type + '(' + declaration.params.map(parameter => parameter.type).join(',') + ')';
    const callees = declaration === null ? 'main' : Array.from(declaration.calls, callee => callee.name).sort(asciiCompare).join(',') || '-';
    lines.push(`  ${unit.name}${signature} address=${before.start}->${unit.start} size=${before.code.length}->${unit.code.length} slots=${unit.slots.length} stack=${unit.stack} blocks=${unit.blocks.length} calls=${callees}`
      + (program.recursive.has(declaration) ? ' recursive' : ''));
    unit.slots.forEach((variable, slot) => lines.push(`    slot ${slot} ${variable.name} ${variable.type}`));
  });
  lines.push('references:');
  for (const declaration of analysis.globals.concat(analysis.functions)) {
    const used = Array.from(new Set(declaration.references.map(position => position.line))).sort((a, b) => a - b);
    lines.push(`  ${declaration.name} defined ${declaration.namePosition.line} used ${used.length ? used.join(' ') : '-'}`);
  }
  disassembly(lines, 'before peephole', program.beforeUnits, program.before);
  disassembly(lines, 'after peephole', program.afterUnits, program.after);
  lines.push('control flow:');
  for (const unit of program.afterUnits) {
    lines.push('  ' + unit.name);
    unit.blocks.forEach((block, i) => lines.push(`    B${i} ${unit.start + block.start}-${unit.start + block.end}`
      + (block.successors.length ? ' -> ' + block.successors.map(next => 'B' + next).join(' ') : '')));
  }
  return lines;
}

function positionDisplay(position, source) {
  return ['  ' + source[position.line - 1], ' '.repeat(position.column + 1) + '^'];
}

function diagnostics(program, source) {
  if (program.error) return [`${program.error.kind} error ${positionText(program.error.position)}: ${program.error.message}`,
    ...positionDisplay(program.error.position, source), 'status: compile error'];
  const lines = program.warnings.map(warning => `warning ${positionText(warning.position)}: ${warning.message}`), result = program.mainRun;
  if (result.error !== null) {
    const { instruction, message } = result.error;
    lines.push(`runtime error ${positionText(instruction.position)}: ${message} in ${instruction.unit.name}`, ...positionDisplay(instruction.position, source));
    const callers = result.frames.slice(1).reverse();
    for (const frame of callers.slice(0, 5)) {
      const call = program.after[frame.returnAddress - 1]; lines.push(`  called from ${call.unit.name} at ${positionText(call.position)}`);
    }
    if (callers.length > 5) lines.push(`  ... ${callers.length - 5} more`);
  }
  lines.push(result.error === null ? 'status: ok' : 'status: runtime error');
  return lines;
}

function ruleLines(counts) { return RULES.map((rule, i) => '  ' + rule + ' ' + counts[i]); }

function statistics(program) {
  const result = program.mainRun, comparison = program.comparisonRun;
  const same = JSON.stringify(result.output) === JSON.stringify(comparison.output) && result.error?.message === comparison.error?.message;
  const lines = [`code: ${program.before.length} -> ${program.after.length}`, `folds: ${program.folds}`,
    `peephole: ${program.peephole.reduce((sum, count) => sum + count, 0)}`, ...ruleLines(program.peephole),
    `executed: ${result.executed}`, `executed before peephole: ${comparison.executed}`, `behaviour: ${same ? 'same' : 'different'}`,
    `max call depth: ${result.maxDepth}`, `max stack: ${result.maxStack}`, 'opcodes:'];
  const opcodes = new Map(), lineCounts = new Map();
  program.after.forEach((instruction, address) => {
    const count = result.counts[address], line = instruction.position.line;
    opcodes.set(instruction.op, (opcodes.get(instruction.op) || 0) + count); lineCounts.set(line, (lineCounts.get(line) || 0) + count);
  });
  for (const [opcode, count] of Array.from(opcodes).filter(([, count]) => count > 0).sort((a, b) => b[1] - a[1] || asciiCompare(a[0], b[0]))) lines.push(`  ${opcode} ${count}`);
  lines.push('functions:');
  const functions = program.afterUnits.slice(1).map(unit => ({ unit, executed: result.counts.slice(unit.start, unit.start + unit.code.length).reduce((sum, count) => sum + count, 0) }));
  functions.sort((a, b) => b.executed - a.executed || asciiCompare(a.unit.name, b.unit.name));
  for (const entry of functions) lines.push(`  ${entry.unit.name} calls=${result.calls.get(entry.unit.name) || 0} executed=${entry.executed}`);
  lines.push('calls:');
  const pairs = Array.from(result.pairs.values()).sort((a, b) => b.count - a.count || asciiCompare(a.from, b.from) || asciiCompare(a.to, b.to));
  for (const pair of pairs) lines.push(`  ${pair.from} -> ${pair.to} ${pair.count}`);
  lines.push('hot lines:');
  const executedLines = Array.from(lineCounts).filter(([, count]) => count > 0).sort((a, b) => b[1] - a[1] || a[0] - b[0]);
  for (const [line, count] of executedLines.slice(0, 5)) lines.push(`  line ${line}: ${count}`);
  const unexecuted = Array.from(lineCounts).filter(([, count]) => count === 0).map(([line]) => line).sort((a, b) => a - b);
  lines.push(`coverage: ${executedLines.length} of ${lineCounts.size} lines`, 'not executed: ' + (unexecuted.length ? unexecuted.join(' ') : 'none'), 'hot spots:');
  const hot = program.after.filter(instruction => result.counts[instruction.address] > 0)
    .sort((a, b) => result.counts[b.address] - result.counts[a.address] || a.address - b.address);
  for (const instruction of hot.slice(0, 5)) lines.push(`  pc=${instruction.address} count=${result.counts[instruction.address]} ${spelling(instruction)}`);
  return lines;
}

function summary(programs) {
  const compiled = programs.filter(program => !program.error), errors = { lexical: 0, syntax: 0, semantic: 0 }, counts = Array(RULES.length).fill(0);
  let folds = 0, executed = 0, runtimeErrors = 0;
  for (const program of programs) {
    if (program.error) { errors[program.error.kind]++; continue; }
    folds += program.folds; executed += program.mainRun.executed; if (program.mainRun.error !== null) runtimeErrors++;
    program.peephole.forEach((count, i) => { counts[i] += count; });
  }
  const lines = ['== summary ==', `programs: ${programs.length}`, `compiled: ${compiled.length}`,
    `compile errors: lexical ${errors.lexical} syntax ${errors.syntax} semantic ${errors.semantic}`, `runtime errors: ${runtimeErrors}`,
    `folds: ${folds}`, `peephole: ${counts.reduce((sum, count) => sum + count, 0)}`, ...ruleLines(counts), `executed: ${executed}`];
  const table = [['program', 'status', 'code', 'executed', 'output']];
  for (const program of programs) table.push(program.error ? [program.name, program.error.kind + ' error', '-', '-', '-']
    : [program.name, program.mainRun.error === null ? 'ok' : 'runtime error', String(program.after.length), String(program.mainRun.executed), String(program.mainRun.output.length)]);
  const widths = table[0].map((value, column) => Math.max(...table.map(row => row[column].length)));
  for (const row of table) lines.push('  ' + row.map((value, i) => i < 2 ? value.padEnd(widths[i], ' ') : value.padStart(widths[i], ' ')).join('  '));
  return lines;
}

function main() {
  const { programs, source } = readInputs(), files = { 'listing.txt': [], 'output.txt': [], 'diagnostics.txt': [], 'stats.txt': [] };
  for (const program of programs) {
    compile(program);
    const heading = `== program ${program.name} ==`;
    for (const lines of Object.values(files)) lines.push(heading);
    files['diagnostics.txt'].push(...diagnostics(program, source));
    if (program.error) { files['listing.txt'].push('not compiled'); files['stats.txt'].push('not compiled'); }
    else {
      files['listing.txt'].push(...listing(program)); files['output.txt'].push(...program.mainRun.output); files['stats.txt'].push(...statistics(program));
    }
  }
  files['stats.txt'].push(...summary(programs));
  fs.mkdirSync('output', { recursive: true });
  for (const [name, lines] of Object.entries(files)) fs.writeFileSync('output/' + name, lines.join('\n') + '\n', 'ascii');
}

main();
