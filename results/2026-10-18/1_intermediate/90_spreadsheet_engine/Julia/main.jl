abstract type Expression end
struct Node <: Expression
    kind::Char
    n::Int
    row::Int
    flags::Int
    text::String
    a::Union{Nothing,Expression}
    b::Union{Nothing,Expression}
    args::Vector{Node}
end
node(k, n = 0, s = "", a = nothing, b = nothing, args = Node[]) = Node(k, n, 0, 0, s, a, b, args)
num(n) = node('N', n)
text(s) = node('S', 0, s)
err(s) = node('E', 0, s)
reference(c, r, f = 0) = Node('R', c, r, f, "", nothing, nothing, Node[])
const INVALID = node('X')
id(r) = r.row*26+r.n+1
label(i) = string(Char(65+(i-1)%26), div(i-1, 26)+1)
inside(r) = 0<=r.n<26 && 0<=r.row<99
function make_range(a, b)
    c, d, r, t=a.n, b.n, a.row, b.row
    ac, bc, ar, br=a.flags&1, b.flags&1, a.flags&2, b.flags&2
    if c>d
        c, d, ac, bc=d, c, bc, ac
    end
    if r>t
        r, t, ar, br=t, r, br, ar
    end
    node('G', 0, "", reference(c, r, ac|ar), reference(d, t, bc|br))
end
function address(s)
    occursin(r"\A[A-Z][1-9][0-9]?\z", s) || throw(ArgumentError("bad address"))
    reference(Int(s[1])-65, parse(Int, s[2:end])-1)
end
function area(s)
    p=split(s, ':'; keepempty = true)
    length(p)<=2 || throw(ArgumentError("bad address"))
    a=address(p[1])
    b=length(p)==1 ? a : address(p[2])
    make_range(a, b)
end
cells(g) = [r*26+c+1 for r=g.a.row:g.b.row for c=g.a.n:g.b.n]
contains_cell(g, r) = g.a.n<=r.n<=g.b.n && g.a.row<=r.row<=g.b.row
const LEVELS =
    [Set(["=", "<>", "<", "<=", ">", ">="]), Set(["&"]), Set(["+", "-"]), Set(["*", "/"])]
precedence(op) = findfirst(xs->op in xs, LEVELS)
function parse_formula(s)
    tokens=Tuple{Node,Int}[]
    i=2
    syntax(p) = throw(ArgumentError("syntax error at $p"))
    while i<=length(s)
        p=i
        ch=s[i]
        if ch==' '
            i+=1
            continue
        end
        if isdigit(ch)
            j=i
            while j<=length(s)&&isdigit(s[j])
                j+=1
            end
            j-i<10 || syntax(p)
            push!(tokens, (num(parse(Int, s[i:(j-1)])), p))
            i=j
        elseif ch=='"'
            j=findnext('"', s, i+1)
            j===nothing && syntax(p)
            push!(tokens, (text(s[(i+1):(j-1)]), p))
            i=j+1
        elseif isletter(ch)||ch=='\$'
            j=i
            while j<=length(s)&&(isletter(s[j])||isdigit(s[j])||s[j]=='\$')
                j+=1
            end
            w=uppercase(s[i:(j-1)])
            i=j
            m=match(r"\A(\$?)([A-Z])(\$?)([1-9][0-9]?)\z", w)
            if m!==nothing
                x=reference(
                    Int(m[2][1])-65,
                    parse(Int, m[4])-1,
                    (isempty(m[1]) ? 0 : 1)|(isempty(m[3]) ? 0 : 2),
                )
            elseif occursin(r"\A[A-Z][A-Z0-9]*\z", w)
                x=node(startswith(lstrip(s[j:end]), "(") ? 'C' : 'W', 0, w)
            else
                syntax(p)
            end
            push!(tokens, (x, p))
        else
            op=s[i:min(i+1, length(s))]
            op in ("<>", "<=", ">=") || (op=string(ch))
            ch in "+-*/&(),:=<>" || syntax(p)
            push!(tokens, (node('T', 0, op), p))
            i+=length(op)
        end
    end
    push!(tokens, (node('Z'), length(s)+1))
    i=1
    function take(op)
        if tokens[i][1].kind=='T'&&tokens[i][1].text==op
            i+=1
            return true
        end
        false
    end
    expect(op) = take(op) || syntax(tokens[i][2])
    function expression(level = 1)
        level==5 && return primary()
        a=expression(level+1)
        while tokens[i][1].kind=='T'&&tokens[i][1].text in LEVELS[level]
            op=tokens[i][1].text
            i+=1
            a=node('B', 0, op, a, expression(level+1))
        end
        a
    end
    function primary()
        take("-") && return node('U', 0, "", primary())
        x, p=tokens[i]
        i+=1
        x.kind in ('N', 'S', 'W') && return x
        if x.kind=='R'
            take(":") || return x
            tokens[i][1].kind=='R' || syntax(tokens[i][2])
            b=tokens[i][1]
            i+=1
            return make_range(x, b)
        elseif x.kind=='C'
            expect("(")
            args=Node[]
            if !take(")")
                push!(args, expression())
                while take(",")
                    push!(args, expression())
                end
                expect(")")
            end
            return node('F', 0, x.text, nothing, nothing, args)
        elseif x.kind=='T'&&x.text=="("
            a=expression()
            expect(")")
            return a
        end
        syntax(p)
    end
    result=expression()
    tokens[i][1].kind=='Z' || syntax(tokens[i][2])
    result
