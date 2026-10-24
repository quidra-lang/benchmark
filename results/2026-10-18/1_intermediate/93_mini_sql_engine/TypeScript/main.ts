import * as fs from 'node:fs';

type Value = number | string | null;
type SqlType = 'INT' | 'TEXT' | 'NULL';
interface Token { kind: string; text: string; value: Value; }
interface Column { name: string; type: SqlType; primary: number; notNull: boolean; }
interface Table { columns: Column[]; rows: Value[][]; }
interface TableRef { name: string; alias: string; }
interface ScopePart { name: string; table: Table; offset: number; }
interface Join { table: TableRef; condition: Expr; left: boolean; }
interface SelectItem { expr: Expr; alias: string | null; heading: string; }
interface OrderItem { expr: Expr; descending: boolean; ordinal: number | null; alias: string | null; selected: number; }
interface ResultRow { values: Value[]; keys: Value[]; }
class Expr {
    index = -1;
    table: string | null = null;
    column = '';
    text = '';
    distinct = false;
    constructor(public kind: string, public op = '', public value: Value = null, public args: Expr[] = []) {}
}
class Query {
    distinct = false;
    star = false;
    items: SelectItem[] = [];
    from: TableRef;
    joins: Join[] = [];
    where: Expr | null = null;
    group: Expr[] | null = null;
    having: Expr | null = null;
    order: OrderItem[] = [];
    limit: number | null = null;
    offset = 0;
}
class Command {
    name = '';
    columns: Column[] = [];
    names: string[] | null = null;
    tuples: Expr[][] = [];
    assignments: [string, Expr][] = [];
    where: Expr | null = null;
    query: Query | null = null;
    constructor(public kind: string) {}
}
class SqlError extends Error {}
const fail = (reason: string): never => { throw new SqlError(reason); };
const reserved = new Set('SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT'.split(' '));
const aggregates = new Set(['COUNT', 'SUM', 'MIN', 'MAX', 'AVG']);
const comparison = new Set(['=', '<>', '!=', '<', '<=', '>', '>=']);
const compatible = (a: SqlType, b: SqlType): boolean => a === b || a === 'NULL' || b === 'NULL';
const written = (v: Value): string => v === null ? 'NULL' : String(v);
const truth = (v: Value): boolean => v !== null && v !== 0;
const inverse = (v: Value): Value => v === null ? null : v === 0 ? 1 : 0;
const conjunction = (a: Value, b: Value): Value => a === 0 || b === 0 ? 0 : a === null || b === null ? null : 1;
const disjunction = (a: Value, b: Value): Value => truth(a) || truth(b) ? 1 : a === null || b === null ? null : 0;
const compare = (a: Value, b: Value): number => a === b ? 0 : a === null ? -1 : b === null ? 1 : a < b ? -1 : 1;
const rowKey = (row: Value[]): string => JSON.stringify(row);

