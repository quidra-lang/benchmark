import * as fs from 'node:fs';

class Expr {
  constructor(public k: string, public n = 0, public m = 0, public f = 0,
              public s = '', public a: Expr | null = null, public b: Expr | null = null,
              public args: Expr[] = []) {}
}
type Content = Expr | null;

const num = (n: number): Expr => new Expr('N', n);
const str = (s: string): Expr => new Expr('S', 0, 0, 0, s);
const err = (s: string): Expr => new Expr('E', 0, 0, 0, s);
const ref = (c: number, r: number, f: number): Expr => new Expr('R', c, r, f);
const unary = (a: Expr): Expr => new Expr('U', 0, 0, 0, '', a);
const binary = (s: string, a: Expr, b: Expr): Expr => new Expr('B', 0, 0, 0, s, a, b);
const invalid = new Expr('X');
const id = (a: Expr): number => a.m * 26 + a.n;
const label = (i: number): string => String.fromCharCode(65 + i % 26) + (Math.floor(i / 26) + 1);
const inside = (a: Expr): boolean => a.n >= 0 && a.n < 26 && a.m >= 0 && a.m < 99;
function range(a: Expr, b: Expr): Expr {
  let c = a.n, r = a.m, ac = a.f & 1, ar = a.f & 2;
  let d = b.n, t = b.m, bc = b.f & 1, br = b.f & 2;
  if (c > d) { [c, d] = [d, c]; [ac, bc] = [bc, ac]; }
  if (r > t) { [r, t] = [t, r]; [ar, br] = [br, ar]; }
  return new Expr('G', 0, 0, 0, '', ref(c, r, ac | ar), ref(d, t, bc | br));
}
function address(s: string): Expr {
  if (!/^[A-Z][1-9][0-9]?$/.test(s)) throw 'bad address';
  return ref(s.charCodeAt(0) - 65, Number(s.slice(1)) - 1, 0);
}
function area(s: string): Expr {
  const p = s.split(':');
  if (p.length > 2) throw 'bad address';
  const a = address(p[0]), b = p.length === 1 ? a : address(p[1]);
  return range(a, b);
}
function cells(g: Expr): number[] {
  const result = [];
  for (let r = g.a.m; r <= g.b.m; r++) for (let c = g.a.n; c <= g.b.n; c++) result.push(r * 26 + c);
  return result;
}
const contains = (g: Expr, r: Expr): boolean => r.n >= g.a.n && r.n <= g.b.n && r.m >= g.a.m && r.m <= g.b.m;
const levels = [['=', '<>', '<', '<=', '>', '>='], ['&'], ['+', '-'], ['*', '/']];
const precedence = (op: string): number => levels.findIndex(x => x.includes(op));
function parse(s: string): Expr {
  const tokens: [Expr, number][] = [];
  const syntax = (p: number): never => { throw 'syntax error at ' + p; };
  let i = 1;
  while (i < s.length) {
    const p = i + 1, ch = s[i];
    if (ch === ' ') { i++; continue; }
    if (/[0-9]/.test(ch)) {
      let j = i; while (j < s.length && /[0-9]/.test(s[j])) j++;
      if (j - i >= 10) syntax(p);
      tokens.push([num(Number(s.slice(i, j))), p]); i = j;
    } else if (ch === '"') {
      const j = s.indexOf('"', i + 1); if (j < 0) syntax(p);
      tokens.push([str(s.slice(i + 1, j)), p]); i = j + 1;
    } else if (/[A-Za-z$]/.test(ch)) {
      let j = i; while (j < s.length && /[A-Za-z0-9$]/.test(s[j])) j++;
      const word = s.slice(i, j).toUpperCase(), match = /^(\$?)([A-Z])(\$?)([1-9][0-9]?)$/.exec(word);
      let x: Expr;
      if (match) x = ref(match[2].charCodeAt(0) - 65, Number(match[4]) - 1, (match[1] ? 1 : 0) | (match[3] ? 2 : 0));
      else if (/^[A-Z][A-Z0-9]*$/.test(word)) x = new Expr(s.slice(j).trimStart().startsWith('(') ? 'C' : 'W', 0, 0, 0, word);
      else syntax(p);
      tokens.push([x, p]); i = j;
    } else {
      let op = s.slice(i, i + 2);
      if (!['<>', '<=', '>='].includes(op)) op = ch;
      if (!'+-*/&(),:=<>'.includes(ch)) syntax(p);
      tokens.push([new Expr('T', 0, 0, 0, op), p]); i += op.length;
    }
  }
  tokens.push([new Expr('Z'), s.length + 1]); i = 0;
  const take = (op: string): boolean => { if (tokens[i][0].k === 'T' && tokens[i][0].s === op) { i++; return true; } return false; };
  const expect = (op: string): void => { if (!take(op)) syntax(tokens[i][1]); };
  function expression(level = 0): Expr {
    if (level === 4) return atom();
    let a = expression(level + 1);
    while (tokens[i][0].k === 'T' && levels[level].includes(tokens[i][0].s)) {
      const op = tokens[i++][0].s; a = binary(op, a, expression(level + 1));
    }
    return a;
  }
  function atom(): Expr {
    if (take('-')) return unary(atom());
    const [x, p] = tokens[i++];
    if (['N', 'S', 'W'].includes(x.k)) return x;
    if (x.k === 'R') {
      if (!take(':')) return x;
      if (tokens[i][0].k !== 'R') syntax(tokens[i][1]);
      return range(x, tokens[i++][0]);
    }
    if (x.k === 'C') {
      expect('('); const args = [];
      if (!take(')')) { args.push(expression()); while (take(',')) args.push(expression()); expect(')'); }
      return new Expr('F', 0, 0, 0, x.s, null, null, args);
    }
    if (x.k === 'T' && x.s === '(') { const a = expression(); expect(')'); return a; }
    syntax(p);
  }
  const tree = expression(); if (tokens[i][0].k !== 'Z') syntax(tokens[i][1]); return tree;
}
function canonical(x: Expr): string {
  switch (x.k) {
    case 'N': return String(x.n);
    case 'S': return '"' + x.s + '"';
    case 'R': return (x.f & 1 ? '$' : '') + String.fromCharCode(65 + x.n) + (x.f & 2 ? '$' : '') + (x.m + 1);
    case 'G': return canonical(x.a) + ':' + canonical(x.b);
    case 'W': return x.s;
    case 'X': return '#REF!';
    case 'F': return x.s + '(' + x.args.map(canonical).join(',') + ')';
    case 'U': return '-' + (x.a.k === 'B' ? '(' + canonical(x.a) + ')' : canonical(x.a));
    case 'B': {
      let a = canonical(x.a), b = canonical(x.b);
      if (x.a.k === 'B' && precedence(x.a.s) < precedence(x.s)) a = '(' + a + ')';
      if (x.b.k === 'B' && precedence(x.b.s) <= precedence(x.s)) b = '(' + b + ')';
      return a + x.s + b;
    }
  }
}
const display = (x: Content): string => x === null ? '' : x.k === 'N' ? String(x.n) : x.s;
const notation = (x: Content): string => x === null ? '(empty)' : x.k === '=' ? '=' + canonical(x.a) : x.k === 'S' ? '"' + x.s + '"' : display(x);
const number = (x: Content): Expr => x === null ? num(0) : x.k === 'S' || x.k === 'G' ? err('#VALUE!') : x;
const string = (x: Content): Expr => x === null ? str('') : x.k === 'N' ? str(String(x.n)) : x.k === 'G' ? err('#VALUE!') : x;
function rewrite(x: Content, transform: (x: Expr) => Expr): Content {
  if (x === null) return null;
  if (x.k === 'R' || x.k === 'G') return transform(x);
  return new Expr(x.k, x.n, x.m, x.f, x.s, rewrite(x.a, transform), rewrite(x.b, transform), x.args.map(a => rewrite(a, transform)));
}
function dependencies(x: Content, result = new Set<number>()): Set<number> {
  if (x === null) return result;
  if (x.k === 'R') result.add(id(x));
  else if (x.k === 'G') for (const i of cells(x)) result.add(i);
  else { dependencies(x.a, result); dependencies(x.b, result); for (const a of x.args) dependencies(a, result); }
  return result;
}
class Sheet {
  contents: Content[];
  values: Content[];
  deps: Set<number>[];
  history: [string, Content[]][];
  constructor() { this.contents = Array(2574).fill(null); this.values = Array(2574).fill(null); this.deps = []; this.history = []; }
  recalculate(): void {
    const contents = this.contents;
    this.deps = contents.map(x => x?.k === '=' ? dependencies(x.a) : new Set());
    this.values = contents.map(x => x?.k === '=' ? null : x);
    const indices: number[] = Array(2574).fill(-1), low: number[] = [], stack: number[] = [], on = new Set<number>(), cyclic = new Set<number>(); let serial = 0;
    const visit = (i: number): void => {
      indices[i] = low[i] = serial++; stack.push(i); on.add(i);
      for (const j of this.deps[i]) if (contents[j]?.k === '=') {
        if (indices[j] < 0) { visit(j); low[i] = Math.min(low[i], low[j]); }
        else if (on.has(j)) low[i] = Math.min(low[i], indices[j]);
      }
      if (low[i] === indices[i]) {
        const part = []; let j; do { j = stack.pop(); on.delete(j); part.push(j); } while (j !== i);
        if (part.length > 1 || this.deps[i].has(i)) for (const j of part) cyclic.add(j);
      }
    };
    for (let i = 0; i < 2574; i++) if (contents[i]?.k === '=' && indices[i] < 0) visit(i);
    const done = new Set<number>();
    const calculate = (i: number): void => {
      if (contents[i]?.k !== '=' || done.has(i)) return;
      done.add(i);
      if (cyclic.has(i)) { this.values[i] = err('#CYCLE!'); return; }
      for (const j of this.deps[i]) calculate(j);
      const v = this.evaluate(contents[i].a); this.values[i] = v === null ? num(0) : v.k === 'G' ? err('#VALUE!') : v;
    };
    for (let i = 0; i < 2574; i++) calculate(i);
  }
  evaluate(x: Expr): Content {
    if (x.k === 'N' || x.k === 'S' || x.k === 'G') return x;
    if (x.k === 'R') return this.values[id(x)];
    if (x.k === 'W') return err('#NAME?');
    if (x.k === 'X') return err('#REF!');
    if (x.k === 'U') { const a = number(this.evaluate(x.a)); return a.k === 'E' ? a : num(-a.n); }
    if (x.k === 'B') {
      let a = this.evaluate(x.a), b = this.evaluate(x.b);
      if (a?.k === 'E') return a; if (b?.k === 'E') return b;
      if (precedence(x.s) === 0) {
        if (a?.k === 'G' || b?.k === 'G') return err('#VALUE!');
        const text = a?.k === 'S' || b?.k === 'S';
        a = a || (text ? str('') : num(0)); b = b || (text ? str('') : num(0));
        const c = a.k !== b.k ? (a.k === 'N' ? -1 : 1) : a.k === 'N' ? Math.sign(a.n - b.n) : a.s < b.s ? -1 : a.s > b.s ? 1 : 0;
        return num(Number({'=': c === 0, '<>': c !== 0, '<': c < 0, '<=': c <= 0, '>': c > 0, '>=': c >= 0}[x.s]));
      }
      a = x.s === '&' ? string(a) : number(a); b = x.s === '&' ? string(b) : number(b);
      if (a.k === 'E') return a; if (b.k === 'E') return b;
      switch (x.s) {
        case '&': return str(a.s + b.s); case '+': return num(a.n + b.n); case '-': return num(a.n - b.n); case '*': return num(a.n * b.n);
        default: return b.n === 0 ? err('#DIV/0!') : num(Math.trunc(a.n / b.n));
      }
    }
    const name = x.s, args = x.args, aggregates = ['SUM', 'MIN', 'MAX', 'COUNT', 'AVERAGE', 'AND', 'OR', 'CONCAT'];
    if (![...aggregates, 'IF', 'ABS', 'NOT', 'LEN'].includes(name)) return err('#NAME?');
    if (aggregates.includes(name)) {
      if (!args.length) return err('#VALUE!');
      const items: Content[] = [];
      for (const a of args) { const v = this.evaluate(a); if (v?.k === 'G') items.push(...cells(v).map(i => this.values[i])); else items.push(v); }
      const ns = items.filter(a => a?.k === 'N').map(a => a.n);
      if (name === 'COUNT') return num(ns.length);
      const error = items.find(a => a?.k === 'E'); if (error) return error;
      if (name === 'CONCAT') return str(items.map(a => string(a).s).join(''));
      const sum = ns.reduce((a, b) => a + b, 0);
      switch (name) {
        case 'SUM': return num(sum); case 'MIN': return num(ns.length ? Math.min(...ns) : 0); case 'MAX': return num(ns.length ? Math.max(...ns) : 0);
        case 'AVERAGE': return ns.length ? num(Math.trunc(sum / ns.length)) : err('#DIV/0!');
        case 'AND': return ns.length ? num(Number(ns.every(n => n !== 0))) : err('#VALUE!');
        default: return ns.length ? num(Number(ns.some(n => n !== 0))) : err('#VALUE!');
      }
    }
    if (name === 'IF') {
      if (args.length !== 2 && args.length !== 3) return err('#VALUE!');
      const c = number(this.evaluate(args[0])); if (c.k === 'E') return c;
      return c.n !== 0 ? this.evaluate(args[1]) : args.length === 3 ? this.evaluate(args[2]) : num(0);
    }
    if (args.length !== 1) return err('#VALUE!');
    const v = name === 'LEN' ? string(this.evaluate(args[0])) : number(this.evaluate(args[0]));
    return v.k === 'E' ? v : num(name === 'LEN' ? v.s.length : name === 'ABS' ? Math.abs(v.n) : Number(v.n === 0));
  }
  replace(next: Content[]): number {
    const old = this.values; this.contents = next; this.recalculate();
    return old.reduce((n, v, i) => n + Number(notation(v) !== notation(this.values[i])), 0);
  }
  describe(i: number): string { return label(i) + ': ' + notation(this.contents[i]) + ' -> ' + notation(this.values[i]); }
  execute(line: string): string[] {
    const p = line.indexOf(' '), name = p < 0 ? line : line.slice(0, p), rest = p < 0 ? '' : line.slice(p + 1);
    if (name === 'SHOW') return [this.describe(id(address(rest)))];
    if (name === 'LIST') { const out = []; for (let i = 0; i < 2574; i++) if (this.contents[i] !== null) out.push(this.describe(i)); return out.length ? out : ['(no cells)']; }
    if (name === 'DEPS') {
      const i = id(address(rest)), ps = [...(this.deps[i] || [])].sort((a,b) => a-b), ds = [];
      for (let j = 0; j < 2574; j++) if (this.deps[j]?.has(i)) ds.push(j);
      const format = (xs: number[]): string => xs.map(label).join(',') || 'none';
      return [rest + ': precedents=' + format(ps) + ' dependents=' + format(ds)];
    }
    if (name === 'PRINT') {
      const g = area(rest), rw = String(g.b.m + 1).length, widths = [];
      for (let c = g.a.n; c <= g.b.n; c++) { let w = 1; for (let r = g.a.m; r <= g.b.m; r++) w = Math.max(w, display(this.values[r * 26 + c]).length); widths.push(w); }
      const sep = '+' + '-'.repeat(rw) + '+' + widths.map(w => '-'.repeat(w) + '+').join('');
      const out = [sep, '|' + ' '.repeat(rw) + '|' + widths.map((w, j) => String.fromCharCode(65 + g.a.n + j).padEnd(w) + '|').join(''), sep];
      for (let r = g.a.m; r <= g.b.m; r++) out.push('|' + String(r + 1).padStart(rw) + '|' + widths.map((w, j) => { const v = this.values[r * 26 + g.a.n + j]; return (v?.k === 'N' ? display(v).padStart(w) : display(v).padEnd(w)) + '|'; }).join(''));
      out.push(sep); return out;
    }
    if (name === 'UNDO') {
      if (!this.history.length) throw 'nothing to undo';
      const [command, old] = this.history.pop(); return ['UNDO ' + command + ' changed=' + this.replace(old)];
    }
    let next = this.contents.slice(), target = -1;
    if (name === 'SET') {
      const split = rest.indexOf(' '), a = rest.slice(0, split), text = rest.slice(split + 1); target = id(address(a));
      if (text.startsWith('=')) next[target] = new Expr('=', 0, 0, 0, '', parse(text));
      else if (/^"[^"]*"$/.test(text)) next[target] = str(text.slice(1, -1));
      else if (/^(0|-?[1-9][0-9]{0,8})$/.test(text)) next[target] = num(Number(text));
      else throw 'bad value';
    } else if (name === 'CLEAR') { for (const i of cells(area(rest))) next[i] = null; }
    else if (name === 'COPY' || name === 'MOVE') {
      const [a, b] = rest.split(' '), source = area(a), dest = address(b), dc = dest.n - source.a.n, dr = dest.m - source.a.m;
      const shift = (r: Expr, relative: boolean): Expr => ref(r.n + (relative && r.f & 1 ? 0 : dc), r.m + (relative && r.f & 2 ? 0 : dr), r.f);
      const destination = range(shift(source.a, false), shift(source.b, false));
      if (!inside(destination.a) || !inside(destination.b)) throw 'out of grid';
      const transform = (x: Expr): Expr => {
        if (x.k === 'R') {
          if (name === 'COPY') { const a = shift(x, true); return inside(a) ? a : invalid; }
          return contains(source, x) ? shift(x, false) : contains(destination, x) ? invalid : x;
        }
        if (name === 'MOVE' && !(contains(source, x.a) && contains(source, x.b))) return x;
        const a = shift(x.a, name === 'COPY'), b = shift(x.b, name === 'COPY');
        return inside(a) && inside(b) ? range(a, b) : invalid;
      };
      if (name === 'MOVE') next = next.map(x => rewrite(x, transform));
      const moving = cells(source).map((i): [number, Content] => [i, name === 'COPY' ? rewrite(this.contents[i], transform) : next[i]]);
      if (name === 'MOVE') for (const [i] of moving) next[i] = null;
      for (const [i, x] of moving) next[i + dr * 26 + dc] = x;
    } else if (['INSERTROW', 'DELETEROW', 'INSERTCOL', 'DELETECOL'].includes(name)) {
      const row = name.endsWith('ROW'), insert = name.startsWith('INSERT');
      if (!(row ? /^[1-9][0-9]?$/.test(rest) : /^[A-Z]$/.test(rest))) throw 'bad address';
      const at = row ? Number(rest) - 1 : rest.charCodeAt(0) - 65, limit = row ? 99 : 26;
      const axis = (x: Expr): number => row ? x.m : x.n, change = (x: Expr, v: number): Expr => ref(row ? x.n : v, row ? v : x.m, x.f);
      if (insert && next.some((x, i) => x !== null && (row ? Math.floor(i / 26) : i % 26) === limit - 1)) throw 'last ' + (row ? 'row' : 'column') + ' not empty';
      const transform = (x: Expr): Expr => {
        if (x.k === 'R') {
          const v = axis(x); if (!insert && v === at) return invalid;
          const n = v + (insert ? Number(v >= at) : -Number(v > at)); return n >= limit ? invalid : change(x, n);
        }
        const a = axis(x.a), b = axis(x.b);
        if (!insert && a === at && b === at) return invalid;
        const u = a + (insert ? Number(a >= at) : -Number(a > at)), v = b + (insert ? Number(b >= at) : -Number(b >= at));
        return v >= limit ? invalid : range(change(x.a, u), change(x.b, v));
      };
      const result = Array(2574).fill(null);
      for (let i = 0; i < 2574; i++) if (next[i] !== null) {
        const r = ref(i % 26, Math.floor(i / 26), 0), v = axis(r);
        if (!insert && v === at) continue;
        const t = change(r, v + (insert ? Number(v >= at) : -Number(v > at))); result[id(t)] = rewrite(next[i], transform);
      }
      next = result;
    } else throw 'unknown command';
    this.history.push([name, this.contents]); const changed = this.replace(next);
    return [name + (name === 'SET' ? ' ' + label(target) + '=' + notation(this.values[target]) : '') + ' changed=' + changed];
  }
}
const lines = fs.readFileSync(0, 'utf8').split(/\r?\n/), sheet = new Sheet(), output: string[] = [];
for (let i = 1; i <= Number(lines[0]); i++) {
  try { output.push(...sheet.execute(lines[i])); } catch (e) { output.push('ERROR ' + e); }
}
process.stdout.write(output.join('\n') + '\n');
