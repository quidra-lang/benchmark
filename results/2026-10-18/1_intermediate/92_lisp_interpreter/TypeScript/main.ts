declare function require(name: string): any;
declare const process: {
    stdout: {
        write(text: string): void;
    };
};
const fs = require("fs");
const NIL = Symbol("nil"),
    VOID = Symbol("void"),
    UNINIT = Symbol("uninitialized");
class Atom {
    name: string;
    constructor(name: string) {
        this.name = name;
    }
}
class Pair {
    car: Value;
    cdr: Value;
    constructor(car: Value, cdr: Value) {
        this.car = car;
        this.cdr = cdr;
    }
}
type Value = number | boolean | string | symbol | Atom | Pair | Proc;
const symbols = new Map<string, Atom>();
function sym(s: string): Atom {
    if (!symbols.has(s)) symbols.set(s, new Atom(s));
    return symbols.get(s)!;
}
function list(a: Value[], tail: Value = NIL): Value {
    for (let i = a.length - 1; i >= 0; i--) tail = new Pair(a[i], tail);
    return tail;
}
function items(v: Value): Value[] | null {
    const a: Value[] = [];
    while (v instanceof Pair) {
        a.push(v.car);
        v = v.cdr;
    }
    return v === NIL ? a : null;
}
function repr(v: Value, quoted = true): string {
    if (v === NIL) return "()";
    if (v === VOID) return "#<void>";
    if (typeof v === "boolean") return v ? "#t" : "#f";
    if (typeof v === "number") return String(v);
    if (typeof v === "string")
        return quoted
            ? '"' + v.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"'
            : v;
    if (v instanceof Atom) return v.name;
    if (v instanceof Proc) return v.name ? `#<procedure ${v.name}>` : "#<procedure>";
    const a = [];
    while (v instanceof Pair) {
        a.push(repr(v.car, quoted));
        v = v.cdr;
    }
    if (v !== NIL) a.push(".", repr(v, quoted));
    return "(" + a.join(" ") + ")";
}
function eq(a: Value, b: Value, deep = false): boolean {
    if (deep && a instanceof Pair && b instanceof Pair)
        return eq(a.car, b.car, true) && eq(a.cdr, b.cdr, true);
    return a === b;
}
class Env {
    parent: Env | null;
    frame: Map<string, Value>;
    constructor(parent: Env | null = null) {
        this.parent = parent;
        this.frame = new Map();
    }
    find(n: string): Env {
        for (let e: Env | null = this; e; e = e.parent) if (e.frame.has(n)) return e;
        throw Error("unbound variable: " + n);
    }
    get(n: string): Value {
        const v = this.find(n).frame.get(n)!;
        if (v === UNINIT) throw Error("uninitialized variable: " + n);
        return v;
    }
}
class Proc {
    name: string;
    min: number;
    rest: boolean | string;
    fn: ((a: Value[]) => Value) | null;
    params: string[];
    body: Value[];
    env: Env | null;
    constructor(
        name: string,
        min: number,
        rest: boolean | string,
        fn: ((a: Value[]) => Value) | null = null,
        params: string[] = [],
        body: Value[] = [],
        env: Env | null = null,
    ) {
        this.name = name;
        this.min = min;
        this.rest = rest;
        this.fn = fn;
        this.params = params;
        this.body = body;
        this.env = env;
    }
    call(a: Value[]): Value {
        if (a.length < this.min || (!this.rest && a.length !== this.min))
            throw Error(
                `${this.name || "lambda"}: wrong number of arguments (expected ${this.rest ? "at least " : ""}${this.min}, got ${a.length})`,
            );
        if (this.fn) return this.fn(a);
        const e = new Env(this.env);
        this.params.forEach((n, i) => e.frame.set(n, a[i]));
        if (typeof this.rest === "string") e.frame.set(this.rest, list(a.slice(this.min)));
        return body(this.body, e);
    }
}
type Parameters = {
    names: string[];
    rest: string | null;
};
function parameters(v: Value): Parameters | null {
    const names: string[] = [];
    while (v instanceof Pair) {
        if (!(v.car instanceof Atom)) return null;
        names.push(v.car.name);
        v = v.cdr;
    }
    const rest = v instanceof Atom ? v.name : null;
    if (v !== NIL && rest === null) return null;
    const all = rest === null ? names : [...names, rest];
    return new Set(all).size === all.length
        ? {
              names,
              rest,
          }
        : null;
}
function closure(p: Parameters, b: Value[], e: Env, name = ""): Proc {
    return new Proc(name, p.names.length, p.rest === null ? false : p.rest, null, p.names, b, e);
}
function shape(ok: unknown, x: Value): asserts ok {
    if (!ok) throw Error("bad syntax: " + repr(x));
}
function bindings(v: Value, unique: boolean): [string, Value][] | null {
    const a = items(v);
    if (!a) return null;
    const result: [string, Value][] = [];
    for (const x of a) {
        const z = items(x);
        if (!z || z.length !== 2 || !(z[0] instanceof Atom)) return null;
        result.push([z[0].name, z[1]]);
    }
    return !unique || new Set(result.map((x) => x[0])).size === result.length ? result : null;
}
function body(a: Value[], e: Env): Value {
    let v: Value = VOID;
    for (const x of a) v = evaluate(x, e);
    return v;
}
function evaluate(x: Value, e: Env): Value {
    if (x instanceof Atom) return e.get(x.name);
    if (!(x instanceof Pair)) {
        shape(x !== NIL, x);
        return x;
    }
    const a = items(x);
    shape(a !== null, x);
    const n = a.length,
        h = a[0] instanceof Atom ? a[0].name : "";
    switch (h) {
        case "quote":
            shape(n === 2, x);
            return a[1];
        case "if":
            shape(n === 3 || n === 4, x);
            return evaluate(a[1], e) !== false
                ? evaluate(a[2], e)
                : n === 4
                  ? evaluate(a[3], e)
                  : VOID;
        case "begin":
            return body(a.slice(1), e);
        case "lambda": {
            const p = n >= 3 ? parameters(a[1]) : null;
            shape(p !== null, x);
            return closure(p, a.slice(2), e);
        }
        case "define": {
            if (n >= 2 && a[1] instanceof Atom) {
                shape(n === 3, x);
                const v = evaluate(a[2], e);
                if (v instanceof Proc && !v.fn && !v.name) v.name = a[1].name;
                e.frame.set(a[1].name, v);
            } else {
                const target = a[1],
                    p =
                        n >= 3 && target instanceof Pair && target.car instanceof Atom
                            ? parameters(target.cdr)
                            : null;
                shape(p !== null, x);
                const pair = target as Pair;
                const name = (pair.car as Atom).name;
                e.frame.set(name, closure(p, a.slice(2), e, name));
            }
            return VOID;
        }
        case "set!":
            shape(n === 3 && a[1] instanceof Atom, x);
            {
                const name = (a[1] as Atom).name;
                const v = evaluate(a[2], e);
                e.find(name).frame.set(name, v);
            }
            return VOID;
        case "let":
        case "let*":
        case "letrec": {
            const named = h === "let" && n > 1 && a[1] instanceof Atom,
                at = named ? 2 : 1;
            const bs = n >= at + 2 ? bindings(a[at], h !== "let*") : null;
            shape(bs !== null, x);
            let scope = new Env(e);
            if (h === "let*") {
                scope = bs.length ? e : scope;
                for (const [name, expr] of bs) {
                    const v = evaluate(expr, scope);
                    scope = new Env(scope);
                    scope.frame.set(name, v);
                }
            } else if (h === "letrec") {
                for (const [name] of bs) scope.frame.set(name, UNINIT);
                for (const [name, expr] of bs) scope.frame.set(name, evaluate(expr, scope));
            } else {
                const vs = bs.map((b) => evaluate(b[1], e));
                if (named) {
                    const p = closure(
                        {
                            names: bs.map((b) => b[0]),
                            rest: null,
                        },
                        a.slice(3),
                        scope,
                        (a[1] as Atom).name,
                    );
                    scope.frame.set((a[1] as Atom).name, p);
                    return p.call(vs);
                }
                bs.forEach((b, i) => scope.frame.set(b[0], vs[i]));
            }
            return body(a.slice(at + 1), scope);
        }
        case "cond": {
            const cs = a.slice(1).map((z) => {
                const c = items(z);
                shape(c && c.length, x);
                return c;
            });
            cs.forEach((c, i) =>
                shape(
                    !(c[0] instanceof Atom) ||
                        c[0].name !== "else" ||
                        (c.length >= 2 && i === cs.length - 1),
                    x,
                ),
            );
            for (const c of cs) {
                if (c[0] instanceof Atom && c[0].name === "else") return body(c.slice(1), e);
                const v = evaluate(c[0], e);
                if (v !== false) return c.length === 1 ? v : body(c.slice(1), e);
            }
            return VOID;
        }
        case "and": {
            let v: Value = true;
            for (const z of a.slice(1)) {
                v = evaluate(z, e);
                if (v === false) break;
            }
            return v;
        }
        case "or":
            for (const z of a.slice(1)) {
                const v = evaluate(z, e);
                if (v !== false) return v;
            }
            return false;
        case "when":
        case "unless":
            shape(n >= 3, x);
            return (evaluate(a[1], e) !== false) === (h === "when") ? body(a.slice(2), e) : VOID;
    }
    const p = evaluate(a[0], e),
        args = a.slice(1).map((z) => evaluate(z, e));
    if (!(p instanceof Proc)) throw Error("not a procedure: " + repr(p));
    return p.call(args);
}
let output = "",
    mid = false;