function* statements(input: string): Generator<string> {
    let start = 0;
    for (let p = 0; p < input.length; p++) {
        if (input[p] === "'") p = input.indexOf("'", p + 1);
        else if (input.startsWith('--', p)) { const end = input.indexOf('\n', p); p = end < 0 ? input.length : end; }
        else if (input[p] === ';') { yield input.slice(start, p + 1); start = p + 1; }
    }
}
function tokenize(text: string): Token[] {
    const result: Token[] = [];
    for (let p = 0; p < text.length;) {
        const ch = text[p];
        if (ch === ' ' || ch === '\n' || ch === '\r') { p++; continue; }
        if (text.startsWith('--', p)) { const end = text.indexOf('\n', p); p = end < 0 ? text.length : end + 1; continue; }
        if (ch === "'") { const end = text.indexOf("'", p + 1); result.push({kind: 'string', text: text.slice(p, end + 1), value: text.slice(p + 1, end)}); p = end + 1; }
        else if (/[0-9]/.test(ch)) {
            const start = p; while (p < text.length && /[0-9]/.test(text[p])) p++;
            const word = text.slice(start, p); result.push({kind: 'integer', text: word, value: Number(word)});
        } else if (/[A-Za-z_]/.test(ch)) {
            const start = p; while (p < text.length && /[A-Za-z0-9_]/.test(text[p])) p++;
            const word = text.slice(start, p), upper = word.toUpperCase();
            result.push({kind: reserved.has(upper) ? 'reserved' : 'name', text: word, value: reserved.has(upper) ? upper : word});
        } else {
            let word = text.slice(p, p + 2);
            if (!['<>', '!=', '<=', '>=', '||'].includes(word)) word = ch;
            if (!['<>', '!=', '<=', '>=', '||'].includes(word) && !'(),.;*/%+-=<>'.includes(ch)) fail("unexpected character '" + ch + "'");
            result.push({kind: 'symbol', text: word, value: word}); p += word.length;
        }
    }
    result.push({kind: 'end', text: '', value: ''}); return result;
}
function heading(tokens: Token[]): string {
    let text = '';
    tokens.forEach((token, i) => { if (i > 0 && tokens[i - 1].kind !== 'symbol' && token.kind !== 'symbol') text += ' '; text += token.text; });
    return text;
}
class Parser {
    position = 0;
    constructor(public tokens: Token[]) {}
    current(): Token { return this.tokens[this.position]; }
    at(word: string): boolean { const t = this.current(); return (t.kind === 'reserved' || t.kind === 'symbol') && t.value === word; }
    take(word: string): boolean { if (!this.at(word)) return false; this.position++; return true; }
    syntax(): never { return fail("syntax error at '" + this.current().text + "'"); }
    expect(word: string): void { if (!this.take(word)) this.syntax(); }
    name(): string { const token = this.current(); if (token.kind !== 'name') this.syntax(); this.position++; return token.text; }
    integer(): number { const token = this.current(); if (token.kind !== 'integer') this.syntax(); this.position++; return token.value as number; }
    list<T>(read: () => T): T[] { const values = [read()]; while (this.take(',')) values.push(read()); return values; }
    reference(): Expr {
        const first = this.name(), e = new Expr('reference');
        if (this.take('.')) { e.table = first; e.column = this.name(); e.text = first + '.' + e.column; }
        else { e.column = first; e.text = first; }
        return e;
    }
    expression(level = 0): Expr {
        if (level === 2 && this.take('NOT')) return new Expr('unary', 'NOT', null, [this.expression(2)]);
        if (level === 6 && this.take('-')) return new Expr('unary', '-', null, [this.expression(6)]);
        if (level === 7) return this.primary();
        let left = this.expression(level + 1);
        if (level === 3) {
            if (comparison.has(String(this.current().value)) && this.current().kind === 'symbol') {
                const op = this.current().text; this.position++; return new Expr('binary', op, null, [left, this.expression(4)]);
            }
            if (this.take('IS')) { const not = this.take('NOT'); this.expect('NULL'); return new Expr('isnull', not ? 'NOT' : '', null, [left]); }
            const not = this.take('NOT');
            let result: Expr | null = null;
            if (this.take('IN')) { this.expect('('); const args = this.list(() => this.expression()); this.expect(')'); result = new Expr('in', '', null, [left, ...args]); }
            else if (this.take('BETWEEN')) { const low = this.expression(4); this.expect('AND'); result = new Expr('between', '', null, [left, low, this.expression(4)]); }
            else if (this.take('LIKE')) result = new Expr('like', '', null, [left, this.expression(4)]);
            else if (not) this.syntax();
            if (result) { result.op = not ? 'NOT' : ''; return result; }
            return left;
        }
        const ops = [['OR'], ['AND'], [], [], ['+', '-', '||'], ['*', '/', '%'], []][level];
        while (ops.some(op => this.at(op))) { const op = String(this.current().value); this.position++; left = new Expr('binary', op, null, [left, this.expression(level + 1)]); }
        return left;
    }
    primary(): Expr {
        const t = this.current();
        if (t.kind === 'integer' || t.kind === 'string') { this.position++; return new Expr('literal', '', t.value); }
        if (this.take('NULL')) return new Expr('literal');
        if (this.take('(')) { const e = this.expression(); this.expect(')'); return new Expr('group', '', null, [e]); }
        if (t.kind === 'name') return this.reference();
        if (t.kind === 'reserved' && aggregates.has(t.value as string)) {
            this.position++; const e = new Expr('aggregate', t.value as string); this.expect('(');
            if (e.op === 'COUNT' && this.take('*')) { this.expect(')'); return e; }
            e.distinct = this.take('DISTINCT'); e.args.push(this.expression()); this.expect(')'); return e;
        }
        return this.syntax();
    }
    table(): TableRef { const name = this.name(); let alias = name; if (this.take('AS')) alias = this.name(); else if (this.current().kind === 'name') alias = this.name(); return {name, alias}; }
    selectItem(): SelectItem {
        const start = this.position, expr = this.expression(), tokens = this.tokens.slice(start, this.position);
        let alias: string | null = null;
        if (this.take('AS')) alias = this.name(); else if (this.current().kind === 'name') alias = this.name();
        return {expr, alias, heading: alias ?? (expr.kind === 'reference' ? expr.column : heading(tokens))};
    }
    orderItem(): OrderItem {
        const start = this.position, expr = this.expression(), token = this.tokens[start], single = this.position === start + 1;
        const descending = this.take('DESC'); if (!descending) this.take('ASC');
        return {expr, descending, ordinal: single && token.kind === 'integer' ? token.value as number : null, alias: single && token.kind === 'name' ? token.text : null, selected: -1};
    }
    query(): Query {
        const q = new Query(); q.distinct = this.take('DISTINCT'); q.star = this.take('*');
        if (!q.star) q.items = this.list(() => this.selectItem());
        this.expect('FROM'); q.from = this.table();
        while (this.at('JOIN') || this.at('INNER') || this.at('LEFT')) {
            const left = this.take('LEFT'); if (left) this.take('OUTER'); else this.take('INNER');
            this.expect('JOIN'); const table = this.table(); this.expect('ON'); q.joins.push({table, condition: this.expression(), left});
        }
        if (this.take('WHERE')) q.where = this.expression();
        if (this.take('GROUP')) { this.expect('BY'); q.group = this.list(() => this.reference()); }
        if (this.take('HAVING')) q.having = this.expression();
        if (this.take('ORDER')) { this.expect('BY'); q.order = this.list(() => this.orderItem()); }
        if (this.take('LIMIT')) { q.limit = this.integer(); if (this.take('OFFSET')) q.offset = this.integer(); }
        return q;
    }
    column(): Column {
        const name = this.name(); let type: SqlType;
        if (this.take('INT')) type = 'INT'; else if (this.take('TEXT')) type = 'TEXT'; else return this.syntax();
        let primary = 0, notNull = false;
        while (this.at('PRIMARY') || this.at('NOT')) {
            if (this.take('PRIMARY')) { this.expect('KEY'); primary++; notNull = true; }
            else { this.expect('NOT'); this.expect('NULL'); notNull = true; }
        }
        return {name, type, primary, notNull};
    }
    parse(): Command {
        let c: Command;
        if (this.take(';')) c = new Command('empty');
        else {
            if (this.take('CREATE')) { c = new Command('create'); this.expect('TABLE'); c.name = this.name(); this.expect('('); c.columns = this.list(() => this.column()); this.expect(')'); }
            else if (this.take('DROP')) { c = new Command('drop'); this.expect('TABLE'); c.name = this.name(); }
            else if (this.take('INSERT')) {
                c = new Command('insert'); this.expect('INTO'); c.name = this.name();
                if (this.take('(')) { c.names = this.list(() => this.name()); this.expect(')'); }
                this.expect('VALUES'); c.tuples = this.list(() => { this.expect('('); const tuple = this.list(() => this.expression()); this.expect(')'); return tuple; });
            } else if (this.take('UPDATE')) {
                c = new Command('update'); c.name = this.name(); this.expect('SET');
                c.assignments = this.list((): [string, Expr] => { const name = this.name(); this.expect('='); return [name, this.expression()]; });
                if (this.take('WHERE')) c.where = this.expression();
            } else if (this.take('DELETE')) { c = new Command('delete'); this.expect('FROM'); c.name = this.name(); if (this.take('WHERE')) c.where = this.expression(); }
            else if (this.take('SELECT')) { c = new Command('select'); c.query = this.query(); }
            else if (this.take('EXIT')) c = new Command('exit');
            else return this.syntax();
            this.expect(';');
        }
        if (this.current().kind !== 'end') this.syntax();
        return c;
    }
}

