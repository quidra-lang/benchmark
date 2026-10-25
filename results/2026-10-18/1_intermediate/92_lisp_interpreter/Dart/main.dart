import 'dart:io';
import 'dart:math' as math;
final nil = Object(), voidValue = Object(), uninitialized = Object();
class SymbolValue {
    final String name;
    SymbolValue(this.name);
}
final symbols = <String, SymbolValue>{
};
SymbolValue sym(String s)=>symbols.putIfAbsent(s, ()=>SymbolValue(s));
class Pair {
    final Object car, cdr;
    Pair(this.car, this.cdr);
}
class Env {
    final Env? parent;
    final frame = <String, Object>{
    };
    Env([this.parent]);
    Env find(String n){
        for (Env? e = this; e != null; e = e.parent){
            if (e.frame.containsKey(n))return e;
        }
        throw LispError('unbound variable: $n');
    }
    Object get(String n){
        final v = find(n).frame[n]!;
        if (identical(v, uninitialized))throw LispError('uninitialized variable: $n');
        return v;
    }
}
class LispError implements Exception {
    final String message;
    LispError(this.message);
}
class Procedure {
    String? name;
    final int minimum;
    final bool variadic;
    final String? rest;
    final List<String> params;
    final List<Object> expressions;
    final Env? env;
    final Object Function(List<Object>)? builtin;
    Procedure(this.name, this.minimum, this.variadic, {
        this.rest, this.params = const[], this.expressions = const[], this.env, this.builtin
    });
    Object call(List<Object>a){
        if (a.length<minimum || (!variadic && a.length != minimum))throw LispError('${name??'lambda'}: wrong number of arguments (expected ${variadic?'at least ':''}$minimum, got ${a.length})');
        if (builtin != null)return builtin!(a);
        final e = Env(env);
        for (var i = 0; i<params.length; i++)e.frame[params[i]] = a[i];
        if (rest != null)e.frame[rest!] = makeList(a.sublist(minimum));
        return body(expressions, e);
    }
}
Object makeList(List<Object>a, [Object? tail]){
    Object v = tail??nil;
    for (final x in a.reversed)v = Pair(x, v);
    return v;
}
List<Object>? items(Object v){
    final a = <Object>[];
    while (v is Pair){
        a.add(v.car);
        v = v.cdr;
    }
    return identical(v, nil)?a: null;
}
bool truth(Object v)=>v != false;
String repr(Object v, [bool quoted = true]){
    if (identical(v, nil))return '()';
    if (identical(v, voidValue))return '#<void>';
    if (v is bool)return v?'#t': '#f';
    if (v is int)return '$v';
    if (v is String)return quoted?'"${v.replaceAll('\\','\\\\').replaceAll('"','\\"').replaceAll('\n','\\n')}"': v;
    if (v is SymbolValue)return v.name;
    if (v is Procedure)return v.name == null?'#<procedure>': '#<procedure ${v.name}>';
    final a = <String>[];
    while (v is Pair){
        a.add(repr(v.car, quoted));
        v = v.cdr;
    }
    if (!identical(v, nil))a.addAll(['.', repr(v, quoted)]);
    return '(${a.join(' ')})';
}
bool same(Object a, Object b, [bool deep = false]){
    if (a is Pair && b is Pair)return deep?same(a.car, b.car, true) && same(a.cdr, b.cdr, true): identical(a, b);
    return a == b;
}
class Parameters {
    final List<String> names;
    final String? rest;
    Parameters(this.names, this.rest);
}
Parameters? parameters(Object v){
    final names = <String>[];
    while (v is Pair){
        if (v.car is! SymbolValue)return null;
        names.add((v.car as SymbolValue).name);
        v = v.cdr;
    }
    final r = v is SymbolValue?v.name: null;
    if (!identical(v, nil) && r == null)return null;
    final all = [...names, if (r != null)r];
    return all.toSet().length == all.length?Parameters(names, r): null;
}
Procedure closure(Parameters p, List<Object>b, Env e, [String? name])=>Procedure(name, p.names.length, p.rest != null, rest: p.rest, params: p.names, expressions: b, env: e);
class Binding {
    final String name;
    final Object expr;
    Binding(this.name, this.expr);
}
List<Binding>? bindings(Object v, bool unique){
    final a = items(v);
    if (a == null)return null;
    final bs = <Binding>[], seen = <String>{
    };
    for (final x in a){
        final b = items(x);
        if (b == null || b.length != 2 || b[0] is! SymbolValue)return null;
        final n = (b[0] as SymbolValue).name;
        if (unique && !seen.add(n))return null;
        bs.add(Binding(n, b[1]));
    }
    return bs;
}
void shape(bool ok, Object x){
    if (!ok)throw LispError('bad syntax: ${repr(x)}');
}
Object body(List<Object>a, Env e){
    Object v = voidValue;
    for (final x in a)v = evaluate(x, e);
    return v;
}
Object evaluate(Object x, Env e){
    if (x is SymbolValue)return e.get(x.name);
    if (x is! Pair){
        shape(!identical(x, nil), x);
        return x;
    }
    final parsed = items(x);
    shape(parsed != null, x);
    final a = parsed!;
    final n = a.length, h = a[0] is SymbolValue?(a[0] as SymbolValue).name: '';
    switch (h){
        case 'quote':
            shape(n == 2, x);
            return a[1];
        case 'if':
            shape(n == 3 || n == 4, x);
            return truth(evaluate(a[1], e))?evaluate(a[2], e): n == 4?evaluate(a[3], e): voidValue;
        case 'begin':
            return body(a.sublist(1), e);
        case 'lambda':
            final p = n >= 3?parameters(a[1]): null;
            shape(p != null, x);
            return closure(p!, a.sublist(2), e);
        case 'define':
            if (n>1 && a[1] is SymbolValue){
                shape(n == 3, x);
                final name = (a[1] as SymbolValue).name;
                final v = evaluate(a[2], e);
                if (v is Procedure && v.builtin == null && v.name == null)v.name = name;
                e.frame[name] = v;
            }
            else{
                final t = n>1?a[1]: nil;
                final p = n >= 3 && t is Pair && t.car is SymbolValue?parameters(t.cdr): null;
                shape(p != null, x);
                final name = ((t as Pair).car as SymbolValue).name;
                e.frame[name] = closure(p!, a.sublist(2), e, name);
            }
            return voidValue;
        case 'set!':
            shape(n == 3 && a[1] is SymbolValue, x);
            final name = (a[1] as SymbolValue).name;
            final v = evaluate(a[2], e);
            e.find(name).frame[name] = v;
            return voidValue;
        case 'let':
        case 'let*':
        case 'letrec':
            final named = h == 'let' && n>1 && a[1] is SymbolValue, at = named?2: 1;
            final bs = n >= at+2?bindings(a[at], h != 'let*'): null;
            shape(bs != null, x);
            var scope = Env(e);
            if (h == 'let*'){
                if (bs!.isNotEmpty)scope = e;
                for (final b in bs){
                    final v = evaluate(b.expr, scope);
                    scope = Env(scope);
                    scope.frame[b.name] = v;
                }
            }
            else if (h == 'letrec'){
                for (final b in bs!)scope.frame[b.name] = uninitialized;
                for (final b in bs)scope.frame[b.name] = evaluate(b.expr, scope);
            }
            else{
                final vs = bs!.map((b)=>evaluate(b.expr, e)).toList();
                if (named){
                    final name = (a[1] as SymbolValue).name;
                    final f = closure(Parameters(bs.map((b)=>b.name).toList(), null), a.sublist(3), scope, name);
                    scope.frame[name] = f;
                    return f.call(vs);
                }
                for (var i = 0; i<bs.length; i++)scope.frame[bs[i].name] = vs[i];
            }
            return body(a.sublist(at+1), scope);
        case 'cond':
            final cs = a.sublist(1).map(items).toList();
            for (var i = 0; i<cs.length; i++){
                final c = cs[i];
                shape(c != null && c.isNotEmpty, x);
                if (identical(c![0], sym('else')))shape(c.length >= 2 && i == cs.length-1, x);
            }
            for (final c0 in cs){
                final c = c0!;
                if (identical(c[0], sym('else')))return body(c.sublist(1), e);
                final v = evaluate(c[0], e);
                if (truth(v))return c.length == 1?v: body(c.sublist(1), e);
            }
            return voidValue;
        case 'and':
            Object v = true;
            for (final z in a.sublist(1)){
                v = evaluate(z, e);
                if (!truth(v))break;
            }
            return v;
        case 'or':
            for (final z in a.sublist(1)){
                final v = evaluate(z, e);
                if (truth(v))return v;
            }
            return false;
        case 'when':
        case 'unless':
            shape(n >= 3, x);
            return truth(evaluate(a[1], e)) == (h == 'when')?body(a.sublist(2), e): voidValue;
    }
    final f = evaluate(a[0], e), args = a.sublist(1).map((z)=>evaluate(z, e)).toList();
    if (f is! Procedure)throw LispError('not a procedure: ${repr(f)}');
    return f.call(args);
}
bool mid = false;
void write(String s){
    stdout.write(s);
    if (s.isNotEmpty)mid = !s.endsWith('\n');
}
void line(String s){
    if (mid)write('\n');
    write('$s\n');
}
Object expect(String n, Object v, String k){
    final ok = switch (k){
        'integer'=>v is int, 'string'=>v is String, 'pair'=>v is Pair, 'procedure'=>v is Procedure, _=>items(v) != null
    };
    if (!ok)throw LispError('$n: expected $k, got ${repr(v)}');
    return v;
}
List<Object> asList(String n, Object v){
    expect(n, v, 'list');
    return items(v)!;
}
Env global(){
    final e = Env();
    void add(String n, int m, bool r, Object Function(List<Object>)fn){
        e.frame[n] = Procedure(n, m, r, builtin: fn);
    }
    for (final name in ['+', '*', '-', 'quotient', 'remainder', 'modulo', 'abs', 'min', 'max', 'gcd', '=', '<', '>', '<=', '>=']){
        final fixed = ['quotient', 'remainder', 'modulo'].contains(name)?2: name == 'abs'?1: -1;
        add(name, fixed >= 0?fixed: ['+', '*', 'gcd'].contains(name)?0: 1, fixed<0, (a){
            final z = a.map((v)=>expect(name, v, 'integer') as int).toList();
            var v = z.isEmpty?0: z[0];
            switch (name){
                case '+':
                    return z.fold(0, (s, x)=>s+x);
                case '*':
                    return z.fold(1, (s, x)=>s*x);
                case '-':
                    return z.length == 1?-v: v-z.sublist(1).fold(0, (s, x)=>s+x);
                case 'abs':
                    return v.abs();
                case 'min':
                    return z.reduce(math.min);
                case 'max':
                    return z.reduce(math.max);
                case 'gcd':
                    return z.fold(0, (g, x)=>g.gcd(x));
                case 'quotient':
                case 'remainder':
                case 'modulo':
                    final b = z[1];
                    if (b == 0)throw LispError('$name: division by zero');
                    final q = v~/b, r = v-b*q;
                    return name == 'quotient'?q: name == 'modulo' && r != 0 && ((r<0) != (b<0))?r+b: r;
            }
            for (var i = 1; i<z.length; i++){
                final l = z[i-1], r = z[i];
                final ok = switch (name){
                    '='=>l == r, '<'=>l<r, '>'=>l>r, '<='=>l <= r, _=>l >= r
                };
                if (!ok)return false;
            }
            return true;
        });
    }
    add('not', 1, false, (a)=>!truth(a[0]));
    add('eq?', 2, false, (a)=>same(a[0], a[1]));
    add('equal?', 2, false, (a)=>same(a[0], a[1], true));
    for (final n in ['null?', 'pair?', 'list?', 'number?', 'symbol?', 'procedure?'])add(n, 1, false, (a)=>switch (n){
        'null?'=>identical(a[0], nil), 'pair?'=>a[0] is Pair, 'list?'=>items(a[0]) != null, 'number?'=>a[0] is int, 'symbol?'=>a[0] is SymbolValue, _=>a[0] is Procedure
    });
    add('cons', 2, false, (a)=>Pair(a[0], a[1]));
    add('list', 0, true, makeList);
    for (final n in ['car', 'cdr', 'cadr'])add(n, 1, false, (a){
        final p = expect(n, a[0], 'pair') as Pair;
        return n == 'car'?p.car: n == 'cdr'?p.cdr: (expect(n, p.cdr, 'pair') as Pair).car;
    });
    for (final n in ['length', 'reverse', 'list-ref'])add(n, n == 'list-ref'?2: 1, false, (a){
        final z = asList(n, a[0]);
        if (n == 'length')return z.length;
        if (n == 'reverse')return makeList(z.reversed.toList());
        final k = expect(n, a[1], 'integer') as int;
        if (k<0 || k >= z.length)throw LispError('list-ref: index out of range: $k');
        return z[k];
    });
    add('append', 0, true, (a){
        if (a.isEmpty)return nil;
        final z = <Object>[];
        for (final v in a.take(a.length-1))z.addAll(asList('append', v));
        return makeList(z, a.last);
    });
    for (final n in ['map', 'filter', 'fold-left', 'apply'])add(n, n == 'fold-left'?3: 2, n != 'filter', (a){
        final f = expect(n, a[0], 'procedure') as Procedure;
        if (n == 'apply')return f.call([...a.sublist(1, a.length-1), ...asList(n, a.last)]);
        final ls = a.sublist(n == 'fold-left'?2: 1).map((v)=>asList(n, v)).toList();
        final count = ls.map((z)=>z.length).reduce(math.min), out = <Object>[];
        var acc = a[1];
        for (var i = 0; i<count; i++){
            if (n == 'filter'){
                if (truth(f.call([ls[0][i]])))out.add(ls[0][i]);
            }else{
                final args = [if (n == 'fold-left')acc, ...ls.map((z)=>z[i])], v = f.call(args);
                if (n == 'map')out.add(v);
                else acc = v;
            }
        }
        return n == 'fold-left'?acc: makeList(out);
    });
    add('string-append', 0, true, (a)=>a.map((v)=>expect('string-append', v, 'string') as String).join(''));
    add('number->string', 1, false, (a)=>expect('number->string', a[0], 'integer').toString());
    add('display', 1, false, (a){
        write(repr(a[0], false));
        return voidValue;
    });
    add('newline', 0, false, (a){
        write('\n');
        return voidValue;
    });
    add('error', 1, true, (a){
        throw LispError((expect('error', a[0], 'string') as String)+a.sublist(1).map((v)=>' ${repr(v)}').join(''));
    });
    return e;
}
class Token {
    final String kind;
    final Object? value;
    Token(this.kind, [this.value]);
}
class Reader {
    final List<String> lines;
    int row = 0, col = 0;
    Reader(this.lines);
    void skip(){
        row++;
        col = 0;
    }
    bool end(){
        while (row<lines.length){
            final s = lines[row];
            while (col<s.length && s[col] == ' ')col++;
            if (col<s.length && s[col] != ';')return false;
            skip();
        }
        return true;
    }
    Token token(){
        if (end())throw LispError('unexpected end of input');
        final s = lines[row];
        var c = s[col++];
        if ("()'".contains(c))return Token(c);
        if (c == '"'){
            var v = '';
            while (col<s.length){
                c = s[col++];
                if (c == '"')return Token('v', v);
                if (c == '\\'){
                    if (col == s.length)break;
                    c = s[col++];
                    if (!['"', '\\', 'n'].contains(c))throw LispError('bad escape');
                    if (c == 'n')c = '\n';
                }
                v += c;
            }
            throw LispError('unterminated string');
        }
        final start = col-1;
        while (col<s.length && !" ()'\";".contains(s[col]))col++;
        final a = s.substring(start, col);
        if (a == '.')return Token('.');
        if (RegExp(r'^[+-]?[0-9]+$').hasMatch(a))return Token('v', int.parse(a));
        if (a == '#t' || a == '#f')return Token('v', a == '#t');
        if (a.startsWith('#'))throw LispError('bad token: $a');
        return Token('v', sym(a));
    }
    Object datum([Token? first]){
        final t = first??token();
        if (t.kind == 'v')return t.value!;
        if (t.kind == "'")return makeList([sym('quote'), datum()]);
        if (t.kind != '(')throw LispError('unexpected ${t.kind}');
        final a = <Object>[];
        while (true){
            final t = token();
            if (t.kind == ')')return makeList(a);
            if (t.kind == '.' && a.isNotEmpty){
                final tail = datum();
                if (token().kind != ')')throw LispError('expected )');
                return makeList(a, tail);
            }
            a.add(datum(t));
        }
    }
}
void main(){
    final lines = <String>[];
    while (true){
        final s = stdin.readLineSync();
        if (s == null || s == '(exit)')break;
        lines.add(s);
    }
    final r = Reader(lines), e = global();
    while (!r.end()){
        late Object x;
        try{
            x = r.datum();
        }
        on LispError catch (err){
            line('Error: read: ${err.message}');
            if (err.message == 'unexpected end of input')break;
            r.skip();
            continue;
        }
        try{
            final v = evaluate(x, e);
            if (!identical(v, voidValue))line(repr(v));
        }
        on LispError catch (err){
            line('Error: ${err.message}');
        }
    }
    if (mid)write('\n');
}