end
function canonical(x)
    k=x.kind
    k=='N' && return string(x.n)
    k=='S' && return "\""*x.text*"\""
    k=='W' && return x.text
    k=='X' && return "#REF!"
    k=='R' &&
        return (x.flags&1!=0 ? "\$" : "")*string(Char(65+x.n))*(x.flags&2!=0 ? "\$" : "")*string(
            x.row+1,
        )
    k=='G' && return canonical(x.a)*":"*canonical(x.b)
    k=='F' && return x.text*"("*join(canonical.(x.args), ",")*")"
    k=='U' && return "-"*(x.a.kind=='B' ? "("*canonical(x.a)*")" : canonical(x.a))
    a=canonical(x.a)
    b=canonical(x.b)
    x.a.kind=='B'&&precedence(x.a.text)<precedence(x.text) && (a="("*a*")")
    x.b.kind=='B'&&precedence(x.b.text)<=precedence(x.text) && (b="("*b*")")
    a*x.text*b
end
display_value(x) = x===nothing ? "" : x.kind=='N' ? string(x.n) : x.text
notation(x) =
    x===nothing ? "(empty)" :
    x.kind=='=' ? "="*canonical(x.a) : x.kind=='S' ? "\""*x.text*"\"" : display_value(x)
to_number(x) = x===nothing ? num(0) : x.kind in ('S', 'G') ? err("#VALUE!") : x
to_text(x) =
    x===nothing ? text("") : x.kind=='N' ? text(string(x.n)) : x.kind=='G' ? err("#VALUE!") : x
function rewrite(x, f)
    x===nothing && return nothing
    x.kind in ('R', 'G') && return f(x)
    a=rewrite(x.a, f)
    b=rewrite(x.b, f)
    args=Node[rewrite(v, f) for v in x.args]
    a===x.a&&b===x.b&&all(args[j]===x.args[j] for j in eachindex(args)) ? x :
    node(x.kind, x.n, x.text, a, b, args)
end
function dependencies(x, out = Set{Int}())
    x===nothing && return out
    if x.kind=='R'
        push!(out, id(x))
    elseif x.kind=='G'
        union!(out, cells(x))
    else
        dependencies(x.a, out)
        dependencies(x.b, out)
        foreach(a->dependencies(a, out), x.args)
    end
    out
end
mutable struct Sheet
    contents::Vector{Union{Nothing,Node}}
    values::Vector{Union{Nothing,Node}}
    deps::Vector{Set{Int}}
    history::Vector{Tuple{String,Vector{Union{Nothing,Node}}}}
end
grid() = Union{Nothing,Node}[nothing for _=1:2574]
Sheet() =
    Sheet(grid(), grid(), [Set{Int}() for _=1:2574], Tuple{String,Vector{Union{Nothing,Node}}}[])
