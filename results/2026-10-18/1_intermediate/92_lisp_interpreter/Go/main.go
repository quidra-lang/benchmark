package main
import (
    "bufio"
    "fmt"
    "os"
    "regexp"
    "strconv"
    "strings"
)
type marker int
const (
    nilValue marker = iota;
    voidValue;
    uninitialized
)
type symbol string
type pair struct{
    car, cdr any
}
type environment struct{
    frame map[string]any;
    parent *environment
}
func scope(p *environment)*environment{
    return &environment{make(map[string]any), p}
}
func fail(s string){
    panic(s)
}
func(e *environment)find(n string)*environment{
    for e != nil{
        if _, ok:=e.frame[n]; ok{
            return e
        };
        e = e.parent
    };
    fail("unbound variable: "+n);
    return nil
}
func(e *environment)get(n string)any{
    v:=e.find(n).frame[n];
    if v == uninitialized{
        fail("uninitialized variable: "+n)
    };
    return v
}
type procedure struct{
    name string;
    minimum int;
    variadic bool;
    rest string;
    params []string;
    body []any;
    env *environment;
    builtin func([]any)any
}
func list(a []any, tail any)any{
    for i:=len(a)-1; i >= 0; i--{
        tail = &pair{a[i], tail}
    };
    return tail
}
func items(v any)([]any, bool){
    a:=[]any{};
    for{
        p, ok:=v.(*pair);
        if !ok{
            return a, v == nilValue
        };
        a = append(a, p.car);
        v = p.cdr
    }
}
func truth(v any)bool{
    b, ok:=v.(bool);
    return !ok || b
}
func repr(v any, quoted bool)string{
    switch x:=v.(type){
        case marker:
        if x == nilValue{
            return "()"
        };
        return "#<void>";
        case bool:
        if x{
            return "#t"
        };
        return "#f";
        case int64:
        return strconv.FormatInt(x, 10);
        case string:
        if !quoted{
            return x
        };
        s:=strings.NewReplacer("\\", "\\\\", "\"", "\\\"", "\n", "\\n").Replace(x);
        return "\""+s+"\"";
        case symbol:
        return string(x);
        case *procedure:
        if x.name == ""{
            return "#<procedure>"
        };
        return "#<procedure "+x.name+">";
        case *pair:
        a:=[]string{};
        for{
            p, ok:=v.(*pair);
            if !ok{
                break
            };
            a = append(a, repr(p.car, quoted));
            v = p.cdr
        };
        if v != nilValue{
            a = append(a, ".", repr(v, quoted))
        };
        return "("+strings.Join(a, " ")+")"
    };
    return ""
}
func same(a, b any, deep bool)bool{
    p, ok:=a.(*pair);
    q, other:=b.(*pair);
    if ok && other{
        if deep{
            return same(p.car, q.car, true) && same(p.cdr, q.cdr, true)
        };
        return p == q
    };
    return a == b
}
func shape(b bool, x any){
    if !b{
        fail("bad syntax: "+repr(x, true))
    }
}
func parameters(v any)(names []string, rest string, valid bool){
    seen:=map[string]bool{};
    for{
        p, ok:=v.(*pair);
        if !ok{
            break
        };
        s, ok:=p.car.(symbol);
        if !ok || seen[string(s)]{
            return nil, "", false
        };
        names = append(names, string(s));
        seen[string(s)] = true;
        v = p.cdr
    };
    if v == nilValue{
        return names, "", true
    };
    s, ok:=v.(symbol);
    if !ok || seen[string(s)]{
        return nil, "", false
    };
    return names, string(s), true
}
func closure(p []string, r string, b []any, e *environment, n string)*procedure{
    return &procedure{name: n, minimum: len(p), variadic: r != "", rest: r, params: p, body: b, env: e}
}
type binding struct{
    name string;
    expr any
}
func bindings(v any, unique bool)([]binding, bool){
    a, ok:=items(v);
    if !ok{
        return nil, false
    };
    bs:=[]binding{};
    seen:=map[string]bool{};
    for _, x:=range a{
        b, ok:=items(x);
        if !ok || len(b) != 2{
            return nil, false
        };
        s, ok:=b[0].(symbol);
        if !ok || unique && seen[string(s)]{
            return nil, false
        };
        seen[string(s)] = true;
        bs = append(bs, binding{string(s), b[1]})
    };
    return bs, true
}
func body(a []any, e *environment)any{
    var v any = voidValue;
    for _, x:=range a{
        v = evaluate(x, e)
    };
    return v
}
func(p *procedure)call(a []any)any{
    if len(a)<p.minimum || !p.variadic && len(a) != p.minimum{
        expected:=strconv.Itoa(p.minimum);
        if p.variadic{
            expected = "at least "+expected
        };
        name:=p.name;
        if name == ""{
            name = "lambda"
        };
        fail(fmt.Sprintf("%s: wrong number of arguments (expected %s, got %d)", name, expected, len(a)))
    };
    if p.builtin != nil{
        return p.builtin(a)
    };
    e:=scope(p.env);
    for i, n:=range p.params{
        e.frame[n] = a[i]
    };
    if p.rest != ""{
        e.frame[p.rest] = list(a[p.minimum: ], nilValue)
    };
    return body(p.body, e)
}
func evaluate(x any, e *environment)any{
    if s, ok:=x.(symbol); ok{
        return e.get(string(s))
    };
    if _, ok:=x.(*pair); !ok{
        shape(x != nilValue, x);
        return x
    };
    a, ok:=items(x);
    shape(ok, x);
    n:=len(a);
    h, _:=a[0].(symbol)
    switch string(h){
        case "quote":
        shape(n == 2, x);
        return a[1]
        case "if":
        shape(n == 3 || n == 4, x);
        if truth(evaluate(a[1], e)){
            return evaluate(a[2], e)
        };
        if n == 4{
            return evaluate(a[3], e)
        };
        return voidValue
        case "begin":
        return body(a[1: ], e)
        case "lambda":
        shape(n >= 3, x);
        p, r, ok:=parameters(a[1]);
        shape(ok, x);
        return closure(p, r, a[2: ], e, "")
        case "define":
        if n>1{
            if s, ok:=a[1].(symbol); ok{
                shape(n == 3, x);
                v:=evaluate(a[2], e);
                if f, ok:=v.(*procedure); ok && f.builtin == nil && f.name == ""{
                    f.name = string(s)
                };
                e.frame[string(s)] = v;
                return voidValue
            }
        }
        shape(n >= 3, x);
        target, ok:=a[1].(*pair);
        shape(ok, x);
        name, ok:=target.car.(symbol);
        shape(ok, x);
        p, r, ok:=parameters(target.cdr);
        shape(ok, x);
        e.frame[string(name)] = closure(p, r, a[2: ], e, string(name));
        return voidValue
        case "set!":
        shape(n == 3, x);
        s, ok:=a[1].(symbol);
        shape(ok, x);
        v:=evaluate(a[2], e);
        e.find(string(s)).frame[string(s)] = v;
        return voidValue
        case "let", "let*", "letrec":
        var name symbol;
        if n>1{
            name, _ = a[1].(symbol)
        };
        named:=h == "let" && name != "";
        at:=1;
        if named{
            at = 2
        };
        shape(n >= at+2, x);
        bs, ok:=bindings(a[at], h != "let*");
        shape(ok, x);
        s:=scope(e)
        if h == "let*"{
            if len(bs)>0{
                s = e
            };
            for _, b:=range bs{
                v:=evaluate(b.expr, s);
                s = scope(s);
                s.frame[b.name] = v
            }
        }else if h == "letrec"{
            for _, b:=range bs{
                s.frame[b.name] = uninitialized
            };
            for _, b:=range bs{
                s.frame[b.name] = evaluate(b.expr, s)
            }
        }else{
            vs:=[]any{};
            names:=[]string{};
            for _, b:=range bs{
                vs = append(vs, evaluate(b.expr, e));
                names = append(names, b.name)
            };
            if named{
                f:=closure(names, "", a[3: ], s, string(name));
                s.frame[string(name)] = f;
                return f.call(vs)
            };
            for i, b:=range bs{
                s.frame[b.name] = vs[i]
            }
        };
        return body(a[at+1: ], s)
        case "cond":
        cs:=[][]any{};
        for i:=1; i<n; i++{
            c, ok:=items(a[i]);
            shape(ok && len(c)>0, x);
            if s, ok:=c[0].(symbol); ok && s == "else"{
                shape(len(c) >= 2 && i == n-1, x)
            };
            cs = append(cs, c)
        };
        for _, c:=range cs{
            if s, ok:=c[0].(symbol); ok && s == "else"{
                return body(c[1: ], e)
            };
            v:=evaluate(c[0], e);
            if truth(v){
                if len(c) == 1{
                    return v
                };
                return body(c[1: ], e)
            }
        };
        return voidValue
        case "and":
        var v any = true;
        for _, z:=range a[1: ]{
            v = evaluate(z, e);
            if !truth(v){
                break
            }
        };
        return v
        case "or":
        for _, z:=range a[1: ]{
            v:=evaluate(z, e);
            if truth(v){
                return v
            }
        };
        return false
        case "when", "unless":
        shape(n >= 3, x);
        if truth(evaluate(a[1], e)) == (h == "when"){
            return body(a[2: ], e)
        };
        return voidValue
    }
    f:=evaluate(a[0], e);
    args:=[]any{};
    for _, z:=range a[1: ]{
        args = append(args, evaluate(z, e))
    };
    p, ok:=f.(*procedure);
    if !ok{
        fail("not a procedure: "+repr(f, true))
    };
    return p.call(args)
}
var mid bool
func write(s string){
    fmt.Print(s);
    if len(s)>0{
        mid = !strings.HasSuffix(s, "\n")
    }
}
func line(s string){
    if mid{
        write("\n")
    };
    write(s+"\n")
}
func expect(n string, v any, k string)any{
    ok:=false;
    switch k{
        case "integer":
        _, ok = v.(int64);
        case "string":
        _, ok = v.(string);
        case "pair":
        _, ok = v.(*pair);
        case "procedure":
        _, ok = v.(*procedure);
        case "list":
        _, ok = items(v)
    };
    if !ok{
        fail(n+": expected "+k+", got "+repr(v, true))
    };
    return v
}
func asList(n string, v any)[]any{
    expect(n, v, "list");
    a, _:=items(v);
    return a
}
func global()*environment{
    e:=scope(nil);
    add:=func(n string, m int, r bool, fn func([]any)any){
        e.frame[n] = &procedure{name: n, minimum: m, variadic: r, builtin: fn}
    }
    for _, name:=range []string{"+", "*", "-", "quotient", "remainder", "modulo", "abs", "min", "max", "gcd", "=", "<", ">", "<=", ">="}{
        fixed:=-1;
        if name == "quotient" || name == "remainder" || name == "modulo"{
            fixed = 2
        }else if name == "abs"{
            fixed = 1
        };
        m:=fixed;
        if m<0{
            m = 1;
            if name == "+" || name == "*" || name == "gcd"{
                m = 0
            }
        };
        add(name, m, fixed<0, func(a []any)any{
            nums:=make([]int64, len(a));
            for i, v:=range a{
                nums[i] = expect(name, v, "integer").(int64)
            };
            var v int64;
            if len(nums)>0{
                v = nums[0]
            }
            switch name{
                case "+", "*":
                v = 0;
                if name == "*"{
                    v = 1
                };
                for _, x:=range nums{
                    if name == "+"{
                        v += x
                    }else{
                        v *= x
                    }
                };
                return v
                case "-":
                if len(a) == 1{
                    return -v
                };
                for _, x:=range nums[1: ]{
                    v -= x
                };
                return v
                case "abs":
                if v<0{
                    return -v
                };
                return v
                case "min", "max":
                for _, x:=range nums{
                    if name == "min" && x<v || name == "max" && x>v{
                        v = x
                    }
                };
                return v
                case "gcd":
                v = 0;
                for _, b:=range nums{
                    if b<0{
                        b = -b
                    };
                    for b != 0{
                        v, b = b, v%b
                    }
                };
                return v
                case "quotient", "remainder", "modulo":
                b:=nums[1];
                if b == 0{
                    fail(name+": division by zero")
                };
                if name == "quotient"{
                    return v/b
                };
                r:=v%b;
                if name == "modulo" && r != 0 && (r<0) != (b<0){
                    r += b
                };
                return r
            }
            for i:=1; i<len(nums); i++{
                l, r:=nums[i-1], nums[i];
                ok:=false;
                switch name{
                    case "=":
                    ok = l == r;
                    case "<":
                    ok = l<r;
                    case ">":
                    ok = l>r;
                    case "<=":
                    ok = l <= r;
                    case ">=":
                    ok = l >= r
                };
                if !ok{
                    return false
                }
            };
            return true
        })
    }
    add("not", 1, false, func(a []any)any{
        return !truth(a[0])
    });
    for _, n:=range []string{"eq?", "equal?"}{
        add(n, 2, false, func(a []any)any{
            return same(a[0], a[1], n == "equal?")
        })
    }
    for _, n:=range []string{"null?", "pair?", "list?", "number?", "symbol?", "procedure?"}{
        add(n, 1, false, func(a []any)any{
            switch n{
                case "null?":
                return a[0] == nilValue;
                case "pair?":
                _, ok:=a[0].(*pair);
                return ok;
                case "list?":
                _, ok:=items(a[0]);
                return ok;
                case "number?":
                _, ok:=a[0].(int64);
                return ok;
                case "symbol?":
                _, ok:=a[0].(symbol);
                return ok
            };
            _, ok:=a[0].(*procedure);
            return ok
        })
    }
    add("cons", 2, false, func(a []any)any{
        return &pair{a[0], a[1]}
    });
    add("list", 0, true, func(a []any)any{
        return list(a, nilValue)
    })
    for _, n:=range []string{"car", "cdr", "cadr"}{
        add(n, 1, false, func(a []any)any{
            p:=expect(n, a[0], "pair").(*pair);
            if n == "car"{
                return p.car
            };
            if n == "cdr"{
                return p.cdr
            };
            return expect(n, p.cdr, "pair").(*pair).car
        })
    }
    for _, n:=range []string{"length", "reverse", "list-ref"}{
        m:=1;
        if n == "list-ref"{
            m = 2
        };
        add(n, m, false, func(a []any)any{
            z:=asList(n, a[0]);
            if n == "length"{
                return int64(len(z))
            };
            if n == "reverse"{
                for i, j:=0, len(z)-1; i<j; i, j = i+1, j-1{
                    z[i], z[j] = z[j], z[i]
                };
                return list(z, nilValue)
            };
            k:=expect(n, a[1], "integer").(int64);
            if k<0 || k >= int64(len(z)){
                fail(fmt.Sprintf("list-ref: index out of range: %d", k))
            };
            return z[k]
        })
    }
    add("append", 0, true, func(a []any)any{
        if len(a) == 0{
            return nilValue
        };
        z:=[]any{};
        for _, v:=range a[: len(a)-1]{
            z = append(z, asList("append", v)...)
        };
        return list(z, a[len(a)-1])
    })
    for _, n:=range []string{"map", "filter", "fold-left", "apply"}{
        m:=2;
        if n == "fold-left"{
            m = 3
        };
        add(n, m, n != "filter", func(a []any)any{
            f:=expect(n, a[0], "procedure").(*procedure);
            if n == "apply"{
                z:=append([]any{}, a[1: len(a)-1]...);
                z = append(z, asList(n, a[len(a)-1])...);
                return f.call(z)
            };
            first:=1;
            if n == "fold-left"{
                first = 2
            };
            ls:=[][]any{};
            count:=int(^uint(0)>>1);
            for _, v:=range a[first: ]{
                z:=asList(n, v);
                ls = append(ls, z);
                if len(z)<count{
                    count = len(z)
                }
            };
            out:=[]any{};
            acc:=a[1];
            for i:=0; i<count; i++{
                if n == "filter"{
                    if truth(f.call([]any{ls[0][i]})){
                        out = append(out, ls[0][i])
                    }
                }else{
                    z:=[]any{};
                    if n == "fold-left"{
                        z = append(z, acc)
                    };
                    for _, l:=range ls{
                        z = append(z, l[i])
                    };
                    v:=f.call(z);
                    if n == "map"{
                        out = append(out, v)
                    }else{
                        acc = v
                    }
                }
            };
            if n == "fold-left"{
                return acc
            };
            return list(out, nilValue)
        })
    }
    add("string-append", 0, true, func(a []any)any{
        s:="";
        for _, v:=range a{
            s += expect("string-append", v, "string").(string)
        };
        return s
    });
    add("number->string", 1, false, func(a []any)any{
        return repr(expect("number->string", a[0], "integer"), true)
    })
    add("display", 1, false, func(a []any)any{
        write(repr(a[0], false));
        return voidValue
    });
    add("newline", 0, false, func(a []any)any{
        write("\n");
        return voidValue
    });
    add("error", 1, true, func(a []any)any{
        s:=expect("error", a[0], "string").(string);
        for _, v:=range a[1: ]{
            s += " "+repr(v, true)
        };
        fail(s);
        return voidValue
    });
    return e
}
type token struct{
    kind byte;
    value any
}
type reader struct{
    lines []string;
    row, col int
}
func(r *reader)skip(){
    r.row++;
    r.col = 0
}
func(r *reader)end()bool{
    for r.row<len(r.lines){
        s:=r.lines[r.row];
        for r.col<len(s) && s[r.col] == ' '{
            r.col++
        };
        if r.col<len(s) && s[r.col] != ';'{
            return false
        };
        r.skip()
    };
    return true
}
var integerPattern = regexp.MustCompile(`^[+-]?[0-9]+$`)
func(r *reader)token()token{
    if r.end(){
        fail("unexpected end of input")
    };
    s:=r.lines[r.row];
    c:=s[r.col];
    r.col++;
    if strings.ContainsRune("()'", rune(c)){
        return token{kind: c}
    };
    if c == '"'{
        v:="";
        for r.col<len(s){
            c = s[r.col];
            r.col++;
            if c == '"'{
                return token{'v', v}
            };
            if c == '\\'{
                if r.col == len(s){
                    break
                };
                c = s[r.col];
                r.col++;
                if c != '"' && c != '\\' && c != 'n'{
                    fail("bad escape")
                };
                if c == 'n'{
                    c = '\n'
                }
            };
            v += string(c)
        };
        fail("unterminated string")
    };
    start:=r.col-1;
    for r.col<len(s) && !strings.ContainsRune(" ()'\";", rune(s[r.col])){
        r.col++
    };
    a:=s[start: r.col];
    if a == "."{
        return token{kind: '.'}
    };
    if integerPattern.MatchString(a){
        n, _:=strconv.ParseInt(a, 10, 64);
        return token{'v', n}
    };
    if a == "#t" || a == "#f"{
        return token{'v', a == "#t"}
    };
    if a[0] == '#'{
        fail("bad token: "+a)
    };
    return token{'v', symbol(a)}
}
func(r *reader)datum()any{
    return r.from(r.token())
}
func(r *reader)from(t token)any{
    if t.kind == 'v'{
        return t.value
    };
    if t.kind == '\''{
        return list([]any{symbol("quote"), r.datum()}, nilValue)
    };
    if t.kind != '('{
        fail("unexpected "+string(t.kind))
    };
    a:=[]any{};
    for{
        t = r.token();
        if t.kind == ')'{
            return list(a, nilValue)
        };
        if t.kind == '.' && len(a)>0{
            tail:=r.datum();
            if r.token().kind != ')'{
                fail("expected )")
            };
            return list(a, tail)
        };
        a = append(a, r.from(t))
    }
}
func readOne(r *reader)(x any, reason string, ok bool){
    ok = true;
    defer func(){
        if p:=recover(); p != nil{
            reason = fmt.Sprint(p);
            ok = false
        }
    }();
    x = r.datum();
    return
}
func evalOne(x any, e *environment)(v any, reason string, ok bool){
    ok = true;
    defer func(){
        if p:=recover(); p != nil{
            reason = fmt.Sprint(p);
            ok = false
        }
    }();
    v = evaluate(x, e);
    return
}
func main(){
    scanner:=bufio.NewScanner(os.Stdin);
    r:=&reader{};
    for scanner.Scan(){
        s:=scanner.Text();
        if s == "(exit)"{
            break
        };
        r.lines = append(r.lines, s)
    };
    e:=global();
    for !r.end(){
        x, err, ok:=readOne(r);
        if !ok{
            line("Error: read: "+err);
            if err == "unexpected end of input"{
                break
            };
            r.skip();
            continue
        };
        v, err, ok:=evalOne(x, e);
        if !ok{
            line("Error: "+err)
        }else if v != voidValue{
            line(repr(v, true))
        }
    };
    if mid{
        write("\n")
    }
}
