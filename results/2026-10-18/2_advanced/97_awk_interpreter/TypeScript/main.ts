import * as fs from 'node:fs';
import { SyntaxFault, tokenize } from './lexer.ts';
import { Parser, children } from './parser.ts';
import { uninitialized, number, string, toNumber, toString, inputValue, truth, compare, asciiCompare, orderedKeys, splitString, Fields, display } from './values_fields.ts';
import { RuntimeFault, fail, format, builtin } from './builtins.ts';
import { argumentsList, readLines, Streams } from './streams.ts';

const SPECIAL = ['FILENAME', 'FNR', 'FS', 'NF', 'NR', 'OFS', 'ORS', 'SUBSEP'];
const positionCompare = (a, b) => a.line - b.line || a.column - b.column;
const positionText = position => position.line + ':' + position.column;

class StaticFault extends Error {
  declare position: any;
  constructor(position, message) { super(message); this.position = position; }
}

function analyze(program) {
  const functions = program.items.filter(item => item.kind === 'function'), definitions = new Map(), errors = [], globals = new Map();
  const rules = program.items.filter(item => item.kind === 'rule'), statementLines = new Set(), calls = [], splits = [];
  const error = (position, priority, message) => errors.push({ position, priority, message });
  const global = name => {
    if (!globals.has(name)) globals.set(name, { name, global: true, array: false });
    return globals.get(name);
  };
  for (const name of SPECIAL) global(name);
  for (const definition of functions) {
    if (definitions.has(definition.name)) error(definition.nameToken.position, 0, `function ${definition.name} redefined`);
    else definitions.set(definition.name, definition);
    definition.scope = new Map(); definition.symbols = [];
    definition.calls = 0; definition.active = 0; definition.depth = 0;
    for (const parameter of definition.parameters) {
      if (definition.scope.has(parameter.text)) error(parameter.position, 1, `duplicate parameter ${parameter.text}`);
      const symbol = { name: parameter.text, global: false, array: false };
      definition.scope.set(parameter.text, symbol); definition.symbols.push(symbol);
    }
  }
  const occurrence = (token, definition, array = false) => {
    if (definitions.has(token.text)) error(token.position, 2, `function ${token.text} used as variable`);
    const symbol = definition?.scope.get(token.text) || global(token.text);
    if (array) symbol.array = true;
    return symbol;
  };
  for (const definition of functions) for (const parameter of definition.parameters) {
    if (definitions.has(parameter.text)) error(parameter.position, 2, `function ${parameter.text} used as variable`);
  }
  for (const item of program.items) {
    const definition = item.kind === 'function' ? item : null, work = [item];
    while (work.length) {
      const node = work.pop();
      if (node.statement) statementLines.add(node.position.line);
      if (['variable', 'array', 'in', 'delete'].includes(node.kind)) node.symbol = occurrence(node.nameToken, definition, node.kind !== 'variable');
      if (node.kind === 'for-in') {
        node.variableSymbol = occurrence(node.variable, definition); node.arraySymbol = occurrence(node.array, definition, true);
      }
      if (node.kind === 'call') {
        node.definition = definitions.get(node.name); calls.push(node);
        if (node.definition === undefined) error(node.position, 3, `undefined function ${node.name}`);
        else if (node.args.length > node.definition.parameters.length) error(node.position, 4, `too many arguments to ${node.name}`);
      }
      if (node.kind === 'builtin' && node.name === 'split') splits.push(node);
      const nested = children(node);
      for (let i = nested.length - 1; i >= 0; i--) work.push(nested[i]);
    }
  }
  if (errors.length) {
    errors.sort((a, b) => positionCompare(a.position, b.position) || a.priority - b.priority);
    throw new StaticFault(errors[0].position, errors[0].message);
  }
  for (const call of splits) call.args[1].symbol.array = true;
  const links = [];
  for (const call of calls) for (let i = 0; i < call.args.length; i++) {
    if (call.args[i].kind === 'variable') links.push([call.args[i].symbol, call.definition.symbols[i]]);
  }
  let changed = true;
  while (changed) {
    changed = false;
    for (const [a, b] of links) if (a.array !== b.array) { a.array = true; b.array = true; changed = true; }
  }
  return { functions, definitions, rules, globals, statementLines };
}

