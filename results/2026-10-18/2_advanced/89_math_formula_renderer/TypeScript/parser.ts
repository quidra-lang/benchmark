import { FormulaError } from './lexer.ts';
import type { FormulaToken, FormulaNode, ParsedFormula } from './types.ts';
const TERMINATORS = new Set(['}', '&', 'newline', 'right', 'end', 'eof']);
const ARGUMENTS = new Set(['identifier', 'number', 'symbol', 'command', 'text', 'eqref', '{', 'frac', 'binom', 'overset', 'underset', 'sqrt', 'accent']);
const emptyRow = (): FormulaNode => ({ kind: 'row', elements: [] });
export const collapse = (elements: FormulaNode[]): FormulaNode => elements.length === 1 ? elements[0] : { kind: 'row', elements };

export function checkBraces(tokens: FormulaToken[]): void {
  const stack: number[] = [];
  for (const token of tokens) {
    if (token.kind === '{') stack.push(token.column);
    else if (token.kind === '}') {
      if (stack.length === 0) throw new FormulaError(token.column, 'unmatched }');
      stack.pop();
    }
  }
  if (stack.length) throw new FormulaError(stack[stack.length - 1], 'unclosed {');
}

export class Parser {
  tokens: FormulaToken[];
  index: number;
  tag: FormulaToken | null;
  label: FormulaToken | null;
  constructor(tokens: FormulaToken[]) { this.tokens = tokens; this.index = 0; this.tag = null; this.label = null; }
  peek(): FormulaToken { return this.tokens[Math.min(this.index, this.tokens.length - 1)]; }
  read(): FormulaToken { const token = this.peek(); this.index++; return token; }
  unexpected(token: FormulaToken): never {
    const messages = { right: 'unexpected \\right', end: 'unexpected \\end', '&': 'misplaced &', newline: 'misplaced \\\\' };
    throw new FormulaError(token.column, messages[token.kind as keyof typeof messages]);
  }
  parse(): ParsedFormula {
    checkBraces(this.tokens);
    const elements = this.elementList(true);
    if (this.peek().kind !== 'eof') this.unexpected(this.peek());
    return { elements, tag: this.tag, label: this.label };
  }
  elementList(top = false, rootIndex = false): FormulaNode[] {
    const elements: FormulaNode[] = [];
    while (true) {
      const next = this.peek();
      if (TERMINATORS.has(next.kind) || (rootIndex && next.kind === 'symbol' && next.value === ']')) return elements;
      if (next.kind === 'tag' || next.kind === 'label') {
        if (!top) throw new FormulaError(next.column, 'misplaced \\' + next.kind);
        if ((next.kind === 'tag' ? this.tag : this.label) !== null) throw new FormulaError(next.column, 'duplicate \\' + next.kind);
        if (next.kind === 'tag') this.tag = this.read(); else this.label = this.read(); continue;
      }
      elements.push(this.element());
    }
  }
  element(): FormulaNode {
    const base = this.peek().kind === '^' || this.peek().kind === '_' ? emptyRow() : this.nucleus();
    let sub: FormulaNode | null = null, sup: FormulaNode | null = null;
    while (this.peek().kind === '^' || this.peek().kind === '_') {
      const token = this.read();
      if (token.kind === '^') {
        if (sup !== null) throw new FormulaError(token.column, 'double superscript');
        sup = this.argument('^');
      } else {
        if (sub !== null) throw new FormulaError(token.column, 'double subscript');
        sub = this.argument('_');
      }
    }
    return sub === null && sup === null ? base : { kind: 'script', base, sub, sup };
  }
  argument(name: string): FormulaNode {
    if (!ARGUMENTS.has(this.peek().kind)) throw new FormulaError(this.peek().column, 'missing argument for ' + name);
    return this.nucleus();
  }
  delimiter(): string {
    const token = this.read();
    if (token.kind === 'symbol' && ['(', ')', '[', ']', '|', '.'].includes(token.value)) return token.value;
    if (token.kind === 'command' && ['\\{', '\\}'].includes(token.value)) return token.value;
    throw new FormulaError(token.column, 'invalid delimiter');
  }
  nucleus(): FormulaNode {
    const token = this.read(), kind = token.kind;
    if (['identifier', 'number', 'symbol', 'command', 'text', 'eqref'].includes(kind)) {
      return { kind: 'atom', atom: kind === 'eqref' ? 'reference' : kind, value: token.value, column: token.column };
    }
    if (kind === '{') {
      const elements = this.elementList();
      if (this.peek().kind !== '}') this.unexpected(this.peek());
      this.read(); return collapse(elements);
    }
    if (['frac', 'binom', 'overset', 'underset'].includes(kind)) {
      const first = this.argument('\\' + kind), second = this.argument('\\' + kind);
      return kind === 'overset' || kind === 'underset' ? { kind: kind as 'overset'|'underset', placed: first, base: second } : { kind: kind as 'frac'|'binom', first, second };
    }
    if (kind === 'sqrt') {
      let index: FormulaNode | null = null;
      if (this.peek().kind === 'symbol' && this.peek().value === '[') {
        const opening = this.read(), elements = this.elementList(false, true);
        if (this.peek().kind !== 'symbol' || this.peek().value !== ']') throw new FormulaError(opening.column, 'missing ]');
        this.read(); index = collapse(elements);
      }
      const body = this.argument('\\sqrt');
      return index === null ? { kind: 'sqrt', body } : { kind: 'root', index, body };
    }
    if (kind === 'accent') return { kind: 'accent', name: token.value, body: this.argument('\\' + token.value) };
    if (kind === 'left') {
      const left = this.delimiter(), elements = this.elementList();
      if (this.peek().kind !== 'right') throw new FormulaError(token.column, 'missing \\right');
      const rightColumn = this.read().column, right = this.delimiter();
      return { kind: 'delim', left, right, body: collapse(elements), rightColumn };
    }
    return this.matrix(token);
  }
  matrix(begin: FormulaToken): FormulaNode {
    const rows: FormulaNode[][] = [[]];
    while (true) {
      rows[rows.length - 1].push(collapse(this.elementList()));
      const token = this.read();
      if (token.kind === '&') continue;
      if (token.kind === 'newline') { rows.push([]); continue; }
      if (token.kind !== 'end') throw new FormulaError(begin.column, 'missing \\end');
      if (token.value !== begin.value) throw new FormulaError(token.column, 'mismatched \\end');
      break;
    }
    const last = rows[rows.length - 1];
    if (rows.length >= 2 && last.length === 1 && last[0].kind === 'row' && last[0].elements.length === 0) rows.pop();
    const columns = Math.max(...rows.map(row => row.length));
    for (const row of rows) while (row.length < columns) row.push(emptyRow());
    return { kind: 'matrix', environment: begin.value, rows };
  }
}