function evaluate(sheet, x)
    k=x.kind
    k in ('N', 'S', 'G') && return x
    k=='R' && return sheet.values[id(x)]
    k=='W' && return err("#NAME?")
    k=='X' && return err("#REF!")
    if k=='U'
        a=to_number(evaluate(sheet, x.a))
        return a.kind=='E' ? a : num(-a.n)
    end
    if k=='B'
        a=evaluate(sheet, x.a)
        b=evaluate(sheet, x.b)
        op=x.text
        a!==nothing&&a.kind=='E' && return a
        b!==nothing&&b.kind=='E' && return b
        if precedence(op)==1
            ((a!==nothing&&a.kind=='G')||(b!==nothing&&b.kind=='G')) && return err("#VALUE!")
            strings=(a!==nothing&&a.kind=='S')||(b!==nothing&&b.kind=='S')
            blank=strings ? text("") : num(0)
            a===nothing && (a=blank)
            b===nothing && (b=blank)
            c=a.kind!=b.kind ? (a.kind=='N' ? -1 : 1) :
              a.kind=='N' ? cmp(a.n, b.n) : cmp(a.text, b.text)
            yes=op=="=" ? c==0 :
                op=="<>" ? c!=0 : op=="<" ? c<0 : op=="<=" ? c<=0 : op==">" ? c>0 : c>=0
            return num(Int(yes))
        end
        convert=op=="&" ? to_text : to_number
        a=convert(a)
        b=convert(b)
        a.kind=='E' && return a
        b.kind=='E' && return b
        return op=="&" ? text(a.text*b.text) :
               op=="+" ? num(a.n+b.n) :
               op=="-" ? num(a.n-b.n) :
               op=="*" ? num(a.n*b.n) : b.n==0 ? err("#DIV/0!") : num(div(a.n, b.n))
    end
    name=x.text
    args=x.args
    if name in ("SUM", "MIN", "MAX", "COUNT", "AVERAGE", "AND", "OR", "CONCAT")
        isempty(args) && return err("#VALUE!")
        items=Union{Nothing,Node}[]
        for a in args
            v=evaluate(sheet, a)
            if v!==nothing&&v.kind=='G'
                append!(items, sheet.values[cells(v)])
            else
                push!(items, v)
            end
        end
        ns=[v.n for v in items if v!==nothing&&v.kind=='N']
        name=="COUNT" && return num(length(ns))
        for v in items
            v!==nothing&&v.kind=='E' && return v
        end
        name=="CONCAT" && return text(join(to_text(v).text for v in items))
        name=="SUM" && return num(sum(ns))
        name=="MIN" && return num(isempty(ns) ? 0 : minimum(ns))
        name=="MAX" && return num(isempty(ns) ? 0 : maximum(ns))
        isempty(ns) && return err(name=="AVERAGE" ? "#DIV/0!" : "#VALUE!")
        name=="AVERAGE" && return num(div(sum(ns), length(ns)))
        return num(Int(name=="AND" ? all(!=(0), ns) : any(!=(0), ns)))
    elseif name=="IF"
        length(args) in (2, 3) || return err("#VALUE!")
        c=to_number(evaluate(sheet, args[1]))
        c.kind=='E' && return c
        return c.n!=0 ? evaluate(sheet, args[2]) :
               length(args)==3 ? evaluate(sheet, args[3]) : num(0)
    end
    name in ("ABS", "NOT", "LEN") || return err("#NAME?")
    length(args)==1 || return err("#VALUE!")
    v=evaluate(sheet, args[1])
    v=name=="LEN" ? to_text(v) : to_number(v)
    v.kind=='E' ? v : num(name=="LEN" ? length(v.text) : name=="ABS" ? abs(v.n) : Int(v.n==0))