function write(s: string): void {
    output += s;
    if (s.length) mid = !s.endsWith("\n");
}
function line(s: string): void {
    if (mid) write("\n");
    write(s + "\n");
}
function globalEnv() {
    const e = new Env();
    function add(name: string, min: number, rest: boolean, fn: (a: Value[]) => Value) {
        e.frame.set(name, new Proc(name, min, rest, fn));
    }
    type KindMap = {
        integer: number;
        string: string;
        pair: Pair;
        procedure: Proc;
        list: Value;
    };
    function checked<K extends keyof KindMap>(name: string, v: Value, kind: K): KindMap[K] {
        const ok =
            kind === "integer"
                ? typeof v === "number"
                : kind === "string"
                  ? typeof v === "string"
                  : kind === "pair"
                    ? v instanceof Pair
                    : kind === "procedure"
                      ? v instanceof Proc
                      : items(v) !== null;
        if (!ok) throw Error(`${name}: expected ${kind}, got ${repr(v)}`);
        return v as KindMap[K];
    }
    function checkedItems(name: string, v: Value): Value[] {
        checked(name, v, "list");
        return items(v)!;
    }
    const ints = [
        "+",
        "*",
        "-",
        "quotient",
        "remainder",
        "modulo",
        "abs",
        "min",
        "max",
        "gcd",
        "=",
        "<",
        ">",
        "<=",
        ">=",
    ];
    for (const name of ints) {
        const fixed = ["quotient", "remainder", "modulo"].includes(name)
            ? 2
            : name === "abs"
              ? 1
              : null;
        add(name, fixed ?? (["+", "*", "gcd"].includes(name) ? 0 : 1), fixed === null, (a) => {
            const numbers = a.map((v) => checked(name, v, "integer"));
            let v = numbers[0];
            switch (name) {
                case "+":
                    return numbers.reduce((s, x) => s + x, 0);
                case "*":
                    return numbers.reduce((s, x) => s * x, 1);
                case "-":
                    return numbers.length === 1 ? -v : numbers.slice(1).reduce((s, x) => s - x, v);
                case "abs":
                    return Math.abs(v);
                case "min":
                    return Math.min(...numbers);
                case "max":
                    return Math.max(...numbers);
                case "gcd":
                    return numbers.reduce((g, x) => {
                        x = Math.abs(x);
                        while (x) {
                            const t = g % x;
                            g = x;
                            x = t;
                        }
                        return g;
                    }, 0);
                case "quotient":
                case "remainder":
                case "modulo":
                    if (numbers[1] === 0) throw Error(name + ": division by zero");
                    return name === "quotient"
                        ? Math.trunc(v / numbers[1])
                        : v -
                              numbers[1] *
                                  (name === "modulo"
                                      ? Math.floor(v / numbers[1])
                                      : Math.trunc(v / numbers[1]));
            }
            return numbers
                .slice(1)
                .every((b, i) =>
                    name === "="
                        ? numbers[i] === b
                        : name === "<"
                          ? numbers[i] < b
                          : name === ">"
                            ? numbers[i] > b
                            : name === "<="
                              ? numbers[i] <= b
                              : numbers[i] >= b,
                );
        });
    }
    add("not", 1, false, (a) => a[0] === false);
    add("eq?", 2, false, (a) => eq(a[0], a[1]));
    add("equal?", 2, false, (a) => eq(a[0], a[1], true));
    for (const name of ["null?", "pair?", "list?", "number?", "symbol?", "procedure?"])
        add(name, 1, false, (a) =>
            name === "null?"
                ? a[0] === NIL
                : name === "pair?"
                  ? a[0] instanceof Pair
                  : name === "list?"
                    ? items(a[0]) !== null
                    : name === "number?"
                      ? typeof a[0] === "number"
                      : name === "symbol?"
                        ? a[0] instanceof Atom
                        : a[0] instanceof Proc,
        );
    add("cons", 2, false, (a) => new Pair(a[0], a[1]));
    add("list", 0, true, (a) => list(a));
    for (const name of ["car", "cdr", "cadr"])
        add(name, 1, false, (a) => {
            const p = checked(name, a[0], "pair");
            return name === "car"
                ? p.car
                : name === "cdr"
                  ? p.cdr
                  : checked(name, p.cdr, "pair").car;
        });
    for (const name of ["length", "reverse", "list-ref"])
        add(name, name === "list-ref" ? 2 : 1, false, (a) => {
            const z = checkedItems(name, a[0]);
            if (name === "length") return z.length;
            if (name === "reverse") return list(z.reverse());
            const k = checked(name, a[1], "integer");
            if (k < 0 || k >= z.length) throw Error("list-ref: index out of range: " + k);
            return z[k];
        });
    add("append", 0, true, (a) => {
        if (!a.length) return NIL;
        const z = [];
        for (const x of a.slice(0, -1)) z.push(...checkedItems("append", x));
        return list(z, a[a.length - 1]);
    });
    for (const name of ["map", "filter", "fold-left", "apply"])
        add(name, name === "fold-left" ? 3 : 2, name !== "filter", (a) => {
            const f = checked(name, a[0], "procedure");
            if (name === "apply")
                return f.call([...a.slice(1, -1), ...checkedItems(name, a[a.length - 1])]);
            const ls = a.slice(name === "fold-left" ? 2 : 1).map((v) => checkedItems(name, v));
            if (name === "filter") return list(ls[0].filter((v) => f.call([v]) !== false));
            const count = Math.min(...ls.map((z) => z.length)),
                z = [];
            let acc = a[1];
            for (let i = 0; i < count; i++) {
                const args = ls.map((z) => z[i]);
                if (name === "map") z.push(f.call(args));
                else acc = f.call([acc, ...args]);
            }
            return name === "map" ? list(z) : acc;
        });
    add("string-append", 0, true, (a) =>
        a.map((v) => checked("string-append", v, "string")).join(""),
    );
    add("number->string", 1, false, (a) => String(checked("number->string", a[0], "integer")));
    add("display", 1, false, (a) => {
        write(repr(a[0], false));
        return VOID;
    });
    add("newline", 0, false, () => {
        write("\n");
        return VOID;
    });
    add("error", 1, true, (a) => {
        throw Error(
            checked("error", a[0], "string") +
                a
                    .slice(1)
                    .map((v) => " " + repr(v))
                    .join(""),
        );
    });
    return e;
}
class Reader {
    lines: string[];
    row: number;
    col: number;
    constructor(lines: string[]) {
        this.lines = lines;
        this.row = 0;
        this.col = 0;
    }
    skip() {
        this.row++;
        this.col = 0;
    }
    end() {
        while (this.row < this.lines.length) {
            const s = this.lines[this.row];
            while (s[this.col] === " ") this.col++;
            if (this.col < s.length && s[this.col] !== ";") return false;
            this.skip();
        }
        return true;
    }
    token(): [string, Value | null] {
        if (this.end()) throw Error("unexpected end of input");
        const s = this.lines[this.row],
            c = s[this.col++];
        if ("()'".includes(c)) return [c, null];
        if (c === '"') {
            let v = "";
            while (this.col < s.length) {
                let c = s[this.col++];
                if (c === '"') return ["v", v];
                if (c === "\\") {
                    if (this.col === s.length) break;
                    c = s[this.col++];
                    if (!'"\\n'.includes(c)) throw Error("bad escape");
                    v += c === "n" ? "\n" : c;
                } else v += c;
            }
            throw Error("unterminated string");
        }
        const start = this.col - 1;
        while (this.col < s.length && !" ()'\";".includes(s[this.col])) this.col++;
        const a = s.slice(start, this.col);
        if (a === ".") return [".", null];
        if (/^[+-]?\d+$/.test(a)) return ["v", Number(a)];
        if (a === "#t" || a === "#f") return ["v", a === "#t"];
        if (a[0] === "#") throw Error("bad token: " + a);
        return ["v", sym(a)];
    }
    datum(t = this.token()): Value {
        if (t[0] === "v") return t[1]!;
        if (t[0] === "'") return list([sym("quote"), this.datum()]);
        if (t[0] !== "(") throw Error("unexpected " + t[0]);
        const a: Value[] = [];
        while (true) {
            const t = this.token();
            if (t[0] === ")") return list(a);
            if (t[0] === "." && a.length) {
                const tail = this.datum();
                if (this.token()[0] !== ")") throw Error("expected )");
                return list(a, tail);
            }
            a.push(this.datum(t));
        }
    }
}
const lines: string[] = fs.readFileSync(0, "utf8").split("\n");
const end = lines.indexOf("(exit)");
const reader = new Reader(end < 0 ? lines : lines.slice(0, end)),
    env = globalEnv();
while (!reader.end()) {
    let x;
    try {
        x = reader.datum();
    } catch (failure) {
        const err = failure as Error;
        line("Error: read: " + err.message);
        if (err.message === "unexpected end of input") break;
        reader.skip();
        continue;
    }
    try {
        const v = evaluate(x, env);
        if (v !== VOID) line(repr(v));
    } catch (failure) {
        const err = failure as Error;
        line("Error: " + err.message);
    }
}
if (mid) write("\n");
process.stdout.write(output);
