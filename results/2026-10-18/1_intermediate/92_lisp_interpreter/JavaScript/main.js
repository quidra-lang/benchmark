const fs = require('fs');
const NIL = Symbol('nil'), VOID = Symbol('void'), UNINIT = Symbol('uninitialized');
class Atom {
    constructor(name) {
        this.name = name;
    }
}
class Pair {
    constructor(car, cdr) {
        this.car = car;
        this.cdr = cdr;
    }
}
const symbols = new Map();
function sym(s) {
    if (!symbols.has(s)) symbols.set(s, new Atom(s));
    return symbols.get(s);
}
function list(a, tail = NIL) {
    for (let i = a.length-1; i >= 0; i--) tail = new Pair(a[i], tail);
    return tail;
}
function items(v) {
    const a = [];
    while (v instanceof Pair){
        a.push(v.car);
        v = v.cdr;
    }
    return v === NIL?a: null;
}
function repr(v, quoted = true) {
    if (v === NIL)return '()';
    if (v === VOID)return '#<void>';
    if (typeof v === 'boolean')return v?'#t': '#f';
    if (typeof v === 'number')return String(v);
    if (typeof v === 'string')return quoted?'"'+v.replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n')+'"': v;
    if (v instanceof Atom)return v.name;
    if (v instanceof Proc)return v.name?`#<procedure ${v.name}>`: '#<procedure>';
    const a = [];
    while (v instanceof Pair){
        a.push(repr(v.car, quoted));
        v = v.cdr;
    }
    if (v !== NIL)a.push('.', repr(v, quoted));
    return '('+a.join(' ')+')';
}
function eq(a, b, deep = false){
    if (deep && a instanceof Pair && b instanceof Pair)return eq(a.car, b.car, true) && eq(a.cdr, b.cdr, true);
    return a === b;
}
class Env {
    constructor(parent = null){
        this.parent = parent;
        this.frame = new Map();
    }
    find(n){
        for (let e = this; e; e = e.parent)if (e.frame.has(n))return e;
        throw Error('unbound variable: '+n);
    }
    get(n){
        const v = this.find(n).frame.get(n);
        if (v === UNINIT)throw Error('uninitialized variable: '+n);
        return v;
    }
}
class Proc {
    constructor(name, min, rest, fn = null, params = [], body = [], env = null){
        Object.assign(this, {
            name, min, rest, fn, params, body, env
        });
    }
    call(a){
        if (a.length<this.min || (!this.rest && a.length !== this.min))throw Error(`${this.name||'lambda'}: wrong number of arguments (expected ${this.rest?'at least ':''}${this.min}, got ${a.length})`);
        if (this.fn)return this.fn(a);
        const e = new Env(this.env);
        this.params.forEach((n, i)=>e.frame.set(n, a[i]));
        if (typeof this.rest === 'string')e.frame.set(this.rest, list(a.slice(this.min)));
        return body(this.body, e);
    }
}
function parameters(v){
    const names = [];
    while (v instanceof Pair){
        if (!(v.car instanceof Atom))return null;
        names.push(v.car.name);
        v = v.cdr;
    }
    const rest = v instanceof Atom?v.name: null;
    if (v !== NIL && rest === null)return null;
    const all = rest === null?names: [...names, rest];
    return new Set(all).size === all.length?{
        names, rest
    }: null;
}
function closure(p, b, e, name = ''){
    return new Proc(name, p.names.length, p.rest === null?false: p.rest, null, p.names, b, e);
}
function shape(ok, x){
    if (!ok)throw Error('bad syntax: '+repr(x));
}
function bindings(v, unique){
    const a = items(v);
    if (!a)return null;
    const result = [];
    for (const x of a){
        const z = items(x);
        if (!z || z.length !== 2 || !(z[0] instanceof Atom))return null;
        result.push([z[0].name, z[1]]);
    }
    return !unique || new Set(result.map(x=>x[0])).size === result.length?result: null;
}
function body(a, e){
    let v = VOID;
    for (const x of a)v = evaluate(x, e);
    return v;
}
function evaluate(x, e){
    if (x instanceof Atom)return e.get(x.name);
    if (!(x instanceof Pair)){
        shape(x !== NIL, x);
        return x;
    }
    const a = items(x);
    shape(a !== null, x);
    const n = a.length, h = a[0] instanceof Atom?a[0].name: '';
    switch (h){
        case 'quote':
            shape(n === 2, x);
            return a[1];
        case 'if':
            shape(n === 3 || n === 4, x);
            return evaluate(a[1], e) !== false?evaluate(a[2], e): n === 4?evaluate(a[3], e): VOID;
        case 'begin':
            return body(a.slice(1), e);
        case 'lambda':
            {
                const p = n >= 3?parameters(a[1]): null;
                shape(p !== null, x);
                return closure(p, a.slice(2), e);
            }
        case 'define':
            {
                if (n >= 2 && a[1] instanceof Atom){
                    shape(n === 3, x);
                    const v = evaluate(a[2], e);
                    if (v instanceof Proc && !v.fn && !v.name)v.name = a[1].name;
                    e.frame.set(a[1].name, v);
                }
                else {
                    const target = a[1], p = n >= 3 && target instanceof Pair && target.car instanceof Atom?parameters(target.cdr): null;
                    shape(p !== null, x);
                    e.frame.set(target.car.name, closure(p, a.slice(2), e, target.car.name));
                }
                return VOID;
            }
        case 'set!':
            shape(n === 3 && a[1] instanceof Atom, x);
            {
                const v = evaluate(a[2], e);
                e.find(a[1].name).frame.set(a[1].name, v);
            }
            return VOID;
        case 'let':
        case 'let*':
        case 'letrec':
            {
                const named = h === 'let' && n>1 && a[1] instanceof Atom, at = named?2: 1;
                const bs = n >= at+2?bindings(a[at], h !== 'let*'): null;
                shape(bs !== null, x);
                let scope = new Env(e);
                if (h === 'let*'){
                    scope = bs.length?e: scope;
                    for (const [name, expr] of bs){
                        const v = evaluate(expr, scope);
                        scope = new Env(scope);
                        scope.frame.set(name, v);
                    }
                }
                else if (h === 'letrec'){
                    for (const [name] of bs)scope.frame.set(name, UNINIT);
                    for (const [name, expr] of bs)scope.frame.set(name, evaluate(expr, scope));
                }
                else {
                    const vs = bs.map(b=>evaluate(b[1], e));
                    if (named){
                        const p = closure({
                            names: bs.map(b=>b[0]), rest: null
                        }, a.slice(3), scope, a[1].name);
                        scope.frame.set(a[1].name, p);
                        return p.call(vs);
                    }
                    bs.forEach((b, i)=>scope.frame.set(b[0], vs[i]));
                }
                return body(a.slice(at+1), scope);
            }
        case 'cond':
            {
                const cs = a.slice(1).map(items);
                cs.forEach((c, i)=>shape(c && c.length && (!(c[0] instanceof Atom) || c[0].name !== 'else' || (c.length >= 2 && i === cs.length-1)), x));
                for (const c of cs){
                    if (c[0] instanceof Atom && c[0].name === 'else')return body(c.slice(1), e);
                    const v = evaluate(c[0], e);
                    if (v !== false)return c.length === 1?v: body(c.slice(1), e);
                }
                return VOID;
            }
        case 'and':
            {
                let v = true;
                for (const z of a.slice(1)){
                    v = evaluate(z, e);
                    if (v === false)break;
                }
                return v;
            }
        case 'or':
            for (const z of a.slice(1)){
                const v = evaluate(z, e);
                if (v !== false)return v;
            }
            return false;
        case 'when':
        case 'unless':
            shape(n >= 3, x);
            return (evaluate(a[1], e) !== false) === (h === 'when')?body(a.slice(2), e): VOID;
    }
    const p = evaluate(a[0], e), args = a.slice(1).map(z=>evaluate(z, e));
    if (!(p instanceof Proc))throw Error('not a procedure: '+repr(p));
    return p.call(args);
}
let output = '', mid = false;
function write(s){
    output += s;
    if (s.length)mid = !s.endsWith('\n');
}
function line(s){
    if (mid)write('\n');
    write(s+'\n');
}
function globalEnv(){
    const e = new Env();
    function add(name, min, rest, fn){
        e.frame.set(name, new Proc(name, min, rest, fn));
    }
    function checked(name, v, kind){
        const ok = kind === 'integer'?typeof v === 'number': kind === 'string'?typeof v === 'string': kind === 'pair'?v instanceof Pair: kind === 'procedure'?v instanceof Proc: items(v) !== null;
        if (!ok)throw Error(`${name}: expected ${kind}, got ${repr(v)}`);
        return v;
    }
    const ints = ['+', '*', '-', 'quotient', 'remainder', 'modulo', 'abs', 'min', 'max', 'gcd', '=', '<', '>', '<=', '>='];
    for (const name of ints){
        const fixed = ['quotient', 'remainder', 'modulo'].includes(name)?2: name === 'abs'?1: null;
        add(name, fixed??(['+', '*', 'gcd'].includes(name)?0: 1), fixed === null, a=>{
            a.forEach(v=>checked(name, v, 'integer'));
            let v = a[0];
            switch (name){
                case '+':
                    return a.reduce((s, x)=>s+x, 0);
                case '*':
                    return a.reduce((s, x)=>s*x, 1);
                case '-':
                    return a.length === 1?-v: a.slice(1).reduce((s, x)=>s-x, v);
                case 'abs':
                    return Math.abs(v);
                case 'min':
                    return Math.min(...a);
                case 'max':
                    return Math.max(...a);
                case 'gcd':
                    return a.reduce((g, x)=>{
                        x = Math.abs(x);
                        while (x){
                            const t = g%x;
                            g = x;
                            x = t;
                        }
                        return g;
                    }, 0);
                case 'quotient':
                case 'remainder':
                case 'modulo':
                    if (a[1] === 0)throw Error(name+': division by zero');
                    return name === 'quotient'?Math.trunc(v/a[1]): v-a[1]*(name === 'modulo'?Math.floor(v/a[1]): Math.trunc(v/a[1]));
            }
            return a.slice(1).every((b, i)=>name === '='?a[i] === b: name === '<'?a[i]<b: name === '>'?a[i]>b: name === '<='?a[i] <= b: a[i] >= b);
        });
    }
    add('not', 1, false, a=>a[0] === false);
    add('eq?', 2, false, a=>eq(a[0], a[1]));
    add('equal?', 2, false, a=>eq(a[0], a[1], true));
    for (const name of ['null?', 'pair?', 'list?', 'number?', 'symbol?', 'procedure?'])
        add(name, 1, false, a=>
            name === 'null?'?a[0] === NIL:
            name === 'pair?'?a[0] instanceof Pair:
            name === 'list?'?items(a[0]) !== null:
            name === 'number?'?typeof a[0] === 'number':
            name === 'symbol?'?a[0] instanceof Atom: a[0] instanceof Proc);
    add('cons', 2, false, a=>new Pair(a[0], a[1]));
    add('list', 0, true, a=>list(a));
    for (const name of ['car', 'cdr', 'cadr'])add(name, 1, false, a=>{
        const p = checked(name, a[0], 'pair');
        return name === 'car'?p.car: name === 'cdr'?p.cdr: checked(name, p.cdr, 'pair').car;
    });
    for (const name of ['length', 'reverse', 'list-ref'])add(name, name === 'list-ref'?2: 1, false, a=>{
        const z = items(checked(name, a[0], 'list'));
        if (name === 'length')return z.length;
        if (name === 'reverse')return list(z.reverse());
        const k = checked(name, a[1], 'integer');
        if (k<0 || k >= z.length)throw Error('list-ref: index out of range: '+k);
        return z[k];
    });
    add('append', 0, true, a=>{
        if (!a.length)return NIL;
        const z = [];
        for (const x of a.slice(0, -1))z.push(...items(checked('append', x, 'list')));
        return list(z, a[a.length-1]);
    });
    for (const name of ['map', 'filter', 'fold-left', 'apply'])add(name, name === 'fold-left'?3: 2, name !== 'filter', a=>{
        const f = checked(name, a[0], 'procedure');
        if (name === 'apply')return f.call([...a.slice(1, -1), ...items(checked(name, a[a.length-1], 'list'))]);
        const ls = a.slice(name === 'fold-left'?2: 1).map(v=>items(checked(name, v, 'list')));
        if (name === 'filter')return list(ls[0].filter(v=>f.call([v]) !== false));
        const count = Math.min(...ls.map(z=>z.length)), z = [];
        let acc = a[1];
        for (let i = 0; i<count; i++){
            const args = ls.map(z=>z[i]);
            if (name === 'map')z.push(f.call(args));
            else acc = f.call([acc, ...args]);
        }
        return name === 'map'?list(z): acc;
    });
    add('string-append', 0, true, a=>a.map(v=>checked('string-append', v, 'string')).join(''));
    add('number->string', 1, false, a=>String(checked('number->string', a[0], 'integer')));
    add('display', 1, false, a=>{
        write(repr(a[0], false));
        return VOID;
    });
    add('newline', 0, false, ()=>{
        write('\n');
        return VOID;
    });
    add('error', 1, true, a=>{
        throw Error(checked('error', a[0], 'string')+a.slice(1).map(v=>' '+repr(v)).join(''));
    });
    return e;
}
class Reader {
    constructor(lines){
        this.lines = lines;
        this.row = 0;
        this.col = 0;
    }
    skip(){
        this.row++;
        this.col = 0;
    }
    end(){
        while (this.row<this.lines.length){
            const s = this.lines[this.row];
            while (s[this.col] === ' ')this.col++;
            if (this.col<s.length && s[this.col] !== ';')return false;
            this.skip();
        }
        return true;
    }
    token(){
        if (this.end())throw Error('unexpected end of input');
        const s = this.lines[this.row], c = s[this.col++];
        if ("()'".includes(c))return [c, null];
        if (c === '"'){
            let v = '';
            while (this.col<s.length){
                let c = s[this.col++];
                if (c === '"')return ['v', v];
                if (c === '\\'){
                    if (this.col === s.length)break;
                    c = s[this.col++];
                    if (!'"\\n'.includes(c))throw Error('bad escape');
                    v += c === 'n'?'\n': c;
                }else v += c;
            }
            throw Error('unterminated string');
        }
        const start = this.col-1;
        while (this.col<s.length && !" ()'\";".includes(s[this.col]))this.col++;
        const a = s.slice(start, this.col);
        if (a === '.')return ['.', null];
        if (/^[+-]?\d+$/.test(a))return ['v', Number(a)];
        if (a === '#t' || a === '#f')return ['v', a === '#t'];
        if (a[0] === '#')throw Error('bad token: '+a);
        return ['v', sym(a)];
    }
    datum(t = this.token()){
        if (t[0] === 'v')return t[1];
        if (t[0] === "'")return list([sym('quote'), this.datum()]);
        if (t[0] !== '(')throw Error('unexpected '+t[0]);
        const a = [];
        while (true){
            const t = this.token();
            if (t[0] === ')')return list(a);
            if (t[0] === '.' && a.length){
                const tail = this.datum();
                if (this.token()[0] !== ')')throw Error('expected )');
                return list(a, tail);
            }
            a.push(this.datum(t));
        }
    }
}
const lines = fs.readFileSync(0, 'utf8').split('\n');
const end = lines.indexOf('(exit)');
const reader = new Reader(end<0?lines: lines.slice(0, end)), env = globalEnv();
while (!reader.end()){
    let x;
    try{
        x = reader.datum();
    }catch (err){
        line('Error: read: '+err.message);
        if (err.message === 'unexpected end of input')break;
        reader.skip();
        continue;
    }
    try{
        const v = evaluate(x, env);
        if (v !== VOID)line(repr(v));
    }catch (err){
        line('Error: '+err.message);
    }
}
if (mid)write('\n');
process.stdout.write(output);