end
function recalculate!(sheet)
    sheet.deps=[x!==nothing&&x.kind=='=' ? dependencies(x.a) : Set{Int}() for x in sheet.contents]
    sheet.values=Union{Nothing,Node}[x!==nothing&&x.kind=='=' ? nothing : x for x in sheet.contents]
    indices=fill(-1, 2574)
    low=zeros(Int, 2574)
    on=falses(2574)
    cyclic=falses(2574)
    done=falses(2574)
    stack=Int[]
    serial=0
    function visit(i)
        indices[i]=low[i]=serial
        serial+=1
        push!(stack, i)
        on[i]=true
        for j in sheet.deps[i]
            if sheet.contents[j]!==nothing&&sheet.contents[j].kind=='='
                if indices[j]<0
                    visit(j)
                    low[i]=min(low[i], low[j])
                elseif on[j]
                    low[i]=min(low[i], indices[j])
                end
            end
        end
        if low[i]==indices[i]
            part=Int[]
            while true
                j=pop!(stack)
                on[j]=false
                push!(part, j)
                j==i && break
            end
            if length(part)>1||i in sheet.deps[i]
                cyclic[part].=true
            end
        end
    end
    for i=1:2574
        sheet.contents[i]!==nothing&&sheet.contents[i].kind=='='&&indices[i]<0 && visit(i)
    end
    function calculate(i)
        (sheet.contents[i]===nothing||sheet.contents[i].kind!='='||done[i]) && return
        done[i]=true
        if cyclic[i]
            sheet.values[i]=err("#CYCLE!")
            return
        end
        foreach(calculate, sheet.deps[i])
        v=evaluate(sheet, sheet.contents[i].a)
        sheet.values[i]=v===nothing ? num(0) : v.kind=='G' ? err("#VALUE!") : v
    end
    foreach(calculate, 1:2574)
end
function replace_contents!(sheet, next)
    old=sheet.values
    sheet.contents=next
    recalculate!(sheet)
    count(i->notation(old[i])!=notation(sheet.values[i]), 1:2574)
