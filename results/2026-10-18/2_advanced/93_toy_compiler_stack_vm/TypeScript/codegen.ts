import { positionCompare } from './lexer.ts';
import { statementChildren, resolve } from './parser.ts';
const BINARY = { '+': 'ADD', '-': 'SUB', '*': 'MUL', '/': 'DIV', '%': 'MOD', '<': 'LT', '<=': 'LE', '>': 'GT', '>=': 'GE', '==': 'EQ', '!=': 'NE' };

class Generator {
  declare code: any;
  constructor() { this.code = []; }
  emit(op, args, position, callee = null) {
    const instruction = { op, args, position, callee }; this.code.push(instruction); return instruction;
  }
  label() { return { target: null, references: [] }; }
  mark(label) {
    label.target = this.code.length;
    for (const instruction of label.references) instruction.args[0] = label.target;
  }
  jump(op, label, position) {
    const instruction = this.emit(op, [label.target], position);
    if (label.target === null) label.references.push(instruction);
  }
  expression(node) { return resolve(this.generateExpression(node)); }
  *generateExpression(node) {
    const position = node.position;
    switch (node.kind) {
      case 'literal': this.emit('PUSH', [node.value], position); break;
      case 'read': this.emit('READ', [], position); break;
      case 'variable': {
        const global = node.referent.kind === 'global';
        this.emit(global ? 'LOADG' : 'LOADL', [global ? node.referent.address : node.referent.slot], position); break;
      }
      case 'index': yield this.generateExpression(node.index); this.emit('LOADA', [node.referent.address, node.referent.size], position); break;
      case 'call':
        for (const argument of node.args) yield this.generateExpression(argument);
        this.emit('CALL', [0, node.args.length], position, node.referent.name); break;
      case 'unary': yield this.generateExpression(node.operand); this.emit(node.operator === '-' ? 'NEG' : 'NOT', [], position); break;
      case 'binary':
        yield this.generateExpression(node.left);
        if (node.operator === '&&' || node.operator === '||') {
          const short = this.label(), end = this.label(), conjunction = node.operator === '&&';
          this.jump(conjunction ? 'JUMPF' : 'JUMPT', short, position); yield this.generateExpression(node.right); this.jump('JUMP', end, position);
          this.mark(short); this.emit('PUSH', [conjunction ? 0 : 1], position); this.mark(end);
        } else { yield this.generateExpression(node.right); this.emit(BINARY[node.operator], [], position); }
        break;
    }
  }
  statement(node, loop = null) { return resolve(this.generateStatement(node, loop)); }
  *generateStatement(node, loop = null) {
    const position = node.position;
    switch (node.kind) {
      case 'block':
        for (const statement of node.statements) yield this.generateStatement(statement, loop);
        break;
      case 'declaration':
        if (node.initializer !== null) this.expression(node.initializer); else this.emit('PUSH', [0], node.namePosition);
        this.emit('STOREL', [node.slot], node.namePosition); break;
      case 'assignment':
        if (node.index !== null) this.expression(node.index);
        this.expression(node.value);
        if (node.index !== null) this.emit('STOREA', [node.referent.address, node.referent.size], position);
        else {
          const global = node.referent.kind === 'global';
          this.emit(global ? 'STOREG' : 'STOREL', [global ? node.referent.address : node.referent.slot], position);
        }
        break;
      case 'call-statement':
        this.expression(node.expression); if (node.expression.type !== 'void') this.emit('POP', [], position); break;
      case 'print': node.values.forEach(value => this.expression(value)); this.emit('PRINT', [node.values.length], position); break;
      case 'return':
        if (node.value !== null) this.expression(node.value);
        this.emit(node.value === null ? 'RET' : 'RETV', [], position); break;
      case 'break': this.jump('JUMP', loop.end, position); break;
      case 'continue': this.jump('JUMP', loop.next, position); break;
      case 'if': {
        const alternative = this.label(), end = this.label();
        this.expression(node.condition); this.jump('JUMPF', alternative, position); yield this.generateStatement(node.then, loop);
        if (node.otherwise !== null) {
          this.jump('JUMP', end, position); this.mark(alternative); yield this.generateStatement(node.otherwise, loop); this.mark(end);
        } else this.mark(alternative);
        break;
      }
      case 'while': {
        const start = this.label(), end = this.label(); this.mark(start);
        this.expression(node.condition); this.jump('JUMPF', end, position); yield this.generateStatement(node.body, { next: start, end });
        this.jump('JUMP', start, position); this.mark(end); break;
      }
      case 'for': {
        const start = this.label(), next = this.label(), end = this.label();
        if (node.initialization !== null) yield this.generateStatement(node.initialization, loop);
        this.mark(start);
        if (node.condition !== null) { this.expression(node.condition); this.jump('JUMPF', end, position); }
        yield this.generateStatement(node.body, { next, end }); this.mark(next);
        if (node.update !== null) yield this.generateStatement(node.update, loop);
        this.jump('JUMP', start, position); this.mark(end); break;
      }
      case 'empty': break;
    }
  }
}

function generate(analysis, functions) {
  let globalSize = 0;
  for (const variable of analysis.globals) { variable.address = globalSize; globalSize += variable.size === null ? 1 : variable.size; }
  const initialization = new Generator(), main = analysis.names.get('main');
  for (const variable of analysis.globals) if (variable.initializer !== null) {
    initialization.expression(variable.initializer); initialization.emit('STOREG', [variable.address], variable.namePosition);
  }
  initialization.emit('CALL', [0, 0], main.namePosition, 'main'); initialization.emit('HALT', [], main.namePosition);
  const units = [{ name: '<init>', declaration: null, slots: [], code: initialization.code }];
  for (const declaration of functions) {
    const locals = [], pending = [declaration.body];
    while (pending.length) {
      const statement = pending.pop();
      if (statement.kind === 'declaration') locals.push(statement);
      for (const child of statementChildren(statement)) pending.push(child);
    }
    locals.sort((a, b) => positionCompare(a.namePosition, b.namePosition));
    const slots = declaration.params.concat(locals); slots.forEach((variable, index) => { variable.slot = index; });
    const generator = new Generator(); generator.emit('ENTER', [slots.length], declaration.namePosition);
    generator.statement(declaration.body);
    if (declaration.type === 'void') generator.emit('RET', [], declaration.body.closingPosition);
    units.push({ name: declaration.name, declaration, slots, code: generator.code });
  }
  return { units, globalSize };
}

export { Generator, generate };