function resolve(e: Expr, scope: ScopePart[]): number {
    if (e.table !== null) {
        const part = scope.find(p => p.name === e.table); if (!part) fail('unknown table ' + e.table);
        const index = part.table.columns.findIndex(c => c.name === e.column); if (index < 0) fail('unknown column ' + e.text);
        return e.index = part.offset + index;
    }
    const matches = scope.flatMap(p => p.table.columns.flatMap((c, i) => c.name === e.column ? [p.offset + i] : []));
    if (matches.length === 0) fail('unknown column ' + e.column);
    if (matches.length > 1) fail('ambiguous column ' + e.column);
    return e.index = matches[0];
}
function check(e: Expr, scope: ScopePart[], allow: boolean, grouping: Set<number> | null, inside = false): SqlType {
    if (e.kind === 'literal') return e.value === null ? 'NULL' : typeof e.value === 'number' ? 'INT' : 'TEXT';
    if (e.kind === 'reference') {
        const index = resolve(e, scope);
        if (grouping !== null && !inside && !grouping.has(index)) fail('column ' + e.text + ' is not grouped');
        for (const part of scope) if (index >= part.offset && index < part.offset + part.table.columns.length) return part.table.columns[index - part.offset].type;
    }
    if (e.kind === 'aggregate') {
        if (!allow || inside) fail('misuse of aggregate ' + e.op);
        if (e.args.length === 0) return 'INT';
        const type = check(e.args[0], scope, true, grouping, true);
        if ((e.op === 'SUM' || e.op === 'AVG') && !compatible(type, 'INT')) fail('type mismatch for ' + e.op);
        return e.op === 'MIN' || e.op === 'MAX' ? type : 'INT';
    }
    const types = e.args.map(a => check(a, scope, allow, grouping, inside));
    if (e.kind === 'group') return types[0];
    if (e.kind === 'isnull') return 'INT';
    let op = e.op, result: SqlType = 'INT';
    if (e.kind === 'in' || e.kind === 'between') {
        op = e.kind === 'in' ? 'IN' : 'BETWEEN';
        if (types.slice(1).some(t => !compatible(t, types[0]))) fail('type mismatch for ' + op);
    } else if (e.kind === 'binary' && comparison.has(op)) {
        if (!compatible(types[0], types[1])) fail('type mismatch for ' + op);
    } else {
        if (e.kind === 'like') op = 'LIKE';
        const required: SqlType = op === '||' || op === 'LIKE' ? 'TEXT' : 'INT';
        if (types.some(t => !compatible(t, required))) fail('type mismatch for ' + op);
        result = op === '||' ? 'TEXT' : 'INT';
    }
    return result;
}
function condition(e: Expr, scope: ScopePart[], allow: boolean, grouping: Set<number> | null, name: string): void {
    if (!compatible(check(e, scope, allow, grouping), 'INT')) fail('type mismatch for ' + name);
}
function hasAggregate(e: Expr): boolean { return e.kind === 'aggregate' || e.args.some(hasAggregate); }
function relation(op: string, a: Value, b: Value): Value {
    if (a === null || b === null) return null;
    const c = compare(a, b);
    return ({'=': c === 0, '<>': c !== 0, '!=': c !== 0, '<': c < 0, '<=': c <= 0, '>': c > 0, '>=': c >= 0} as Record<string, boolean>)[op] ? 1 : 0;
}
function like(text: string, pattern: string): boolean {
    let previous = Array(text.length + 1).fill(false); previous[0] = true;
    for (const ch of pattern) {
        const current = Array(text.length + 1).fill(false); current[0] = ch === '%' && previous[0];
        for (let i = 1; i <= text.length; i++) current[i] = ch === '%' ? previous[i] || current[i - 1] : previous[i - 1] && (ch === '_' || ch === text[i - 1]);
        previous = current;
    }
    return previous[text.length];
}
function evaluate(e: Expr, row: Value[], group: Value[][] | null): Value {
    if (e.kind === 'literal') return e.value;
    if (e.kind === 'reference') return row[e.index];
    if (e.kind === 'aggregate') {
        const rows = group!;
        if (e.args.length === 0) return rows.length;
        let values = rows.map(r => evaluate(e.args[0], r, null)).filter(v => v !== null);
        if (e.distinct) values = [...new Set(values)];
        if (e.op === 'COUNT') return values.length;
        if (values.length === 0) return null;
        if (e.op === 'MIN' || e.op === 'MAX') return values.reduce((a, b) => (compare(a, b) <= 0) === (e.op === 'MIN') ? a : b);
        const sum = (values as number[]).reduce((a, b) => a + b, 0);
        return e.op === 'SUM' ? sum : Math.trunc(sum / values.length);
    }
    const values = e.args.map(a => evaluate(a, row, group)), a = values[0], b = values[1];
    if (e.kind === 'group') return a;
    if (e.kind === 'unary') return e.op === 'NOT' ? inverse(a) : a === null ? null : -(a as number);
    if (e.kind === 'isnull') return e.op === 'NOT' ? (a === null ? 0 : 1) : (a === null ? 1 : 0);
    let result: Value;
    if (e.kind === 'in') result = a === null ? null : values.slice(1).some(v => v !== null && v === a) ? 1 : values.slice(1).includes(null) ? null : 0;
    else if (e.kind === 'between') result = conjunction(relation('>=', a, b), relation('<=', a, values[2]));
    else if (e.kind === 'like') result = a === null || b === null ? null : like(a as string, b as string) ? 1 : 0;
    else {
        if (comparison.has(e.op)) return relation(e.op, a, b);
        if (e.op === 'AND') return conjunction(a, b);
        if (e.op === 'OR') return disjunction(a, b);
        if (a === null || b === null) return null;
        if (e.op === '||') return (a as string) + (b as string);
        const x = a as number, y = b as number;
        switch (e.op) {
            case '+': return x + y;
            case '-': return x - y;
            case '*': return x * y;
            case '/': return y === 0 ? null : Math.trunc(x / y);
            case '%': return y === 0 ? null : x % y;
        }
        throw new Error('invalid expression');
    }
    return e.op === 'NOT' ? inverse(result) : result;
}

