struct Marker
    kind::Symbol
end
const NIL=Marker(:nil)
const VOID=Marker(:void)
const UNINIT=Marker(:uninitialized)
struct Pair
    car::Any
    cdr::Any
    identity::Ref{Nothing}
    Pair(a,b)=new(a,b,Ref(nothing))
end
mutable struct Env
    frame::Dict{Symbol,Any}
    parent::Union{Env,Nothing}
    Env(p=nothing)=new(Dict{Symbol,Any}(),p)
end
mutable struct Procedure
    name::Union{Symbol,Nothing}
    minimum::Int
    rest::Union{Bool,Symbol}
    params::Vector{Symbol}
    body::Vector{Any}
    env::Union{Env,Nothing}
    builtin::Union{Function,Nothing}
end
fail(s)=throw(ErrorException(s))
function make_list(a,tail=NIL)
    for x in Iterators.reverse(a);tail=Pair(x,tail);end
    tail
end
function items(v)
    a=Any[]
    while v isa Pair;push!(a,v.car);v=v.cdr;end
    v===NIL ? a : nothing
end
truth(v)=v!==false
function repr_value(v,quoted=true)
    v===NIL && return "()"
    v===VOID && return "#<void>"
    v isa Bool && return v ? "#t" : "#f"
    v isa Integer && return string(v)
    v isa String && return quoted ? "\""*replace(v,"\\"=>"\\\\","\""=>"\\\"","\n"=>"\\n")*"\"" : v
    v isa Symbol && return string(v)
    v isa Procedure && return isnothing(v.name) ? "#<procedure>" : "#<procedure $(v.name)>"
    a=String[]
    while v isa Pair;push!(a,repr_value(v.car,quoted));v=v.cdr;end
    v!==NIL && append!(a,[".",repr_value(v,quoted)])
    "("*join(a," ")*")"
end
function same(a,b,deep=false)
    if a isa Pair && b isa Pair
        return deep ? same(a.car,b.car,true)&&same(a.cdr,b.cdr,true) : a.identity===b.identity
    end
    typeof(a)==typeof(b) && (a isa String ? a==b : a===b)
end
function findenv(e,n)
    while !isnothing(e)
        haskey(e.frame,n) && return e
        e=e.parent
    end
    fail("unbound variable: $n")
end
function lookup(e,n)
    v=findenv(e,n).frame[n]
    v===UNINIT && fail("uninitialized variable: $n")
    v
end
function parameters(v)
    names=Symbol[]
    while v isa Pair
        v.car isa Symbol || return nothing
        push!(names,v.car);v=v.cdr
    end
    r=v isa Symbol ? v : false
    (v===NIL || r isa Symbol) || return nothing
    all=r===false ? names : [names;r]
    length(unique(all))==length(all) ? (names,r) : nothing
end
compound(p,b,e,n=nothing)=Procedure(n,length(p[1]),p[2],p[1],Any[b...],e,nothing)
function bindings(v,unique_names)
    a=items(v);isnothing(a) && return nothing
    bs=Tuple{Symbol,Any}[]
    for x in a
        b=items(x)
        (isnothing(b)||length(b)!=2||!(b[1] isa Symbol)) && return nothing
        push!(bs,(b[1],b[2]))
    end
    unique_names && length(unique(first.(bs)))!=length(bs) && return nothing
    bs
end
shape(ok,x)=ok || fail("bad syntax: "*repr_value(x))
function eval_body(a,e)
    v=VOID
    for x in a;v=evaluate(x,e);end
    v
end
function call_proc(f,a)
    if length(a)<f.minimum || (f.rest===false && length(a)!=f.minimum)
        fail("$(isnothing(f.name) ? :lambda : f.name): wrong number of arguments (expected $(f.rest===false ? "" : "at least ")$(f.minimum), got $(length(a)))")
    end
    !isnothing(f.builtin) && return f.builtin(a)
    e=Env(f.env)
    for (n,v) in zip(f.params,a);e.frame[n]=v;end
    f.rest isa Symbol && (e.frame[f.rest]=make_list(a[f.minimum+1:end]))
    eval_body(f.body,e)
