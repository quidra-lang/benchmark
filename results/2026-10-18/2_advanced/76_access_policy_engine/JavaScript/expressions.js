'use strict';

function tokenize(text) {
  return text.match(/"[^"]*"|[0-9]+|[A-Za-z][A-Za-z0-9_.]*|==|!=|<=|>=|[()[\],+*<>-]/g) || [];
}

class Parser {
  constructor(text) {
    this.tokens = tokenize(text);
    this.position = 0;
  }

  peek() {
    return this.tokens[this.position];
  }

  take() {
    return this.tokens[this.position++];
  }

  chain(read, operators) {
    let expression = read();
    while (operators.includes(this.peek())) {
      const operation = this.take();
      expression = {kind: 'operation', operation, arguments: [expression, read()]};
    }
    return expression;
  }

  disjunction() {
    return this.chain(() => this.conjunction(), ['or']);
  }

  conjunction() {
    return this.chain(() => this.negation(), ['and']);
  }

  negation() {
    if (this.peek() !== 'not') return this.comparison();
    this.take();
    return {kind: 'operation', operation: 'not', arguments: [this.negation()]};
  }

  comparison() {
    const left = this.sum();
    if (!['==', '!=', '<', '<=', '>', '>=', 'in'].includes(this.peek())) return left;
    const operation = this.take();
    return {kind: 'operation', operation, arguments: [left, this.sum()]};
  }

  sum() {
    return this.chain(() => this.product(), ['+', '-']);
  }

  product() {
    return this.chain(() => this.unary(), ['*']);
  }

  unary() {
    if (this.peek() !== '-') return this.primary();
    this.take();
    return {kind: 'operation', operation: '-', arguments: [this.unary()]};
  }

  primary() {
    const token = this.take();
    if (token === '(') {
      const expression = this.disjunction();
      this.take();
      return expression;
    }
    if (token === '[') {
      const value = [];
      if (this.peek() !== ']') {
        for (;;) {
          value.push(this.take().slice(1, -1));
          if (this.peek() !== ',') break;
          this.take();
        }
      }
      this.take();
      return {kind: 'literal', value};
    }
    if (token.startsWith('"')) return {kind: 'literal', value: token.slice(1, -1)};
    if (/^[0-9]/.test(token)) return {kind: 'literal', value: Number(token)};
    if (token === 'true' || token === 'false') return {kind: 'literal', value: token === 'true'};
    if (token === 'it') return {kind: 'it'};
    if (token.includes('.')) return {kind: 'attribute', name: token};
    this.take();
    const argumentsList = [];
    if (this.peek() !== ')') {
      for (;;) {
        argumentsList.push(this.disjunction());
        if (this.peek() !== ',') break;
        this.take();
      }
    }
    this.take();
    return {kind: 'operation', operation: token, arguments: argumentsList};
  }
}

function parse(text) {
  return new Parser(text).disjunction();
}

module.exports = {tokenize, parse};
