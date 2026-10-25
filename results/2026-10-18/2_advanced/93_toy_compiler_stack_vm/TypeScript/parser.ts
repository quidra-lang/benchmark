import { CompileError } from './lexer.ts';
const TYPES = new Set(['int', 'bool', 'void']);
const PRECEDENCE = new Map([['||', 1], ['&&', 2], ['==', 3], ['!=', 3], ['<', 4], ['<=', 4], ['>', 4], ['>=', 4],
  ['+', 5], ['-', 5], ['*', 6], ['/', 6], ['%', 6]]);

function resolve(iterator) {
  const pending = [iterator];
  let value;
  while (pending.length) {
    const step = pending[pending.length - 1].next(value); value = undefined;
    if (step.done) { pending.pop(); value = step.value; } else pending.push(step.value);
  }
  return value;
}

class Parser {
  declare index: any;
  declare tokens: any;
  constructor(tokens) { this.tokens = tokens; this.index = 0; }
  peek() { return this.tokens[this.index]; }
  take() { return this.tokens[this.index++]; }
  error() {
    const token = this.peek();
    throw new CompileError('syntax', token.position, token.kind === 'end' ? 'unexpected end of program' : `unexpected '${token.text}'`);
  }
  accept(text) { if (this.peek().text !== text) return false; this.take(); return true; }
  expect(text) { if (this.peek().text !== text) this.error(); return this.take(); }
  identifier() { if (this.peek().kind !== 'identifier') this.error(); return this.take(); }
  declarationHead(kind) {
    if (!TYPES.has(this.peek().text)) this.error();
    const type = this.take(), name = this.identifier();
    return { kind, type: type.text, name: name.text, position: type.position, namePosition: name.position, initializer: null };
  }
  parse() { return resolve(this.program()); }
  *program() {
    const declarations = [];
    while (this.peek().kind !== 'end') {
      const declaration = this.declarationHead('global');
      if (this.accept('(')) {
        declaration.kind = 'function'; declaration.params = [];
        if (this.peek().text !== ')') {
          do { declaration.params.push(this.declarationHead('parameter')); } while (this.accept(','));
        }
        this.expect(')'); declaration.body = yield this.block();
      } else {
        declaration.size = null;
        if (this.accept('[')) {
          if (this.peek().kind !== 'integer') this.error();
          const size = this.take(); declaration.size = size.value; declaration.sizePosition = size.position; this.expect(']');
        } else if (this.accept('=')) declaration.initializer = yield this.expression();
        this.expect(';');
      }
      declarations.push(declaration);
    }
    return { declarations, end: this.peek().position };
  }
  *declaration(requiredInitializer = false) {
    const result = this.declarationHead('declaration');
    if (requiredInitializer) { this.expect('='); result.initializer = yield this.expression(); }
    else if (this.accept('=')) result.initializer = yield this.expression();
    return result;
  }
  *block() {
    const position = this.expect('{').position, statements = [];
    while (this.peek().text !== '}') {
      if (TYPES.has(this.peek().text)) { statements.push(yield this.declaration()); this.expect(';'); }
      else statements.push(yield this.statement());
    }
    return { kind: 'block', position, statements, closingPosition: this.take().position };
  }
  *statement() {
    const token = this.peek(), position = token.position;
    if (token.text === '{') return yield this.block();
    if (token.text === 'if') {
      this.take(); this.expect('('); const condition = yield this.expression(); this.expect(')');
      const then = yield this.statement(), otherwise = this.accept('else') ? (yield this.statement()) : null;
      return { kind: 'if', position, condition, then, otherwise };
    }
    if (token.text === 'while') {
      this.take(); this.expect('('); const condition = yield this.expression(); this.expect(')');
      return { kind: 'while', position, condition, body: yield this.statement() };
    }
    if (token.text === 'for') {
      this.take(); this.expect('(');
      const initialization = this.peek().text === ';' ? null : TYPES.has(this.peek().text) ? (yield this.declaration(true)) : (yield this.simple());
      this.expect(';'); const condition = this.peek().text === ';' ? null : (yield this.expression());
      this.expect(';'); const update = this.peek().text === ')' ? null : (yield this.simple());
      this.expect(')'); return { kind: 'for', position, initialization, condition, update, body: yield this.statement() };
    }
    if (token.text === 'break' || token.text === 'continue') { this.take(); this.expect(';'); return { kind: token.text, position }; }
    if (token.text === 'return') {
      this.take(); const value = this.peek().text === ';' ? null : (yield this.expression()); this.expect(';');
      return { kind: 'return', position, value };
    }
    if (token.text === 'print') {
      this.take(); this.expect('('); const values = [yield this.expression()];
      while (this.accept(',')) values.push(yield this.expression());
      this.expect(')'); this.expect(';'); return { kind: 'print', position, values };
    }
    if (token.kind !== 'identifier' && token.text !== 'read') this.error();
    const result = yield this.simple(); this.expect(';'); return result;
  }
  *arguments() {
    const args = [];
    if (this.peek().text !== ')') { do { args.push(yield this.expression()); } while (this.accept(',')); }
    this.expect(')'); return args;
  }
  *simple() {
    const token = this.peek();
    if (token.text === 'read') return { kind: 'call-statement', position: token.position, expression: yield this.primary() };
    const name = this.identifier();
    if (this.accept('(')) return { kind: 'call-statement', position: name.position,
      expression: { kind: 'call', name: name.text, position: name.position, args: yield this.arguments() } };
    let index = null;
    if (this.accept('[')) { index = yield this.expression(); this.expect(']'); }
    this.expect('='); return { kind: 'assignment', position: name.position, name: name.text, index, value: yield this.expression() };
  }
  *expression(minimum = 1) {
    let left = yield this.unary();
    while (PRECEDENCE.has(this.peek().text) && PRECEDENCE.get(this.peek().text) >= minimum) {
      const token = this.take(), right = yield this.expression(PRECEDENCE.get(token.text) + 1);
      left = { kind: 'binary', operator: token.text, position: token.position, left, right };
    }
    return left;
  }
  *unary() {
    if (this.peek().text === '-' || this.peek().text === '!') {
      const token = this.take(); return { kind: 'unary', operator: token.text, position: token.position, operand: yield this.unary() };
    }
    return yield this.primary();
  }
  *primary() {
    const token = this.peek();
    if (token.kind === 'integer') { this.take(); return { kind: 'literal', type: 'int', value: token.value, position: token.position }; }
    if (token.text === 'true' || token.text === 'false') {
      this.take(); return { kind: 'literal', type: 'bool', value: token.text === 'true' ? 1 : 0, position: token.position };
    }
    if (token.text === 'read') { this.take(); this.expect('('); this.expect(')'); return { kind: 'read', position: token.position }; }
    if (this.accept('(')) { const result = yield this.expression(); this.expect(')'); return result; }
    const name = this.identifier();
    if (this.accept('(')) return { kind: 'call', position: name.position, name: name.text, args: yield this.arguments() };
    if (this.accept('[')) { const index = yield this.expression(); this.expect(']'); return { kind: 'index', position: name.position, name: name.text, index }; }
    return { kind: 'variable', position: name.position, name: name.text };
  }
}

function statementChildren(node) {
  if (node.kind === 'block') return node.statements;
  if (node.kind === 'if') return [node.then, node.otherwise].filter(child => child !== null);
  if (node.kind === 'while') return [node.body];
  if (node.kind === 'for') return [node.initialization, node.update, node.body].filter(child => child !== null);
  return [];
}

function expressionChildren(node) {
  if (node.kind === 'binary') return [node.left, node.right];
  if (node.kind === 'unary') return [node.operand];
  if (node.kind === 'call') return node.args;
  if (node.kind === 'index') return [node.index];
  return [];
}

export { Parser, statementChildren, expressionChildren, resolve };
