'use strict';

const { SyntaxFault } = require('./lexer');
const ASSIGNMENTS = new Set(['=', '+=', '-=', '*=', '/=', '%=', '^=']);
const COMPARISONS = new Set(['<', '<=', '==', '!=', '>=', '>']);
const lvalue = node => ['variable', 'array', 'field'].includes(node.kind);
const concatenates = token => ['number', 'string', 'name', 'function', 'builtin'].includes(token.kind) || ['$', '(', '++', '--'].includes(token.text);

class Parser {
  constructor(tokens) { this.tokens = tokens; this.index = 0; this.context = 'rule'; this.loops = 0; }
  peek(offset = 0) { return this.tokens[Math.min(this.index + offset, this.tokens.length - 1)]; }
  is(text) { return this.peek().text === text; }
  take() { return this.tokens[this.index++]; }
  fail(token = this.peek()) { throw new SyntaxFault(token.position); }
  expect(text) { if (!this.is(text)) this.fail(); return this.take(); }
  name() { if (this.peek().kind !== 'name') this.fail(); return this.take(); }
  newlines() { while (this.peek().kind === 'newline') this.take(); }
  node(kind, token, fields = {}) { return { kind, position: token.position, ...fields }; }
  endSimple() { if (this.is(';') || this.peek().kind === 'newline') this.take(); else if (!this.is('}')) this.fail(); }
  noValue() { return this.is(';') || this.is('}') || this.peek().kind === 'newline'; }
  program() {
    const items = [];
    while (this.peek().kind !== 'eof') {
      if (this.peek().kind === 'newline' || this.is(';')) { this.take(); continue; }
      const token = this.peek(); this.loops = 0;
      if (this.is('function')) {
        this.take();
        if (!['name', 'function'].includes(this.peek().kind)) this.fail();
        const name = this.take(), parameters = []; this.expect('(');
        if (!this.is(')')) {
          parameters.push(this.name());
          while (this.is(',')) { this.take(); this.newlines(); parameters.push(this.name()); }
        }
        this.expect(')'); this.newlines(); this.context = 'function';
        items.push(this.node('function', token, { name: name.text, nameToken: name, parameters, body: this.block() }));
      } else {
        let kind, start = null, end = null, body = null;
        if (this.is('BEGIN') || this.is('END')) {
          kind = this.take().text; this.context = kind; body = this.block();
        } else {
          this.context = 'rule';
          if (this.is('{')) { kind = 'all'; body = this.block(); }
          else {
            kind = 'pattern'; start = this.expression();
            if (this.is(',')) { this.take(); this.newlines(); end = this.expression(); kind = 'range'; }
            if (this.is('{')) body = this.block();
            else if (!this.is(';') && !['newline', 'eof'].includes(this.peek().kind)) this.fail();
          }
        }
        items.push(this.node('rule', token, { ruleKind: kind, start, end, body, matches: 0, inside: false }));
      }
    }
    return { items };
  }
  block() {
    const token = this.expect('{'), statements = [];
    while (!this.is('}')) {
      if (this.peek().kind === 'newline' || this.is(';')) this.take();
      else statements.push(this.statement());
    }
    this.take(); return this.node('block', token, { statements });
  }
  loopBody() { this.newlines(); this.loops++; const body = this.statement(); this.loops--; return body; }
  statement() {
    const token = this.peek();
    if (this.is('{')) return this.block();
    if (this.is(';')) { this.take(); return this.node('empty', token); }
    let result;
    if (this.is('if')) {
      this.take(); this.expect('('); const condition = this.expression(); this.expect(')'); this.newlines();
      const then = this.statement(); this.newlines(); let otherwise = null;
      if (this.is('else')) { this.take(); this.newlines(); otherwise = this.statement(); }
      result = this.node('if', token, { condition, then, otherwise });
    } else if (this.is('while')) {
      this.take(); this.expect('('); const condition = this.expression(); this.expect(')');
      result = this.node('while', token, { condition, body: this.loopBody() });
    } else if (this.is('do')) {
      this.take(); const body = this.loopBody(); this.newlines(); this.expect('while'); this.expect('(');
      const condition = this.expression(); this.expect(')'); this.endSimple(); result = this.node('do', token, { condition, body });
    } else if (this.is('for')) {
      this.take(); this.expect('(');
      if (this.peek().kind === 'name' && this.peek(1).text === 'in' && this.peek(2).kind === 'name' && this.peek(3).text === ')') {
        const variable = this.name(); this.expect('in'); const array = this.name(); this.expect(')');
        result = this.node('for-in', token, { variable, array, body: this.loopBody() });
      } else {
        const initial = this.is(';') ? null : this.expression(); this.expect(';'); this.newlines();
        const condition = this.is(';') ? null : this.expression(); this.expect(';'); this.newlines();
        const update = this.is(')') ? null : this.expression(); this.expect(')');
        result = this.node('for', token, { initial, condition, update, body: this.loopBody() });
      }
    } else { result = this.simple(); this.endSimple(); }
    result.statement = true; return result;
  }
  parenthesizedOutput() {
    let depth = 0;
    for (let i = this.index; i < this.tokens.length; i++) {
      if (this.tokens[i].text === '(') depth++;
      if (this.tokens[i].text === ')' && --depth === 0) {
        const following = this.tokens[i + 1];
        return following !== undefined && ([';', '}', '>', '>>'].includes(following.text) || ['newline', 'eof'].includes(following.kind));
      }
    }
    return false;
  }
  simple() {
    const token = this.peek();
    if (this.is('print') || this.is('printf')) {
      this.take(); const args = [];
      if (this.noValue() || this.is('>') || this.is('>>')) { if (token.text === 'printf') this.fail(); }
      else if (this.is('(') && this.parenthesizedOutput()) { this.take(); args.push(...this.expressionList()); this.expect(')'); }
      else args.push(...this.expressionList(false));
      let redirect = null;
      if (this.is('>') || this.is('>>')) {
        const operator = this.take(); redirect = { operator: operator.text, position: operator.position, target: this.concat(true) };
      }
      return this.node(token.text, token, { args, redirect });
    }
    if (this.is('delete')) {
      this.take(); const name = this.name(); let subscripts = null;
      if (this.is('[')) { this.take(); subscripts = this.expressionList(); this.expect(']'); }
      return this.node('delete', token, { nameToken: name, subscripts });
    }
    if (['next', 'break', 'continue', 'exit', 'return'].includes(token.text)) {
      this.take();
      if ((token.text === 'next' && ['BEGIN', 'END'].includes(this.context)) || (token.text === 'return' && this.context !== 'function')
          || (['break', 'continue'].includes(token.text) && this.loops === 0)) this.fail(token);
      const value = ['exit', 'return'].includes(token.text) && !this.noValue() ? this.expression() : null;
      return this.node(token.text, token, { value });
    }
    return this.node('expression', token, { expression: this.expression() });
  }
  expressionList(greater = true) {
    const values = [this.expression(greater)];
    while (this.is(',')) { this.take(); this.newlines(); values.push(this.expression(greater)); }
    return values;
  }
  expression(greater = true) {
    const left = this.conditional(greater);
    if (lvalue(left) && ASSIGNMENTS.has(this.peek().text)) {
      const operator = this.take(); return this.node('assignment', operator, { operator: operator.text, left, right: this.expression(greater) });
    }
    return left;
  }
  conditional(greater) {
    const condition = this.logical(greater, '||');
    if (!this.is('?')) return condition;
    const token = this.take(), then = this.conditional(greater); this.expect(':');
    return this.node('conditional', token, { condition, then, otherwise: this.conditional(greater) });
  }
  logical(greater, operator) {
    const next = () => operator === '||' ? this.logical(greater, '&&') : this.membership(greater);
    let left = next();
    while (this.is(operator)) { const token = this.take(); this.newlines(); left = this.node('binary', token, { operator, left, right: next() }); }
    return left;
  }
  membership(greater) {
    let result = this.comparison(greater);
    while (this.is('in')) { const token = this.take(), name = this.name(); result = this.node('in', token, { subscripts: [result], nameToken: name }); }
    return result;
  }
  comparison(greater) {
    let left = this.concat(greater);
    while (COMPARISONS.has(this.peek().text) && (greater || !this.is('>'))) {
      const token = this.take(); left = this.node('binary', token, { operator: token.text, left, right: this.concat(greater) });
    }
    return left;
  }
  concat(greater) {
    let left = this.additive(greater);
    while (concatenates(this.peek())) { const token = this.peek(); left = this.node('binary', token, { operator: 'concat', left, right: this.additive(greater) }); }
    return left;
  }
  additive(greater) {
    let left = this.multiplicative(greater);
    while (this.is('+') || this.is('-')) { const token = this.take(); left = this.node('binary', token, { operator: token.text, left, right: this.multiplicative(greater) }); }
    return left;
  }
  multiplicative(greater) {
    let left = this.unary(greater);
    while (['*', '/', '%'].includes(this.peek().text)) { const token = this.take(); left = this.node('binary', token, { operator: token.text, left, right: this.unary(greater) }); }
    return left;
  }
  unary(greater) {
    if (['!', '-', '+'].includes(this.peek().text)) {
      const token = this.take(); return this.node('unary', token, { operator: token.text, operand: this.unary(greater) });
    }
    const left = this.postfix(greater);
    if (!this.is('^')) return left;
    const token = this.take(); return this.node('binary', token, { operator: '^', left, right: this.unary(greater) });
  }
  increment(greater) { const token = this.take(); return this.node('increment', token, { operator: token.text, target: this.location(greater), prefix: true }); }
  postfix(greater) {
    if (this.is('++') || this.is('--')) return this.increment(greater);
    const target = this.atom(greater);
    if (lvalue(target) && (this.is('++') || this.is('--'))) { const token = this.take(); return this.node('increment', token, { operator: token.text, target, prefix: false }); }
    return target;
  }
  location(greater) {
    const token = this.peek();
    if (token.kind === 'name') {
      this.take();
      if (!this.is('[')) return this.node('variable', token, { nameToken: token });
      this.take(); const subscripts = this.expressionList(); this.expect(']'); return this.node('array', token, { nameToken: token, subscripts });
    }
    this.expect('$');
    const index = this.is('++') || this.is('--') ? this.increment(greater) : this.atom(greater);
    return this.node('field', token, { index });
  }
  atom(greater) {
    const token = this.peek();
    if (token.kind === 'number' || token.kind === 'string') { this.take(); return this.node('literal', token, { valueKind: token.kind, value: token.value }); }
    if (token.kind === 'name' || this.is('$')) return this.location(greater);
    if (token.kind === 'function' || token.kind === 'builtin') {
      this.take(); const args = [];
      if (!this.is('(')) { if (token.text !== 'length') this.fail(); }
      else { this.take(); if (!this.is(')')) args.push(...this.expressionList()); this.expect(')'); }
      if (token.kind === 'builtin') {
        const sizes = { length: [0, 1], substr: [2, 3], index: [2], split: [2, 3], toupper: [1], tolower: [1], close: [1], int: [1] };
        if ((token.text === 'sprintf' ? args.length === 0 : !sizes[token.text].includes(args.length))
            || (token.text === 'split' && args[1].kind !== 'variable')) this.fail(token);
      }
      return this.node(token.kind === 'builtin' ? 'builtin' : 'call', token, { name: token.text, args });
    }
    if (this.is('getline')) {
      this.take(); const target = this.peek().kind === 'name' || this.is('$') ? this.location(greater) : null;
      let file = null; if (this.is('<')) { this.take(); file = this.atom(greater); }
      return this.node('getline', token, { target, file });
    }
    if (this.is('(')) {
      this.take(); const expressions = this.expressionList(); this.expect(')');
      if (expressions.length === 1) return this.node('parenthesized', token, { expression: expressions[0] });
      this.expect('in'); return this.node('in', token, { subscripts: expressions, nameToken: this.name() });
    }
    this.fail();
  }
}

function children(node) {
  switch (node.kind) {
    case 'function': return [node.body];
    case 'rule': return [node.start, node.end, node.body].filter(Boolean);
    case 'block': return node.statements;
    case 'if': case 'conditional': return [node.condition, node.then, node.otherwise].filter(Boolean);
    case 'while': case 'do': return [node.condition, node.body];
    case 'for': return [node.initial, node.condition, node.update, node.body].filter(Boolean);
    case 'for-in': return [node.body];
    case 'delete': return node.subscripts || [];
    case 'return': case 'exit': return node.value === null ? [] : [node.value];
    case 'print': case 'printf': return [...node.args, ...(node.redirect === null ? [] : [node.redirect.target])];
    case 'expression': case 'parenthesized': return [node.expression];
    case 'binary': case 'assignment': return [node.left, node.right];
    case 'unary': return [node.operand];
    case 'increment': return [node.target];
    case 'array': case 'in': return node.subscripts;
    case 'field': return [node.index];
    case 'call': case 'builtin': return node.args;
    case 'getline': return [node.file, node.target].filter(Boolean);
    default: return [];
  }
}

module.exports = { Parser, children };
