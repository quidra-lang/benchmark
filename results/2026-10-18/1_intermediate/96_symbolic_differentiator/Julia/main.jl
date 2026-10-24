using Printf
const FUNCTIONS = Set(["sin","cos","tan","exp","ln","sqrt"])
struct Form
    kind::Int
    q::Rational{Int64}
    name::String
    args::Vector{Form}
end
num(p, q=1) = Form(5, p//q, "", Form[])
node(k, a=Form[], s="") = Form(k, 0//1, s, a)
const ZERO, ONE, MINUS, HALF = num(0), num(1), num(-1), num(1,2)
Base.:(==)(a::Form,b::Form) = a.kind==b.kind && a.q==b.q && a.name==b.name && a.args==b.args
Base.hash(f::Form,h::UInt) = hash((f.kind,f.q,f.name,f.args),h)
isint(f) = f.kind==5 && denominator(f.q)==1
negative(f) = f.kind==3 && f.args[2].kind==5 && f.args[2].q<0
base(f) = f.kind==3 ? f.args[1] : f
exponent(f) = f.kind==3 ? f.args[2] : ONE
function coefficient(f)
    f.kind==5 && return (f.q,Form[])
    f.kind==2 && return f.args[1].kind==5 ? (f.args[1].q,f.args[2:end]) : (1//1,f.args)
    (1//1,[f])
end
function compare(a,b)
    a.kind!=b.kind && return cmp(a.kind,b.kind)
    a.kind==5 && return cmp(a.q,b.q)
    a.name!=b.name && return cmp(a.name,b.name)
    for (s,t) in zip(a.args,b.args)
        c=compare(s,t); c!=0 && return c
    end
    cmp(length(a.args),length(b.args))
end
function exponent_compare(a,b)
    a.kind==5 && b.kind!=5 && return -1
    a.kind!=5 && b.kind==5 && return 1
    compare(a,b)
end
function term_compare(a,b)
    x,y=coefficient(a)[2],coefficient(b)[2]
    bs=sort!(unique(base.(vcat(x,y)));lt=(s,t)->compare(s,t)<0)
    for f in bs
        i,j=findfirst(g->base(g)==f,x),findfirst(g->base(g)==f,y)
        c=exponent_compare(j===nothing ? ZERO : exponent(y[j]),i===nothing ? ZERO : exponent(x[i]))
        c!=0 && return c
    end
    0
end
function product(c,a)
    isempty(a) && return num(c)
    c!=1 && return node(2,vcat([num(c)],a))
    length(a)==1 ? a[1] : node(2,a)
end
function add(operands::Form...)
    terms=Form[]
    for f in operands
        if f.kind==1
            append!(terms,f.args)
        elseif f.kind==2 && length(f.args)==2 && f.args[1].kind==5 && f.args[2].kind==1
            append!(terms,[mul(f.args[1],t) for t in f.args[2].args])
        else
            push!(terms,f)
        end
    end
    monomials=Vector{Form}[]; coefficients=Rational{Int64}[]
    for f in terms
        c,m=coefficient(f); i=findfirst(==(m),monomials)
        if i===nothing; push!(monomials,m);push!(coefficients,c)
        else coefficients[i]+=c end
    end
    built=[product(coefficients[i],monomials[i]) for i in eachindex(coefficients) if coefficients[i]!=0]
    sort!(built;lt=(a,b)->term_compare(a,b)<0)
    isempty(built) ? ZERO : length(built)==1 ? built[1] : node(1,built)
end
function mul(operands::Form...)
    c=1//1; bs=Form[]; groups=Vector{Form}[]
    for f in reduce(vcat,[t.kind==2 ? t.args : [t] for t in operands];init=Form[])
        if f.kind==5; c*=f.q
        else
            b=base(f);i=findfirst(==(b),bs)
            if i===nothing;push!(bs,b);push!(groups,[f])
            else push!(groups[i],f) end
        end
    end
    c==0 && return ZERO
    r=[length(g)==1 ? g[1] : power(bs[i],add(exponent.(g)...)) for (i,g) in enumerate(groups)]
    if any(f->f.kind in (2,5),r) || length(unique(base.(r)))<length(r)
        return mul(num(c),r...)
    end
    product(c,sort!(r;lt=(a,b)->compare(base(a),base(b))<0))
end
function integer_root(v,d)
    v==1 && return 1
    d>20 && return nothing
    r=round(Int,v^(1/d))
    for s in max(0,r-1):r+1
        big(s)^d==v && return s
    end
    nothing
end
function power(b,x)
    x==ZERO && return ONE
    x==ONE && return b
    if b.kind==5
        b==ONE && return ONE
        x.kind!=5 && return node(3,[b,x])
        if b.q==0
            x.q>0 && return ZERO
            error("division by zero")
        end
        isint(x) && return num(b.q^numerator(x.q))
        if b.q>0
            s,t=integer_root(numerator(b.q),denominator(x.q)),integer_root(denominator(b.q),denominator(x.q))
            s!==nothing && t!==nothing && return num((s//t)^numerator(x.q))
        end
    elseif isint(x)
        b.kind==3 && return power(b.args[1],mul(b.args[2],x))
        b.kind==2 && return mul([power(f,x) for f in b.args]...)
    end
    node(3,[b,x])
end
function fn(s,a)
    s=="sqrt" && return power(a,HALF)
    a==ZERO && s in ("sin","tan") && return ZERO
    a==ZERO && s in ("cos","exp") && return ONE
    a==ONE && s=="ln" && return ZERO
    if s in ("sin","cos","tan") && coefficient(a)[1]<0
        r=fn(s,mul(MINUS,a));return s=="cos" ? r : mul(MINUS,r)
    end
    a.kind==4 && ((s=="exp" && a.name=="ln") || (s=="ln" && a.name=="exp")) && return a.args[1]
    node(4,[a],s)
end
variables(f) = f.kind==0 ? [f.name] : sort!(unique(reduce(vcat,variables.(f.args);init=String[])))
function derivative(f,v)
    f.kind==5 && return ZERO
    f.kind==0 && return f.name==v ? ONE : ZERO
    f.kind==1 && return add([derivative(t,v) for t in f.args]...)
    f.kind==2 && return add([mul([i==j ? derivative(t,v) : t for (j,t) in enumerate(f.args)]...) for i in eachindex(f.args)]...)
    if f.kind==3
        b,x=f.args
        !(v in variables(x)) && return mul(x,power(b,add(x,MINUS)),derivative(b,v))
        !(v in variables(b)) && return mul(f,fn("ln",b),derivative(x,v))
        return mul(f,add(mul(derivative(x,v),fn("ln",b)),mul(x,derivative(b,v),power(b,MINUS))))
    end
    a=f.args[1]
    h=f.name=="sin" ? fn("cos",a) : f.name=="cos" ? mul(MINUS,fn("sin",a)) : f.name=="tan" ? power(fn("cos",a),num(-2)) : f.name=="exp" ? f : power(a,MINUS)
    mul(h,derivative(a,v))
end
rebuild(f,a) = f.kind==1 ? add(a...) : f.kind==2 ? mul(a...) : f.kind==3 ? power(a...) : fn(f.name,a[1])
substitute(f,m) = f.kind==0 ? get(m,f.name,f) : f.kind==5 ? f : rebuild(f,[substitute(t,m) for t in f.args])
terms(f) = f.kind==1 ? f.args : [f]
distribute(a,b) = add([mul(x,y) for x in terms(a) for y in terms(b)]...)
function expand(f)
    f.kind in (0,5) && return f
    a=expand.(f.args)
    f.kind==2 && return reduce(distribute,a)
    if f.kind==3 && a[1].kind==1 && isint(a[2]) && a[2].q>0
        r=a[1]
        for _ in 2:numerator(a[2].q);r=distribute(r,a[1]);end
        return r
    end
    rebuild(f,a)
end
function numeric(f)
    f.kind==5 && return Float64(f.q)
    f.kind==1 && return foldl((r,t)->r+numeric(t),f.args;init=0.0)
    f.kind==2 && return foldl((r,t)->r*numeric(t),f.args;init=1.0)
    if f.kind==3
        u,z=numeric.(f.args)
        integral=f.args[2].kind==5 ? isint(f.args[2]) : isinteger(z)
        u<0 && !integral && error("domain error")
        return f.args[2]==HALF ? sqrt(u) : u^z
    end
    a=numeric(f.args[1])
    f.name=="ln" && a<=0 && error("domain error")
    f.name=="ln" ? log(a) : f.name=="sin" ? sin(a) : f.name=="cos" ? cos(a) : f.name=="tan" ? tan(a) : exp(a)
end
atomic(f) = f.kind in (0,4) || (isint(f) && f.q>=0) || (f.kind==3 && f.args[2]==HALF)
atom(f) = atomic(f) ? show_form(f) : "("*show_form(f)*")"
show_power(b,x) = x==HALF ? "sqrt("*show_form(b)*")" : atom(b)*"^"*atom(x)
factor(f) = f.kind==1 ? "("*show_form(f)*")" : f.kind==3 ? show_power(f.args...) : show_form(f)
function quotient(c,a)
    p,q=abs(numerator(c)),denominator(c); top=p==1 ? String[] : [string(p)];bottom=q==1 ? String[] : [string(q)]
    for f in a
        if negative(f)
            r=num(-f.args[2].q);push!(bottom,r==ONE ? factor(f.args[1]) : show_power(f.args[1],r))
        else push!(top,factor(f)) end
    end
    s=isempty(top) ? "1" : join(top,"*")
    !isempty(bottom) && (s*=length(bottom)==1 ? "/"*bottom[1] : "/("*join(bottom,"*")*")")
    c<0 ? "-"*s : s
end
function show_form(f)
    f.kind==5 && return string(numerator(f.q))*(denominator(f.q)==1 ? "" : "/"*string(denominator(f.q)))
    f.kind==0 && return f.name
    f.kind==4 && return f.name*"("*show_form(f.args[1])*")"
    f.kind==3 && return negative(f) ? quotient(1//1,[f]) : show_power(f.args...)
    f.kind==2 && return quotient(coefficient(f)...)
    reduce((a,b)->a*(startswith(b,"-") ? " - "*b[2:end] : " + "*b),show_form.(f.args))
end
struct Syntax
    op::String
    args::Vector{Syntax}
    form::Union{Nothing,Form}
end
leaf(f)=Syntax("",Syntax[],f)
syntax(op,a...)=Syntax(op,collect(a),nothing)
function parse_form(text,names)
    tokens=String[]
    for m in eachmatch(r"[0-9]+|[a-z][a-z0-9]*|[A-Z][A-Z0-9]*|[-+*/^()]| +|.",text)
        t=String(m.match);startswith(t," ") && continue
        !occursin(r"^[a-zA-Z0-9+*/^()-]+$",t) && error("invalid character '$t'")
        push!(tokens,t)
    end
    p=1
    peek()=p<=length(tokens) ? tokens[p] : ""
    unexpected()=error(p>length(tokens) ? "unexpected end of expression" : "unexpected '$(peek())'")
    function accept(s)
        peek()!=s && return false
        p+=1;true
    end
    expect(s)=accept(s) || unexpected()
    function atom_tree()
        t=peek();isempty(t) && unexpected()
        if accept("(");a=expression();expect(")");return a;end
        !occursin(r"^[a-zA-Z0-9]",t) && unexpected()
        p+=1
        occursin(r"^[0-9]",t) && return leaf(num(parse(Int,t)))
        if occursin(r"^[A-Z]",t)
            !haskey(names,t) && error("undefined name '$t'")
            return leaf(names[t])
        end
        !(t in FUNCTIONS) && return leaf(node(0,Form[],t))
        expect("(");a=expression();expect(")");syntax(t,a)
    end
    function unary()
        accept("-") && return syntax("neg",unary())
        a=atom_tree();accept("^") ? syntax("^",a,unary()) : a
    end
    function term()
        a=unary()
        while peek() in ("*","/");op=peek();p+=1;a=syntax(op,a,unary());end
        a
    end
    function expression()
        a=term()
        while peek() in ("+","-");op=peek();p+=1;a=syntax(op,a,term());end
        a
    end
    function evaluate(t)
        t.form!==nothing && return t.form
        a=evaluate.(t.args)
        t.op=="+" ? add(a...) : t.op=="-" ? add(a[1],mul(MINUS,a[2])) : t.op=="*" ? mul(a...) : t.op=="/" ? mul(a[1],power(a[2],MINUS)) : t.op=="^" ? power(a...) : t.op=="neg" ? mul(MINUS,a[1]) : fn(t.op,a[1])
    end
    t=expression();p<=length(tokens) && unexpected();evaluate(t)
end
variable(s)=occursin(r"^[a-z][a-z0-9]*$",s) && !(s in FUNCTIONS)
function literal(s)
    !occursin(r"^-?[0-9]+(?:/[0-9]+)?$",s) && error("invalid number '$s'")
    a=parse.(Int,split(s,"/"));q=length(a)==1 ? 1 : a[2];q==0 && error("division by zero");num(a[1],q)
end
const SIGNATURES=Dict("SIMPLIFY"=>"e","EXPAND"=>"e","DIFF"=>"ev","DIFFN"=>"evn","GRAD"=>"e","HESSIAN"=>"e","IMPLICIT"=>"evv","SUBST"=>"eve","EVAL"=>"ea","TANGENT"=>"evc","LIMIT"=>"evc","TAYLOR"=>"evcn")
function command(line,names)
    parts=split(line," ";limit=2);c=parts[1];arg=length(parts)==1 ? "" : parts[2]
    if c=="LET"
        pieces=split(arg,"=";limit=2);length(pieces)!=2 && error("wrong number of arguments")
        s=strip(pieces[1]);!occursin(r"^[A-Z][A-Z0-9]*$",s) && error("invalid name '$s'")
        f=parse_form(strip(pieces[2]),names);names[s]=f;return [s*" = "*show_form(f)]
    end
    !haskey(SIGNATURES,c) && error("unknown command $c")
    fields=length(parts)==1 ? String[] : strip.(split(arg,";";keepempty=true));sig=SIGNATURES[c]
    !(c=="EVAL" ? length(fields) in (1,2) : length(fields)==length(sig)) && error("wrong number of arguments")
    a=Any[]
    for (i,s) in enumerate(fields)
        k=sig[i]
        if k=='e';push!(a,parse_form(s,names))
        elseif k=='v';!variable(s) && error("invalid variable '$s'");push!(a,s)
        elseif k=='n';!occursin(r"^[1-8]$",s) && error("invalid order '$s'");push!(a,parse(Int,s))
        elseif k=='c';push!(a,literal(s))
        else push!(a,s) end
    end
    f=a[1];v=length(a)>=2 ? a[2] : "";x=length(a)>=3 ? a[3] : ZERO
    c=="SIMPLIFY" && return ["simplified: "*show_form(f)]
    c=="EXPAND" && return ["expanded: "*show_form(expand(f))]
    c=="DIFF" && return ["d/d$v = "*show_form(derivative(f,v))]
    if c=="DIFFN"
        out=String[];for k in 1:x;f=derivative(f,v);push!(out,"d^$k/d$v^$k = "*show_form(f));end;return out
    end
    if c in ("GRAD","HESSIAN")
        vs=variables(f);isempty(vs) && return ["no variables"];out=String[]
        for (i,s) in enumerate(vs)
            d=derivative(f,s)
            if c=="GRAD";push!(out,"d/d$s = "*show_form(d))
            else for t in vs[i:end];push!(out,"d2/d$(s)d$t = "*show_form(derivative(d,t)));end end
        end
        return out
    end
    if c=="IMPLICIT"
        v==x && error("same variable")
        return ["d$x/d$v = "*show_form(mul(MINUS,derivative(f,v),power(derivative(f,x),MINUS)))]
    end
    c=="SUBST" && return ["substituted: "*show_form(substitute(f,Dict(v=>x)))]
    if c=="EVAL"
        values=Dict{String,Form}()
        for word in split(v)
            m=match(r"^([a-z][a-z0-9]*)=(-?[0-9]+(?:/[0-9]+)?)$",word)
            (m===nothing || !variable(m[1])) && error("invalid assignment '$word'")
            q=literal(m[2]);haskey(values,m[1]) && error("duplicate variable $(m[1])");values[m[1]]=q
        end
        for s in variables(f);!haskey(values,s) && error("no value for $s");end
        r=substitute(f,values);return [r.kind==5 ? "exact: "*show_form(r) : @sprintf("approx: %.6f",numeric(r))]
    end
    point=Dict(v=>x)
    if c=="TANGENT"
        m=substitute(derivative(f,v),point);y=substitute(f,point);z=node(0,Form[],v)
        t="tangent: y = "*show_form(add(mul(m,z),y,mul(num(-x.q),m)))
        m==ZERO && return [t,"normal: $v = "*show_form(x)]
        k=power(m,MINUS);return [t,"normal: y = "*show_form(add(mul(MINUS,k,z),y,mul(x,k)))]
    end
    if c=="LIMIT"
        top=Form[];bottom=Form[]
        for t in f.kind==2 ? f.args : [f]
            negative(t) ? push!(bottom,power(t.args[1],num(-t.args[2].q))) : push!(top,t)
        end
        g,h=mul(top...),mul(bottom...)
        for k in 0:5
            u,b=substitute(g,point),substitute(h,point)
            b!=ZERO && return ["limit: "*show_form(mul(u,power(b,MINUS)))]
            u!=ZERO && return ["limit: unbounded"]
            k<5 && ((g,h)=(derivative(g,v),derivative(h,v)))
        end
        return ["limit: unknown"]
    end
    n=a[4];ds=[f];for _ in 1:n;push!(ds,derivative(ds[end],v));end
    ps=Form[];fac=1
    for k in 0:n
        k>0 && (fac*=k);co=mul(substitute(ds[k+1],point),num(1,fac))
        push!(ps,mul(co,power(add(node(0,Form[],v),num(-x.q)),num(k))))
    end
    ["taylor: "*show_form(expand(add(ps...)))]
end
function main()
    names=Dict{String,Form}()
    for _ in 1:parse(Int,readline())
        line=readline()
        try
            for s in command(line,names);println(s);end
        catch e
            e isa ErrorException || rethrow()
            println("error: ",e.msg)
        end
    end
end
main()
