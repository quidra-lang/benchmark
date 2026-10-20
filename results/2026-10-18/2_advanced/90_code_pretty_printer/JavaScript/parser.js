'use strict';

const { FormatError, TYPES } = require('./lexer');
const ASSIGNMENTS = new Set(['=', '+=', '-=', '*=', '/=', '%=']);
const PRECEDENCE = new Map([['||', 1], ['&&', 2], ['==', 3], ['!=', 3], ['<', 4], ['<=', 4], ['>', 4], ['>=', 4], ['+', 5], ['-', 5], ['*', 6], ['/', 6], ['%', 6]]);

class Parser {
  constructor(tokens) { this.tokens = tokens; this.position = 0; }
  peek(offset = 0) { return this.tokens[Math.min(this.position + offset, this.tokens.length - 1)]; }
  is(value) { return this.peek().value === value; }
  fail(expected) {
    const token = this.peek(), actual = token.kind === 'end' ? 'end of file' : "'" + token.value + "'";
    throw new FormatError(token.line, token.column, 'expected ' + expected + ', found ' + actual);
  }
  read(value) { if (!this.is(value)) this.fail("'" + value + "'"); return this.tokens[this.position++]; }
  identifier() { if (this.peek().kind !== 'identifier') this.fail('identifier'); return this.tokens[this.position++]; }
  type() { if (!TYPES.has(this.peek().value)) this.fail('type'); return this.tokens[this.position++]; }
  node(kind, first, fields = {}) { return { kind, first, last: this.tokens[this.position - 1], ...fields }; }
  program() {
    const items = [];
    while (this.peek().kind !== 'end') {
      const type = this.type(), name = this.identifier();
      if (this.is('(')) {
        const parameters = this.list('(', ')', 'parameters', false, () => this.parameter()), body = this.block();
        items.push(this.node('function', type, { type, name, parameters, body }));
      } else items.push(this.declaration(type, name, true));
    }
    return { kind: 'program', items, end: this.peek() };
  }
  parameter() {
    const type = this.type(), name = this.identifier(), dimensions = [];
    while (this.is('[')) dimensions.push({ open: this.read('['), close: this.read(']') });
    return this.node('parameter', type, { type, name, dimensions });
  }
  declaration(type, name, semicolon) {
    const dimensions = [];
    while (this.is('[')) {
      const open = this.read('['), value = this.is(']') ? null : this.expression(), close = this.read(']');
      dimensions.push({ open, value, close });
    }
    let equal = null, initializer = null;
    if (this.is('=')) { equal = this.read('='); initializer = this.initializer(); }
    const semi = semicolon ? this.read(';') : null;
    return this.node('declaration', type, { type, name, dimensions, equal, initializer, semi });
  }
  initializer() { return this.is('{') ? this.list('{', '}', 'initializers', true, () => this.initializer()) : this.expression(); }
  list(opening, closing, role, allowTrailing, element) {
    const open = this.read(opening), elements = [], commas = [];
    let trailing = null;
    if (!this.is(closing)) {
      elements.push(element());
      while (this.is(',')) {
        if (allowTrailing && this.peek(1).value === closing) { trailing = this.read(','); break; }
        commas.push(this.read(',')); elements.push(element());
      }
    }
    const close = this.read(closing);
    return this.node('list', open, { open, close, role, elements, commas, trailing });
  }
  block() {
    const open = this.read('{'), statements = [];
    while (!this.is('}') && this.peek().kind !== 'end') statements.push(this.statement());
    const close = this.read('}');
    return this.node('block', open, { open, close, statements });
  }
  statement() {
    const first = this.peek();
    if (this.is('{')) return this.block();
    if (TYPES.has(first.value)) { const type = this.type(), name = this.identifier(); return this.declaration(type, name, true); }
    if (this.is('if')) return this.ifStatement();
    if (this.is('while')) {
      const keyword = this.read('while'), open = this.read('('), condition = this.expression(), close = this.read(')'), body = this.statement();
      return this.node('while', first, { keyword, open, condition, close, body });
    }
    if (this.is('for')) return this.forStatement();
    if (this.is('switch')) return this.switchStatement();
    if (this.is('return')) {
      const keyword = this.read('return'), value = this.is(';') ? null : this.expression(), semi = this.read(';');
      return this.node('return', first, { keyword, value, semi });
    }
    if (this.is('break') || this.is('continue')) {
      const keyword = this.read(first.value), semi = this.read(';');
      return this.node('jump', first, { keyword, semi });
    }
    const result = this.simple(); result.semi = this.read(';'); result.last = result.semi; return result;
  }
  ifStatement() {
    const keyword = this.read('if'), open = this.read('('), condition = this.expression(), close = this.read(')'), body = this.statement();
    let otherwise = null, alternative = null;
    if (this.is('else')) { otherwise = this.read('else'); alternative = this.statement(); }
    return this.node('if', keyword, { keyword, open, condition, close, body, otherwise, alternative });
  }
  forStatement() {
    const keyword = this.read('for'), open = this.read('(');
    let initial = null;
    if (!this.is(';')) {
      if (TYPES.has(this.peek().value)) { const type = this.type(), name = this.identifier(); initial = this.declaration(type, name, false); }
      else initial = this.simple();
    }
    const firstSemi = this.read(';'), condition = this.is(';') ? null : this.expression(), secondSemi = this.read(';');
    const update = this.is(')') ? null : this.simple(), close = this.read(')'), body = this.statement();
    return this.node('for', keyword, { keyword, open, initial, firstSemi, condition, secondSemi, update, close, body });
  }
  switchStatement() {
    const keyword = this.read('switch'), left = this.read('('), condition = this.expression(), right = this.read(')'), open = this.read('{'), clauses = [];
    while (this.is('case') || this.is('default')) {
      const label = this.read(this.peek().value), value = label.value === 'case' ? this.expression() : null, colon = this.read(':'), statements = [];
      while (!['case', 'default', '}'].includes(this.peek().value) && this.peek().kind !== 'end') statements.push(this.statement());
      clauses.push(this.node('clause', label, { label, value, colon, statements }));
    }
    const close = this.read('}');
    return this.node('switch', keyword, { keyword, left, condition, right, open, close, clauses });
  }
  simple() {
    const left = this.expression();
    if (ASSIGNMENTS.has(this.peek().value)) {
      const operator = this.read(this.peek().value), right = this.expression();
      return this.node('assignment', left.first, { left, operator, right, semi: null });
    }
    return this.node('expression_statement', left.first, { value: left, semi: null });
  }
  expression() {
    const condition = this.binary(1);
    if (!this.is('?')) return condition;
    const question = this.read('?'), yes = this.expression(), colon = this.read(':'), no = this.expression();
    return this.node('conditional', condition.first, { condition, question, yes, colon, no });
  }
  binary(precedence) {
    if (precedence === 7) return this.unary();
    let left = this.binary(precedence + 1);
    while (PRECEDENCE.get(this.peek().value) === precedence) {
      const operator = this.read(this.peek().value), right = this.binary(precedence + 1);
      left = this.node('binary', left.first, { left, operator, right, precedence });
    }
    return left;
  }
  unary() {
    if (this.is('-') || this.is('!')) {
      const operator = this.read(this.peek().value), operand = this.unary();
      return this.node('unary', operator, { operator, operand });
    }
    let target = this.primary();
    while (true) {
      if (this.is('(')) {
        const argumentsList = this.list('(', ')', 'arguments', false, () => this.expression());
        target = this.node('call', target.first, { target, argumentsList });
      } else if (this.is('[')) {
        const open = this.read('['), value = this.expression(), close = this.read(']');
        target = this.node('index', target.first, { target, open, value, close });
      } else if (this.is('.')) {
        const dot = this.read('.'), name = this.identifier(); target = this.node('member', target.first, { target, dot, name });
      } else return target;
    }
  }
  primary() {
    const token = this.peek();
    if (['identifier', 'number', 'string'].includes(token.kind) || token.value === 'true' || token.value === 'false') {
      this.position++; return this.node('primary', token, { token });
    }
    if (this.is('(')) {
      const open = this.read('('), inner = this.expression(), close = this.read(')');
      return this.node('parenthesized', open, { open, inner, close });
    }
    this.fail('expression');
  }
}

function children(node) {
  switch (node.kind) {
    case 'program': return node.items;
    case 'function': return [node.parameters, node.body];
    case 'declaration': return [...node.dimensions.map(dimension => dimension.value), node.initializer].filter(Boolean);
    case 'list': return node.elements;
    case 'block': return node.statements;
    case 'clause': return [node.value, ...node.statements].filter(Boolean);
    case 'if': return [node.condition, node.body, node.alternative].filter(Boolean);
    case 'while': return [node.condition, node.body];
    case 'for': return [node.initial, node.condition, node.update, node.body].filter(Boolean);
    case 'switch': return [node.condition, ...node.clauses];
    case 'return': case 'expression_statement': return node.value ? [node.value] : [];
    case 'assignment': case 'binary': return [node.left, node.right];
    case 'conditional': return [node.condition, node.yes, node.no];
    case 'unary': return [node.operand];
    case 'parenthesized': return [node.inner];
    case 'call': return [node.target, node.argumentsList];
    case 'index': return [node.target, node.value];
    case 'member': return [node.target];
    default: return [];
  }
}

module.exports = { Parser, children };
