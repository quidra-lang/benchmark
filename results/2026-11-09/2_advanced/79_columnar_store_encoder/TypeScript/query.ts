import type { Query, QueryItem, Condition, Literal } from './types.ts';

export function tokenize(text: string): string[] {
  return text.match(/[A-Z]+|[a-z][a-z0-9_]*|-?[0-9]+|'[a-z0-9_-]*'|<>|<=|>=|[=<>(),*]/g);
}

class Parser {
  tokens: string[];
  position: number;
  constructor(text: string) {
    this.tokens = tokenize(text);
    this.position = 0;
  }

  take(): string {
    return this.tokens[this.position++];
  }

  accept(token: string): boolean {
    if (this.tokens[this.position] !== token) return false;
    this.position++;
    return true;
  }

  literal(): Literal {
    const token = this.take();
    if (token[0] === "'") return {type: 'string', value: token.slice(1, -1)};
    if (token === 'TRUE' || token === 'FALSE') return {type: 'boolean', value: token === 'TRUE'};
    return {type: 'integer', value: Number(token)};
  }

  comparison(): Condition {
    const name = this.take();
    let operator = this.take();
    const literals = [];
    if (operator === 'IS') {
      if (this.accept('NOT')) operator = 'IS NOT NULL';
      else operator = 'IS NULL';
      this.take();
    } else if (operator === 'BETWEEN') {
      literals.push(this.literal());
      this.take();
      literals.push(this.literal());
    } else if (operator === 'IN') {
      this.take();
      do literals.push(this.literal()); while (this.accept(','));
      this.take();
    } else literals.push(this.literal());
    return {kind: 'comparison', name, operator, literals};
  }

  negation(): Condition {
    if (this.accept('NOT')) return {kind: 'NOT', child: this.negation()};
    if (this.accept('(')) {
      const condition = this.condition();
      this.take();
      return condition;
    }
    return this.comparison();
  }

  conjunction(): Condition {
    let left = this.negation();
    while (this.accept('AND')) left = {kind: 'AND', left, right: this.negation()};
    return left;
  }

  condition(): Condition {
    let left = this.conjunction();
    while (this.accept('OR')) left = {kind: 'OR', left, right: this.conjunction()};
    return left;
  }

  item(): QueryItem {
    const token = this.take();
    if (!this.accept('(')) return {kind: 'column', name: token};
    const distinct = this.accept('DISTINCT');
    const name = this.take();
    this.take();
    return {kind: 'aggregate', function: token, name: name === '*' ? null : name, distinct};
  }

  parse(): Query {
    this.take();
    const items = [];
    const star = this.accept('*');
    if (!star) do items.push(this.item()); while (this.accept(','));
    const result: Query = {star, items, condition: null, group: null, order: null, limit: null};
    if (this.accept('WHERE')) result.condition = this.condition();
    if (this.accept('GROUP')) {
      this.take();
      result.group = this.take();
    }
    if (this.accept('ORDER')) {
      this.take();
      const name = this.take();
      const descending = this.accept('DESC');
      if (!descending) this.accept('ASC');
      result.order = {name, descending};
    }
    if (this.accept('LIMIT')) result.limit = Number(this.take());
    return result;
  }
}

export const parse = (text: string): Query => new Parser(text).parse();