class Transfer extends Error {
  declare kind: any;
  declare value: any;
  constructor(kind, value = uninitialized) { super(kind); this.kind = kind; this.value = value; }
}

function resolve(iterator) {
  const pending = [iterator];
  let value, raised = false;
  while (pending.length) {
    let step;
    try { step = raised ? pending[pending.length - 1].throw(value) : pending[pending.length - 1].next(value); }
    catch (error) { pending.pop(); value = error; raised = true; continue; }
    value = undefined; raised = false;
    if (step.done) { pending.pop(); value = step.value; } else pending.push(step.value);
  }
  if (raised) throw value;
  return value;
}

class Interpreter {
  declare analysis: any;
  declare args: any;
  declare current: any;
  declare error: any;
  declare fields: any;
  declare globals: any;
  declare lines: any;
  declare locals: any;
  declare operand: any;
  declare phase: any;
  declare status: any;
  declare streams: any;
  constructor(analysis, args) {
    this.analysis = analysis; this.args = args; this.globals = new Map(); this.locals = [];
    for (const symbol of analysis.globals.values()) this.globals.set(symbol.name, this.cell(symbol));
    const initial = { FS: string(' '), OFS: string(' '), ORS: string('\n'), SUBSEP: string(String.fromCharCode(28)),
      NR: number(0), FNR: number(0), FILENAME: string('') };
    for (const [name, value] of Object.entries(initial)) this.globals.get(name).value = value;
    this.fields = new Fields(name => this.globalValue(name), fail); this.streams = new Streams();
    this.lines = new Map(Array.from(analysis.statementLines, line => [line, 0]));
    this.operand = 0; this.current = null; this.phase = 'BEGIN'; this.status = 0; this.error = null;
  }
  cell(symbol, value = uninitialized, array = null) { return { symbol, value, array: symbol.array ? array || new Map() : null }; }
  globalCell(name) {
    if (!this.globals.has(name)) this.globals.set(name, this.cell({ name, global: true, array: false }));
    return this.globals.get(name);
  }
  symbolCell(symbol) { return symbol.global ? this.globalCell(symbol.name) : this.locals[this.locals.length - 1].get(symbol.name); }
  globalValue(name) { return this.read({ kind: 'variable', cell: this.globalCell(name) }); }
  array(symbol) { return this.symbolCell(symbol).array; }
  read(location) {
    if (location.kind === 'field') return this.fields.read(location.index);
    if (location.kind === 'array') {
      if (!location.array.has(location.key)) location.array.set(location.key, uninitialized);
      return location.array.get(location.key);
    }
    const { cell } = location;
    return cell.symbol.global && cell.symbol.name === 'NF' ? number(this.fields.count) : cell.value;
  }
  store(location, value, position) {
    if (location.kind === 'field') this.fields.write(location.index, value);
    else if (location.kind === 'array') location.array.set(location.key, value);
    else if (location.cell.symbol.global && location.cell.symbol.name === 'NF') this.fields.resize(value, position);
    else location.cell.value = value;
    return this.read(location);
  }
  assignGlobal(name, value) { return this.store({ kind: 'variable', cell: this.globalCell(name) }, value, null); }
  *key(expressions) {
    const parts = [];
    for (const expression of expressions) parts.push(toString(yield this.evaluate(expression)));
    return parts.join(toString(this.globalValue('SUBSEP')));
  }
  *location(node) {
    if (node.kind === 'variable') return { kind: 'variable', cell: this.symbolCell(node.symbol) };
    if (node.kind === 'array') return { kind: 'array', array: this.array(node.symbol), key: yield this.key(node.subscripts) };
    const index = toNumber(yield this.evaluate(node.index));
    if (index < 0) fail(node.position, 'negative field index');
    return { kind: 'field', index };
  }
  arithmetic(operator, left, right, position) {
    const a = toNumber(left), b = toNumber(right);
    if ((operator === '/' || operator === '%') && b === 0) fail(position, 'division by zero');
    if (operator === '^' && b < 0) fail(position, 'negative exponent');
    switch (operator) {
      case '+': return number(a + b);
      case '-': return number(a - b);
      case '*': return number(a * b);
      case '/': return number(Math.trunc(a / b));
      case '%': return number(a % b);
      case '^': {
        let result = 1, base = a, exponent = b;
        while (exponent > 0) {
          if (exponent % 2 === 1) result *= base;
          exponent = Math.floor(exponent / 2); if (exponent > 0) base *= base;
        }
        return number(result);
      }
    }
  }
  *evaluate(node) {
    switch (node.kind) {
      case 'literal': return node.valueKind === 'number' ? number(node.value) : string(node.value);
      case 'parenthesized': return yield this.evaluate(node.expression);
      case 'variable': case 'array': case 'field': return this.read(yield this.location(node));
      case 'assignment': {
        const location = yield this.location(node.left), right = yield this.evaluate(node.right);
        const value = node.operator === '=' ? right : this.arithmetic(node.operator[0], this.read(location), right, node.position);
        return this.store(location, value, node.position);
      }
      case 'increment': {
        const location = yield this.location(node.target), previous = toNumber(this.read(location));
        const value = previous + (node.operator === '++' ? 1 : -1); this.store(location, number(value), node.position);
        return number(node.prefix ? value : previous);
      }
      case 'conditional': return yield this.evaluate(truth(yield this.evaluate(node.condition)) ? node.then : node.otherwise);
      case 'unary': {
        const value = yield this.evaluate(node.operand);
        return number(node.operator === '!' ? Number(!truth(value)) : node.operator === '-' ? -toNumber(value) : toNumber(value));
      }
      case 'binary': {
        const left = yield this.evaluate(node.left);
        if (node.operator === '&&' && !truth(left)) return number(0);
        if (node.operator === '||' && truth(left)) return number(1);
        const right = yield this.evaluate(node.right);
        if (node.operator === '&&' || node.operator === '||') return number(Number(truth(right)));
        if (node.operator === 'concat') return string(toString(left) + toString(right));
        if (['<', '<=', '==', '!=', '>=', '>'].includes(node.operator)) {
          const relation = compare(left, right);
          const satisfied = { '<': relation < 0, '<=': relation <= 0, '==': relation === 0, '!=': relation !== 0, '>=': relation >= 0, '>': relation > 0 };
          return number(Number(satisfied[node.operator]));
        }
        return this.arithmetic(node.operator, left, right, node.position);
      }
      case 'in': { const key = yield this.key(node.subscripts); return number(Number(this.array(node.symbol).has(key))); }
      case 'call': return yield this.call(node);
      case 'builtin': return yield this.builtin(node);
      case 'getline': return yield this.getline(node);
    }
  }
  *call(node) {
    const definition = node.definition, frame = new Map();
    for (let i = 0; i < definition.symbols.length; i++) {
      const symbol = definition.symbols[i];
      if (symbol.array) frame.set(symbol.name, this.cell(symbol, uninitialized, i < node.args.length ? this.array(node.args[i].symbol) : new Map()));
      else frame.set(symbol.name, this.cell(symbol, i < node.args.length ? (yield this.evaluate(node.args[i])) : uninitialized));
    }
    definition.calls++; definition.active++; definition.depth = Math.max(definition.depth, definition.active); this.locals.push(frame);
    try { yield this.statement(definition.body); }
    catch (transfer) { if (!(transfer instanceof Transfer) || transfer.kind !== 'return') throw transfer; return transfer.value; }
    finally { this.locals.pop(); definition.active--; }
    return uninitialized;
  }
  *builtin(node) {
    if (node.name === 'length') {
      if (node.args.length === 0) return number(toString(this.fields.record).length);
      if (node.args[0].kind === 'variable' && node.args[0].symbol.array) return number(this.array(node.args[0].symbol).size);
      return number(toString(yield this.evaluate(node.args[0])).length);
    }
    if (node.name === 'split') {
      const value = toString(yield this.evaluate(node.args[0]));
      const separator = node.args.length === 3 ? toString(yield this.evaluate(node.args[2])) : toString(this.globalValue('FS'));
      const array = this.array(node.args[1].symbol), pieces = splitString(value, separator); array.clear();
      pieces.forEach((piece, i) => array.set(String(i + 1), inputValue(piece))); return number(pieces.length);
    }
    const values = [];
    for (const argument of node.args) values.push(yield this.evaluate(argument));
    return node.name === 'close' ? number(this.streams.close(toString(values[0]))) : builtin(node.name, values, node.position);
  }
  readMain() {
    if (this.phase === 'END') return null;
    while (true) {
      if (this.current !== null && this.current.index < this.current.lines.length) {
        this.current.operand.records++;
        this.assignGlobal('NR', number(toNumber(this.globalValue('NR')) + 1));
        this.assignGlobal('FNR', number(toNumber(this.globalValue('FNR')) + 1));
        return this.current.lines[this.current.index++];
      }
      if (this.operand === this.args.operands.length) return null;
      const operand = this.args.operands[this.operand++];
      if (operand.kind === 'assignment') this.assignGlobal(operand.name, inputValue(operand.value));
      else {
        this.current = { operand, lines: readLines(operand.name), index: 0 };
        this.assignGlobal('FILENAME', string(operand.name)); this.assignGlobal('FNR', number(0));
      }
    }
  }
  *getline(node) {
    let result;
    if (node.file === null) {
      const line = this.readMain(); result = line === null ? { status: 0 } : { status: 1, line };
    } else result = this.streams.getline(toString(yield this.evaluate(node.file)));
    if (result.status === 1) {
      if (node.target === null) this.fields.setRecord(result.line);
      else this.store(yield this.location(node.target), inputValue(result.line), node.position);
    }
    return number(result.status);
  }
  *output(node) {
    const values = [];
    for (const argument of node.args) values.push(yield this.evaluate(argument));
    if (node.kind === 'print' && values.length === 0) values.push(this.fields.record);
    const content = node.kind === 'print' ? values.map(toString).join(toString(this.globalValue('OFS'))) + toString(this.globalValue('ORS')) : format(values, node.position);
    if (node.redirect === null) this.streams.write(content);
    else {
      const name = toString(yield this.evaluate(node.redirect.target));
      this.streams.write(content, name, node.redirect.operator, node.redirect.position);
    }
  }
  *statement(node) {
    if (node.statement) this.lines.set(node.position.line, this.lines.get(node.position.line) + 1);
    switch (node.kind) {
      case 'empty': break;
      case 'block': for (const statement of node.statements) yield this.statement(statement); break;
      case 'expression': yield this.evaluate(node.expression); break;
      case 'if': {
        const selected = truth(yield this.evaluate(node.condition)) ? node.then : node.otherwise;
        if (selected !== null) yield this.statement(selected); break;
      }
      case 'while': case 'do': {
        let first = true;
        while ((node.kind === 'do' && first) || truth(yield this.evaluate(node.condition))) {
          first = false;
          try { yield this.statement(node.body); }
          catch (transfer) {
            if (!(transfer instanceof Transfer) || !['break', 'continue'].includes(transfer.kind)) throw transfer;
            if (transfer.kind === 'break') break;
          }
        }
        break;
      }
      case 'for':
        if (node.initial !== null) yield this.evaluate(node.initial);
        while (node.condition === null || truth(yield this.evaluate(node.condition))) {
          try { yield this.statement(node.body); }
          catch (transfer) {
            if (!(transfer instanceof Transfer) || !['break', 'continue'].includes(transfer.kind)) throw transfer;
            if (transfer.kind === 'break') break;
          }
          if (node.update !== null) yield this.evaluate(node.update);
        }
        break;
      case 'for-in': {
        const keys = orderedKeys(this.array(node.arraySymbol));
        for (const key of keys) {
          this.store({ kind: 'variable', cell: this.symbolCell(node.variableSymbol) }, inputValue(key), node.variable.position);
          try { yield this.statement(node.body); }
          catch (transfer) {
            if (!(transfer instanceof Transfer) || !['break', 'continue'].includes(transfer.kind)) throw transfer;
            if (transfer.kind === 'break') break;
          }
        }
        break;
      }
      case 'delete': {
        const array = this.array(node.symbol);
        if (node.subscripts === null) array.clear(); else array.delete(yield this.key(node.subscripts));
        break;
      }
      case 'print': case 'printf': yield this.output(node); break;
      case 'next':
        if (this.phase === 'BEGIN' || this.phase === 'END') fail(node.position, 'next used in BEGIN or END');
        throw new Transfer('next');
      case 'break': case 'continue': throw new Transfer(node.kind);
      case 'return': throw new Transfer('return', node.value === null ? uninitialized : (yield this.evaluate(node.value)));
      case 'exit':
        if (node.value !== null) this.status = toNumber(yield this.evaluate(node.value));
        throw new Transfer('exit');
    }
  }
  *match(rule) {
    if (rule.ruleKind === 'all') return true;
    if (rule.ruleKind === 'pattern') return truth(yield this.evaluate(rule.start));
    if (!rule.inside && truth(yield this.evaluate(rule.start))) rule.inside = true;
    if (!rule.inside) return false;
    if (truth(yield this.evaluate(rule.end))) rule.inside = false;
    return true;
  }
  *initialAndRecords() {
    for (const option of this.args.options) this.assignGlobal(option.name, inputValue(option.value));
    for (const rule of this.analysis.rules) if (rule.ruleKind === 'BEGIN') { rule.matches++; yield this.statement(rule.body); }
    if (!this.analysis.rules.some(rule => rule.ruleKind !== 'BEGIN')) return;
    this.phase = 'records';
    while (true) {
      const record = this.readMain(); if (record === null) break;
      this.fields.setRecord(record);
      try {
        for (const rule of this.analysis.rules) if (rule.ruleKind !== 'BEGIN' && rule.ruleKind !== 'END' && (yield this.match(rule))) {
          rule.matches++;
          if (rule.body !== null) yield this.statement(rule.body);
          else this.streams.write(toString(this.fields.record) + toString(this.globalValue('ORS')));
        }
      } catch (transfer) { if (!(transfer instanceof Transfer) || transfer.kind !== 'next') throw transfer; }
    }
  }
  *execute() {
    try {
      try { yield this.initialAndRecords(); }
      catch (transfer) { if (!(transfer instanceof Transfer) || transfer.kind !== 'exit') throw transfer; }
      this.phase = 'END';
      try {
        for (const rule of this.analysis.rules) if (rule.ruleKind === 'END') { rule.matches++; yield this.statement(rule.body); }
      } catch (transfer) { if (!(transfer instanceof Transfer) || transfer.kind !== 'exit') throw transfer; }
    } catch (error) { if (!(error instanceof RuntimeFault)) throw error; this.error = error; }
  }
  statistics() {
    const lines = [this.error === null ? `status: exit ${this.status}` : `status: runtime error at ${positionText(this.error.position)}: ${this.error.message}`, '[inputs]'];
    for (const operand of this.args.operands) if (operand.kind === 'file') lines.push(`${operand.name} records=${operand.records}`);
    lines.push('[getline]');
    for (const [name, input] of this.streams.inputs) lines.push(name + (input.opened ? ` reads=${input.reads}` : ' missing'));
    lines.push('[rules]');
    for (const rule of this.analysis.rules) lines.push(`${positionText(rule.position)} ${rule.ruleKind} count=${rule.matches}`);
    lines.push('[functions]');
    for (const definition of this.analysis.functions) lines.push(`${definition.name} calls=${definition.calls} depth=${definition.depth}`);
    lines.push('[outputs]', `stdout.txt writes=${this.streams.stdout.writes} bytes=${this.streams.stdout.content.length}`);
    for (const [name, output] of this.streams.outputs) lines.push(`${name} writes=${output.writes} bytes=${output.content.length}`);
    lines.push('[lines]');
    for (const line of Array.from(this.lines.keys()).sort((a, b) => a - b)) lines.push(`${line} count=${this.lines.get(line)}`);
    lines.push('[globals]');
    for (const name of Array.from(this.globals.keys()).sort(asciiCompare)) {
      const cell = this.globals.get(name);
      lines.push(name + ' = ' + (cell.array === null ? display(this.globalValue(name)) : `array (${cell.array.size})`));
    }
    return lines;
  }
}

function main() {
  const args = argumentsList(readLines('args.txt')), source = fs.readFileSync('input/program.awk', 'ascii');
  let analysis;
  try { analysis = analyze(new Parser(tokenize(source)).program()); }
  catch (error) {
    if (!(error instanceof SyntaxFault) && !(error instanceof StaticFault)) throw error;
    const status = error instanceof SyntaxFault ? `status: syntax error at ${positionText(error.position)}` : `status: error at ${positionText(error.position)}: ${error.message}`;
    fs.mkdirSync('output', { recursive: true }); fs.writeFileSync('output/stdout.txt', '', 'ascii'); fs.writeFileSync('output/stats.txt', status + '\n', 'ascii'); return;
  }
  const interpreter = new Interpreter(analysis, args); resolve(interpreter.execute()); interpreter.streams.save();
  fs.writeFileSync('output/stats.txt', interpreter.statistics().join('\n') + '\n', 'ascii');
}

main();