end
describe(sheet, i) = label(i)*": "*notation(sheet.contents[i])*" -> "*notation(sheet.values[i])
format_cells(xs) = isempty(xs) ? "none" : join(label.(sort!(collect(xs))), ",")
function execute!(sheet, line)
    parts=split(line, ' '; limit = 2)
    name=parts[1]
    rest=length(parts)==2 ? parts[2] : ""
    name=="SHOW" && return [describe(sheet, id(address(rest)))]
    if name=="LIST"
        out=[describe(sheet, i) for i=1:2574 if sheet.contents[i]!==nothing]
        return isempty(out) ? ["(no cells)"] : out
    end
    if name=="DEPS"
        i=id(address(rest))
        ds=[j for j=1:2574 if i in sheet.deps[j]]
        return [rest*": precedents="*format_cells(sheet.deps[i])*" dependents="*format_cells(ds)]
    end
    if name=="PRINT"
        g=area(rest)
        rw=length(string(g.b.row+1))
        cs=g.a.n:g.b.n
        rs=g.a.row:g.b.row
        ws=[max(1, maximum(length(display_value(sheet.values[r*26+c+1])) for r in rs)) for c in cs]
        sep="+"*"-"^rw*"+"*join("-"^w*"+" for w in ws)
        head="|"*" "^rw*"|"*join(rpad(string(Char(65+c)), w)*"|" for (c, w) in zip(cs, ws))
        out=[sep, head, sep]
        for r in rs
            row="|"*lpad(string(r+1), rw)*"|"
            for (c, w) in zip(cs, ws)
                v=sheet.values[r*26+c+1]
                row*=(
                    v!==nothing&&v.kind=='N' ? lpad(display_value(v), w) :
                    rpad(display_value(v), w)
                )*"|"
            end
            push!(out, row)
        end
        push!(out, sep)
        return out
    end
    if name=="UNDO"
        isempty(sheet.history) && throw(ArgumentError("nothing to undo"))
        command, old=pop!(sheet.history)
        return ["UNDO "*command*" changed="*string(replace_contents!(sheet, old))]
    end
    next=copy(sheet.contents)
    target=0
    if name=="SET"
        p=split(rest, ' '; limit = 2)
        target=id(address(p[1]))
        s=p[2]
        if startswith(s, "=")
            next[target]=node('=', 0, "", parse_formula(s))
        elseif occursin(r"\A\"[^\"]*\"\z", s)
            next[target]=text(s[2:(end-1)])
        elseif occursin(r"\A(0|-?[1-9][0-9]{0,8})\z", s)
            next[target]=num(parse(Int, s))
        else
            throw(ArgumentError("bad value"))
        end
    elseif name=="CLEAR"
        next[cells(area(rest))].=nothing
    elseif name in ("COPY", "MOVE")
        p=split(rest, ' '; limit = 2)
        source=area(p[1])
        dest=address(p[2])
        dc=dest.n-source.a.n
        dr=dest.row-source.a.row
        shift(r, relative) = reference(
            r.n+(relative&&r.flags&1!=0 ? 0 : dc),
            r.row+(relative&&r.flags&2!=0 ? 0 : dr),
            r.flags,
        )
        destination=make_range(shift(source.a, false), shift(source.b, false))
        inside(destination.a)&&inside(destination.b) || throw(ArgumentError("out of grid"))
        function transform(x)
            if x.kind=='R'
                if name=="COPY"
                    r=shift(x, true)
                    return inside(r) ? r : INVALID
                end
                return contains_cell(source, x) ? shift(x, false) :
                       contains_cell(destination, x) ? INVALID : x
            end
            name=="MOVE"&&!(contains_cell(source, x.a)&&contains_cell(source, x.b)) && return x
            a=shift(x.a, name=="COPY")
            b=shift(x.b, name=="COPY")
            inside(a)&&inside(b) ? make_range(a, b) : INVALID
        end
        name=="MOVE" && (next=Union{Nothing,Node}[rewrite(x, transform) for x in next])
        ids=cells(source)
        moving=[name=="COPY" ? rewrite(sheet.contents[i], transform) : next[i] for i in ids]
        name=="MOVE" && (next[ids].=nothing)
        for (i, x) in zip(ids, moving)
            next[i+dr*26+dc]=x
        end
    elseif name in ("INSERTROW", "DELETEROW", "INSERTCOL", "DELETECOL")
        row=endswith(name, "ROW")
        insert=startswith(name, "INSERT")
        occursin(row ? r"\A[1-9][0-9]?\z" : r"\A[A-Z]\z", rest) ||
            throw(ArgumentError("bad address"))
        at=row ? parse(Int, rest)-1 : Int(rest[1])-65
        limit=row ? 99 : 26
        axis(x) = row ? x.row : x.n
        change(x, v) = reference(row ? x.n : v, row ? v : x.row, x.flags)
        if insert&&any(
            i->sheet.contents[i]!==nothing&&(row ? div(i-1, 26) : (i-1)%26)==limit-1,
            1:2574,
        )
            throw(ArgumentError("last "*(row ? "row" : "column")*" not empty"))
        end
        function transform_axis(x)
            if x.kind=='R'
                v=axis(x)
                !insert&&v==at && return INVALID
                n=v+(insert ? Int(v>=at) : -Int(v>at))
                return n>=limit ? INVALID : change(x, n)
            end
            a=axis(x.a)
            b=axis(x.b)
            !insert&&a==at&&b==at && return INVALID
            u=a+(insert ? Int(a>=at) : -Int(a>at))
            v=b+(insert ? Int(b>=at) : -Int(b>=at))
            v>=limit ? INVALID : make_range(change(x.a, u), change(x.b, v))
        end
        next=grid()
        for i=1:2574
            sheet.contents[i]===nothing && continue
            r=reference((i-1)%26, div(i-1, 26))
            v=axis(r)
            !insert&&v==at && continue
            t=change(r, v+(insert ? Int(v>=at) : -Int(v>at)))
            next[id(t)]=rewrite(sheet.contents[i], transform_axis)
        end
    else
        throw(ArgumentError("unknown command"))
    end
    push!(sheet.history, (String(name), sheet.contents))
    changed=replace_contents!(sheet, next)
    [
        name*(name=="SET" ? " "*label(target)*"="*notation(sheet.values[target]) : "")*" changed="*string(
            changed,
        ),
    ]
end
function main()
    n=parse(Int, readline())
    sheet=Sheet()
    for _=1:n
        line=readline()
        try
            foreach(println, execute!(sheet, line))
        catch e
            e isa ArgumentError || rethrow()
            println("ERROR ", e.msg)
        end
    end
end
main()