end
function evaluate(x,e)
    x isa Symbol && return lookup(e,x)
    if !(x isa Pair);shape(x!==NIL,x);return x;end
    a=items(x);shape(!isnothing(a),x);n=length(a);h=a[1] isa Symbol ? string(a[1]) : ""
    if h=="quote";shape(n==2,x);return a[2]
    elseif h=="if";shape(n==3||n==4,x);return truth(evaluate(a[2],e)) ? evaluate(a[3],e) : n==4 ? evaluate(a[4],e) : VOID
    elseif h=="begin";return eval_body(a[2:end],e)
    elseif h=="lambda";p=n>=3 ? parameters(a[2]) : nothing;shape(!isnothing(p),x);return compound(p,a[3:end],e)
    elseif h=="define"
        if n>1 && a[2] isa Symbol
            shape(n==3,x);v=evaluate(a[3],e)
            v isa Procedure && isnothing(v.builtin) && isnothing(v.name) && (v.name=a[2])
            e.frame[a[2]]=v
        else
            t=n>1 ? a[2] : NIL
            p=n>=3 && t isa Pair && t.car isa Symbol ? parameters(t.cdr) : nothing
            shape(!isnothing(p),x);e.frame[t.car]=compound(p,a[3:end],e,t.car)
        end
        return VOID
    elseif h=="set!";shape(n==3&&a[2] isa Symbol,x);v=evaluate(a[3],e);findenv(e,a[2]).frame[a[2]]=v;return VOID
    elseif h in ("let","let*","letrec")
        named=h=="let"&&n>1&&a[2] isa Symbol;at=named ? 3 : 2
        bs=n>=at+1 ? bindings(a[at],h!="let*") : nothing;shape(!isnothing(bs),x);s=Env(e)
        if h=="let*"
            !isempty(bs) && (s=e)
            for (name,expr) in bs;v=evaluate(expr,s);s=Env(s);s.frame[name]=v;end
        elseif h=="letrec"
            for (name,_) in bs;s.frame[name]=UNINIT;end
            for (name,expr) in bs;s.frame[name]=evaluate(expr,s);end
        else
            vs=Any[evaluate(b[2],e) for b in bs]
            if named
                f=compound((Symbol[first(b) for b in bs],false),a[4:end],s,a[2]);s.frame[a[2]]=f;return call_proc(f,vs)
            end
            for (b,v) in zip(bs,vs);s.frame[b[1]]=v;end
        end
        return eval_body(a[at+1:end],s)
    elseif h=="cond"
        cs=items.(a[2:end])
        for (i,c) in enumerate(cs)
            shape(!isnothing(c)&&!isempty(c),x)
            c[1]===:else && shape(length(c)>=2&&i==length(cs),x)
        end
        for c in cs
            c[1]===:else && return eval_body(c[2:end],e)
            v=evaluate(c[1],e);truth(v) && return length(c)==1 ? v : eval_body(c[2:end],e)
        end
        return VOID
    elseif h=="and"
        v=true;for z in a[2:end];v=evaluate(z,e);!truth(v)&&break;end;return v
    elseif h=="or"
        for z in a[2:end];v=evaluate(z,e);truth(v)&&return v;end;return false
    elseif h=="when"||h=="unless"
        shape(n>=3,x);return truth(evaluate(a[2],e))==(h=="when") ? eval_body(a[3:end],e) : VOID
    end
    f=evaluate(a[1],e);args=Any[evaluate(z,e) for z in a[2:end]]
    f isa Procedure || fail("not a procedure: "*repr_value(f));call_proc(f,args)
end
const mid=Ref(false)
function write_text(s)
    print(s);!isempty(s)&&(mid[]=!endswith(s,"\n"))
end
function write_line(s)
    mid[]&&write_text("\n");write_text(s*"\n")
end
function expect(n,v,k)
    ok=k=="integer" ? v isa Integer && !(v isa Bool) : k=="string" ? v isa String : k=="pair" ? v isa Pair : k=="procedure" ? v isa Procedure : !isnothing(items(v))
    ok||fail("$n: expected $k, got "*repr_value(v));v
