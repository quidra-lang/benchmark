import type { Expression } from './types.ts';

export function tokenize(text: string): string[] {
  return text.match(/"[^"]*"|[0-9]+|[A-Za-z][A-Za-z0-9_.]*|==|!=|<=|>=|[()[\],+*<>-]/g) || [];
}

class Parser {
  tokens: string[];
  position: number;
  constructor(text: string) {
    this.tokens = tokenize(text);
    this.position = 0;
  }

  peek(): string {
    return this.tokens[this.position];
  }

  take(): string {
    return this.tokens[this.position++];
  }

  chain(read: () => Expression, operators: string[]): Expression {
    let expression = read();
    while (operators.includes(this.peek())) {
      const operation = this.take();
      expression = {kind: 'operation', operation, arguments: [expression, read()]};
    }
    return expression;
  }

  disjunction(): Expression {
    return this.chain(() => this.conjunction(), ['or']);
  }

  conjunction(): Expression {
    return this.chain(() => this.negation(), ['and']);
  }

  negation(): Expression {
    if (this.peek() !== 'not') return this.comparison();
    this.take();
    return {kind: 'operation', operation: 'not', arguments: [this.negation()]};
  }

  comparison(): Expression {
    const left = this.sum();
    if (!['==', '!=', '<', '<=', '>', '>=', 'in'].includes(this.peek())) return left;
    const operation = this.take();
    return {kind: 'operation', operation, arguments: [left, this.sum()]};
  }

  sum(): Expression {
    return this.chain(() => this.product(), ['+', '-']);
  }

  product(): Expression {
    return this.chain(() => this.unary(), ['*']);
  }

  unary(): Expression {
    if (this.peek() !== '-') return this.primary();
    this.take();
    return {kind: 'operation', operation: '-', arguments: [this.unary()]};
  }

  primary(): Expression {
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

export function parse(text: string): Expression {
  return new Parser(text).disjunction();
}