class Database {
    tables = new Map<string, Table>();
    table(name: string): Table { const table = this.tables.get(name); if (!table) fail('unknown table ' + name); return table; }
    targets(table: Table, names: string[]): number[] {
        const seen = new Set<string>();
        return names.map(name => { const index = table.columns.findIndex(c => c.name === name); if (index < 0) fail('unknown column ' + name); if (seen.has(name)) fail('duplicate column ' + name); seen.add(name); return index; });
    }
    constraints(table: Table, rows: Value[][], targets: number[]): void {
        const primary = table.columns.findIndex(c => c.primary > 0);
        for (const i of targets) {
            for (let c = 0; c < table.columns.length; c++) if (table.columns[c].notNull && rows[i][c] === null) fail('NULL value in column ' + table.columns[c].name);
            if (primary >= 0 && rows.some((row, j) => j !== i && row[primary] === rows[i][primary])) fail('duplicate primary key ' + written(rows[i][primary]));
        }
    }
    select(q: Query): string[] {
        const scope: ScopePart[] = [], names = new Set<string>();
        const add = (ref: TableRef): void => {
            const table = this.table(ref.name);
            if (names.has(ref.alias)) fail('duplicate table name ' + ref.alias);
            names.add(ref.alias); const offset = scope.reduce((n, p) => n + p.table.columns.length, 0); scope.push({name: ref.alias, table, offset});
        };
        add(q.from);
        for (const join of q.joins) { add(join.table); condition(join.condition, scope, false, null, 'ON'); }
        if (q.where) condition(q.where, scope, false, null, 'WHERE');
        const grouping = q.group === null ? [] : q.group.map(e => resolve(e, scope));
        const aggregate = q.group !== null || q.having !== null || q.items.some(i => hasAggregate(i.expr)) || q.order.some(i => hasAggregate(i.expr));
        const grouped = aggregate ? new Set(grouping) : null;
        if (q.star) for (const p of scope) for (const column of p.table.columns) {
            const expr = new Expr('reference'); expr.table = p.name; expr.column = column.name; expr.text = column.name;
            q.items.push({expr, alias: null, heading: column.name});
        }
        const types = q.items.map(i => check(i.expr, scope, true, grouped));
        if (q.having) condition(q.having, scope, true, grouped, 'HAVING');
        for (const item of q.order) {
            if (item.ordinal !== null) {
                if (item.ordinal < 1 || item.ordinal > q.items.length) fail('ORDER BY position ' + item.ordinal + ' is out of range');
                item.selected = item.ordinal - 1;
            } else {
                item.selected = item.alias === null ? -1 : q.items.findIndex(i => i.alias === item.alias);
                if (item.selected < 0) check(item.expr, scope, true, grouped);
            }
        }
        let rows = scope[0].table.rows.map(row => [...row]);
        q.joins.forEach((join, j) => {
            const right = scope[j + 1].table, next: Value[][] = [];
            for (const left of rows) {
                let found = false;
                for (const r of right.rows) { const row = left.concat(r); if (truth(evaluate(join.condition, row, null))) { next.push(row); found = true; } }
                if (join.left && !found) next.push(left.concat(Array(right.columns.length).fill(null)));
            }
            rows = next;
        });
        if (q.where) rows = rows.filter(row => truth(evaluate(q.where!, row, null)));
        let groups: Value[][][];
        if (!aggregate) groups = rows.map(row => [row]);
        else if (q.group === null) groups = [rows];
        else {
            const byKey = new Map<string, Value[][]>();
            for (const row of rows) { const id = rowKey(grouping.map(i => row[i])); if (!byKey.has(id)) byKey.set(id, []); byKey.get(id)!.push(row); }
            groups = [...byKey.values()];
        }
        if (q.having) groups = groups.filter(group => truth(evaluate(q.having!, group[0] ?? [], group)));
        let results: ResultRow[] = groups.map(group => {
            const row = group[0] ?? [], context = aggregate ? group : null, values = q.items.map(i => evaluate(i.expr, row, context));
            return {values, keys: q.order.map(i => i.selected >= 0 ? values[i.selected] : evaluate(i.expr, row, context))};
        });
        if (q.order.length) results.sort((a, b) => { for (let i = 0; i < q.order.length; i++) { const c = compare(a.keys[i], b.keys[i]); if (c !== 0) return q.order[i].descending ? -c : c; } return 0; });
        if (q.distinct) { const seen = new Set<string>(); results = results.filter(row => { const id = rowKey(row.values); if (seen.has(id)) return false; seen.add(id); return true; }); }
        results = results.slice(q.offset, q.limit === null ? undefined : q.offset + q.limit);
        const headings = q.items.map(i => i.heading), strings = results.map(row => row.values.map(written));
        const widths = headings.map((h, i) => Math.max(h.length, ...strings.map(row => row[i].length)));
        const separator = '+' + widths.map(w => '-'.repeat(w + 2) + '+').join('');
        const format = (row: string[], header: boolean): string => '|' + row.map((v, i) => ' ' + (!header && types[i] === 'INT' ? v.padStart(widths[i]) : v.padEnd(widths[i])) + ' |').join('');
        return [separator, format(headings, true), separator, ...strings.map(row => format(row, false)), separator, `(${results.length} ${results.length === 1 ? 'row' : 'rows'})`];
    }
    execute(c: Command): string[] {
        if (c.kind === 'empty' || c.kind === 'exit') return [];
        if (c.kind === 'select') return this.select(c.query!);
        if (c.kind === 'create') {
            if (this.tables.has(c.name)) fail('table ' + c.name + ' already exists');
            const seen = new Set<string>(); let primary = 0;
            for (const column of c.columns) { if (seen.has(column.name)) fail('duplicate column ' + column.name); seen.add(column.name); primary += column.primary; if (primary >= 2) fail('multiple primary keys'); }
            this.tables.set(c.name, {columns: c.columns, rows: []}); return ['Table ' + c.name + ' created.'];
        }
        const table = this.table(c.name);
        if (c.kind === 'drop') { this.tables.delete(c.name); return ['Table ' + c.name + ' dropped.']; }
        const scope: ScopePart[] = [{name: c.name, table, offset: 0}];
        let rows: Value[][], count: number;
        if (c.kind === 'insert') {
            const targets = c.names === null ? table.columns.map((_, i) => i) : this.targets(table, c.names);
            for (const tuple of c.tuples) {
                if (tuple.length !== targets.length) fail(`expected ${targets.length} values, got ${tuple.length}`);
                tuple.forEach((expr, i) => { if (!compatible(check(expr, [], false, null), table.columns[targets[i]].type)) fail('type mismatch for column ' + table.columns[targets[i]].name); });
            }
            const appended = c.tuples.map(tuple => { const row: Value[] = Array(table.columns.length).fill(null); tuple.forEach((e, i) => { row[targets[i]] = evaluate(e, [], null); }); return row; });
            rows = table.rows.concat(appended); this.constraints(table, rows, appended.map((_, i) => table.rows.length + i)); count = appended.length;
        } else if (c.kind === 'update') {
            const targets = this.targets(table, c.assignments.map(([name]) => name));
            c.assignments.forEach(([, e], i) => { if (!compatible(check(e, scope, false, null), table.columns[targets[i]].type)) fail('type mismatch for column ' + table.columns[targets[i]].name); });
            if (c.where) condition(c.where, scope, false, null, 'WHERE');
            const changed: number[] = [];
            rows = table.rows.map((row, i) => {
                if (c.where && !truth(evaluate(c.where, row, null))) return row;
                const result = [...row], values = c.assignments.map(([, e]) => evaluate(e, row, null)); targets.forEach((column, j) => { result[column] = values[j]; }); changed.push(i); return result;
            });
            this.constraints(table, rows, changed); count = changed.length;
        } else {
            if (c.where) condition(c.where, scope, false, null, 'WHERE');
            rows = table.rows.filter(row => c.where !== null && !truth(evaluate(c.where, row, null))); count = table.rows.length - rows.length;
        }
        table.rows = rows;
        return [`${count} ${count === 1 ? 'row' : 'rows'} ${c.kind === 'insert' ? 'inserted' : c.kind === 'update' ? 'updated' : 'deleted'}.`];
    }
}

const database = new Database(), output: string[] = [];
for (const text of statements(fs.readFileSync(0, 'utf8'))) {
    try { const command = new Parser(tokenize(text)).parse(); if (command.kind === 'exit') break; output.push(...database.execute(command)); }
    catch (e) { if (!(e instanceof SqlError)) throw e; output.push('ERROR: ' + e.message); }
}
if (output.length > 0) process.stdout.write(output.join('\n') + '\n');