end
function global_env()
    e=Env()
    add(n,m,r,fn)=(e.frame[Symbol(n)]=Procedure(Symbol(n),m,r,Symbol[],Any[],nothing,fn))
    for name in ("+","*","-","quotient","remainder","modulo","abs","min","max","gcd","=","<",">","<=",">=")
        fixed=name in ("quotient","remainder","modulo") ? 2 : name=="abs" ? 1 : -1
        add(name,fixed>=0 ? fixed : name in ("+","*","gcd") ? 0 : 1,fixed<0,a->begin
            z=Int64[expect(name,v,"integer") for v in a]
            name=="+"&&return sum(z);name=="*"&&return prod(z);name=="-"&&return length(z)==1 ? -z[1] : z[1]-sum(z[2:end])
            name=="abs"&&return abs(z[1]);name=="min"&&return minimum(z);name=="max"&&return maximum(z)
            if name=="gcd";g=0;for v in z;g=gcd(g,v);end;return g;end
            if name in ("quotient","remainder","modulo")
                z[2]==0&&fail(name*": division by zero")
                return name=="quotient" ? div(z[1],z[2]) : name=="remainder" ? rem(z[1],z[2]) : mod(z[1],z[2])
            end
            all(i->name=="=" ? z[i-1]==z[i] : name=="<" ? z[i-1]<z[i] : name==">" ? z[i-1]>z[i] : name=="<=" ? z[i-1]<=z[i] : z[i-1]>=z[i],2:length(z))
        end)
    end
    add("not",1,false,a->!truth(a[1]));add("eq?",2,false,a->same(a[1],a[2]));add("equal?",2,false,a->same(a[1],a[2],true))
    for name in ("null?","pair?","list?","number?","symbol?","procedure?")
        add(name,1,false,a->name=="null?" ? a[1]===NIL : name=="pair?" ? a[1] isa Pair : name=="list?" ? !isnothing(items(a[1])) : name=="number?" ? a[1] isa Integer&&!(a[1] isa Bool) : name=="symbol?" ? a[1] isa Symbol : a[1] isa Procedure)
    end
    add("cons",2,false,a->Pair(a[1],a[2]));add("list",0,true,make_list)
    for name in ("car","cdr","cadr")
        add(name,1,false,a->begin p=expect(name,a[1],"pair");name=="car" ? p.car : name=="cdr" ? p.cdr : expect(name,p.cdr,"pair").car end)
    end
    for name in ("length","reverse","list-ref")
        add(name,name=="list-ref" ? 2 : 1,false,a->begin
            z=items(expect(name,a[1],"list"));name=="length"&&return length(z);name=="reverse"&&return make_list(reverse(z))
            k=expect(name,a[2],"integer");0<=k<length(z)||fail("list-ref: index out of range: $k");z[k+1]
        end)
    end
    add("append",0,true,a->begin isempty(a)&&return NIL;z=Any[];for v in a[1:end-1];append!(z,items(expect("append",v,"list")));end;make_list(z,a[end]) end)
    for name in ("map","filter","fold-left","apply")
        add(name,name=="fold-left" ? 3 : 2,name!="filter",a->begin
            f=expect(name,a[1],"procedure")
            name=="apply"&&return call_proc(f,vcat(a[2:end-1],items(expect(name,a[end],"list"))))
            ls=[items(expect(name,v,"list")) for v in a[(name=="fold-left" ? 3 : 2):end]];out=Any[];acc=a[2]
            for i in 1:minimum(length.(ls))
                if name=="filter";truth(call_proc(f,Any[ls[1][i]]))&&push!(out,ls[1][i])
                else
                    args=Any[l[i] for l in ls];name=="fold-left"&&pushfirst!(args,acc);v=call_proc(f,args)
                    if name=="map";push!(out,v);else;acc=v;end
                end
            end
            name=="fold-left" ? acc : make_list(out)
        end)
    end
    add("string-append",0,true,a->join([expect("string-append",v,"string") for v in a]))
    add("number->string",1,false,a->string(expect("number->string",a[1],"integer")))
    add("display",1,false,a->begin write_text(repr_value(a[1],false));VOID end);add("newline",0,false,a->begin write_text("\n");VOID end)
    add("error",1,true,a->fail(expect("error",a[1],"string")*join([" "*repr_value(v) for v in a[2:end]])))
    e
end
mutable struct Reader
    lines::Vector{String}
    row::Int
    col::Int
end
skip_line!(r)=(r.row+=1;r.col=1)
function at_end(r)
    while r.row<=length(r.lines)
        s=r.lines[r.row];while r.col<=length(s)&&s[r.col]==' ';r.col+=1;end
        r.col<=length(s)&&s[r.col]!=';'&&return false
        skip_line!(r)
    end
    true
end
function token(r)
    at_end(r)&&fail("unexpected end of input");s=r.lines[r.row];c=s[r.col];r.col+=1
    c in ('(',')','\'')&&return (c,nothing)
    if c=='"'
        v=""
        while r.col<=length(s)
            c=s[r.col];r.col+=1;c=='"'&&return ('v',v)
            if c=='\\'
                r.col>length(s)&&break;c=s[r.col];r.col+=1
                c in ('"','\\','n')||fail("bad escape");c=='n'&&(c='\n')
            end
            v*=c
        end
        fail("unterminated string")
    end
    first=r.col-1;while r.col<=length(s)&&!(s[r.col] in " ()'\";");r.col+=1;end
    a=s[first:r.col-1];a=="."&&return ('.',nothing)
    occursin(r"^[+-]?[0-9]+$",a)&&return ('v',parse(Int64,a))
    a in ("#t","#f")&&return ('v',a=="#t")
    startswith(a,"#")&&fail("bad token: "*a);('v',Symbol(a))
end
function datum(r,t=token(r))
    t[1]=='v'&&return t[2];t[1]=='\''&&return make_list(Any[:quote,datum(r)])
    t[1]=='('||fail("unexpected $(t[1])");a=Any[]
    while true
        t=token(r);t[1]==')'&&return make_list(a)
        if t[1]=='.'&&!isempty(a);tail=datum(r);token(r)[1]==')'||fail("expected )");return make_list(a,tail);end
        push!(a,datum(r,t))
    end
end
function main_program()
    lines=String[];for s in eachline(stdin);s=="(exit)"&&break;push!(lines,s);end
    r=Reader(lines,1,1);e=global_env()
    while !at_end(r)
        x=try datum(r) catch err
            write_line("Error: read: "*err.msg);err.msg=="unexpected end of input"&&break;skip_line!(r);continue
        end
        try
            v=evaluate(x,e);v!==VOID&&write_line(repr_value(v))
        catch err
            write_line("Error: "*err.msg)
        end
    end
    mid[]&&write_text("\n")
end
main_program()
