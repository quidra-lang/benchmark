const LETTERS="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
const DIGITS="0123456789"
struct CommandError <: Exception
    message::String
end
struct JsonError <: Exception
    reason::String
    position::Int
end
fail(s) = throw(CommandError(s))
require(b, s = "bad arguments") = b ? nothing : fail(s)
part(s, a, b = length(s)) = a>b ? "" : String(s[a:b])
identifier(s) =
    !isempty(s) &&
    (s[1] in LETTERS || s[1]=='_') &&
    all(c->c in LETTERS || c in DIGITS || c=='_', s)
function integerword(s)
    s=="0" && return true
    digits=startswith(s, "-") ? part(s, 2) : s
    1<=length(digits)<=9 && digits[1]!='0' && all(c->c in DIGITS, digits)
end
function hexvalue(s)
    length(s)==4 && all(c->c in "0123456789abcdefABCDEF", s) || return -1
    parse(Int, s; base = 16)
end
function quoted(s, mark = '"')
    io=IOBuffer()
    print(io, mark)
    escapes=Dict('\\'=>"\\\\", '\b'=>"\\b", '\f'=>"\\f", '\n'=>"\\n", '\r'=>"\\r", '\t'=>"\\t")
    for c in s
        if c==mark
            print(io, '\\', c)
        elseif haskey(escapes, c)
            print(io, escapes[c])
        elseif Int(c)<32 || Int(c)==127
            print(io, "\\u", lpad(string(Int(c); base = 16), 4, '0'))
        else
            print(io, c)
        end
    end
    print(io, mark)
    String(take!(io))
end
mutable struct Value
    kind::String
    scalar::Any
    keys::Vector{String}
    items::Vector{Value}
end
Value(kind, scalar = nothing) = Value(kind, scalar, String[], Value[])
findkey(v, k) = something(findfirst(==(k), v.keys), 0)
valuecount(v) = 1+sum(valuecount, v.items; init = 0)
valuedepth(v) = 1+maximum(valuedepth.(v.items); init = 0)
function compact(v)
    v.kind=="null" && return "null"
    v.kind=="boolean" && return v.scalar ? "true" : "false"
    v.kind=="number" && return string(v.scalar)
    v.kind=="string" && return quoted(v.scalar)
    v.kind=="array" && return "["*join(compact.(v.items), ",")*"]"
    "{"*join([quoted(k)*":"*compact(x) for (k, x) in zip(v.keys, v.items)], ",")*"}"
end
function pretty(v, indent = "")
    isempty(v.items) && return compact(v)
    inner=indent*"  "
    rows=[
        inner*(v.kind=="object" ? quoted(v.keys[i])*": " : "")*pretty(x, inner) for
        (i, x) in enumerate(v.items)
    ]
    (v.kind=="object" ? "{" : "[")*"\n"*join(rows, ",\n")*"\n"*indent*(v.kind=="object" ? "}" : "]")
end
function equalvalue(a, b)
    a.kind==b.kind || return false
    if a.kind=="array"
        return length(a.items)==length(b.items) &&
               all(equalvalue(x, y) for (x, y) in zip(a.items, b.items))
    end
    if a.kind=="object"
        length(a.items)==length(b.items) || return false
        for (k, x) in zip(a.keys, a.items)
            j=findkey(b, k)
            (j!=0 && equalvalue(x, b.items[j])) || return false
        end
        return true
    end
    a.scalar==b.scalar
end
mutable struct JsonReader
    text::String
    at::Int
end
JsonReader(s) = JsonReader(s, 1)
current(p) = p.at<=length(p.text) ? p.text[p.at] : '\0'
jsonfail(p, s, at = p.at) = throw(JsonError(s, at))
function whitespace!(p)
    while current(p) in (' ', '\n')
        p.at+=1
    end
end
function expect!(p, c, message)
    current(p)=='\0' && jsonfail(p, "unexpected end of input")
    current(p)==c || jsonfail(p, message)
end
function readstring!(p)
    p.at+=1
    result=IOBuffer()
    escapes=Dict(
        '"'=>'"',
        '\\'=>'\\',
        '/'=>'/',
        'b'=>'\b',
        'f'=>'\f',
        'n'=>'\n',
        'r'=>'\r',
        't'=>'\t',
    )
    while true
        c=current(p)
        c in ('\0', '\n') && jsonfail(p, "unterminated string")
        p.at+=1
        c=='"' && return String(take!(result))
        if c=='\\'
            start=p.at-1
            e=current(p)
            e in ('\0', '\n') && jsonfail(p, "unterminated string")
            if e=='u'
                n=p.at+4<=length(p.text) ? hexvalue(part(p.text, p.at+1, p.at+4)) : -1
                n<0 && jsonfail(p, "bad unicode escape", start)
                n>127 && jsonfail(p, "non-ascii escape", start)
                print(result, Char(n))
                p.at+=5
            else
                haskey(escapes, e) || jsonfail(p, "invalid escape '\\$e'", start)
                print(result, escapes[e])
                p.at+=1
            end
        else
            print(result, c)
        end
    end
end
function readnumber!(p)
    start=p.at
    negative=current(p)=='-'
    negative && (p.at+=1)
    first=p.at
    while current(p) in DIGITS
        p.at+=1
    end
    digits=part(p.text, first, p.at-1)
    isempty(digits) && jsonfail(p, "invalid number", start)
    length(digits)>=2 && digits[1]=='0' && jsonfail(p, "leading zero", first)
    current(p)=='.' && jsonfail(p, "fraction not allowed")
    current(p) in ('e', 'E') && jsonfail(p, "exponent not allowed")
    length(digits)>=10 && jsonfail(p, "number out of range", start)
    Value("number", parse(Int, digits)*(negative ? -1 : 1))
end
function readvalue!(p)
    whitespace!(p)
    c=current(p)
    c=='\0' && jsonfail(p, "unexpected end of input")
    c=='"' && return Value("string", readstring!(p))
    (c=='-' || c in DIGITS) && return readnumber!(p)
    if c in LETTERS
        start=p.at
        while current(p) in LETTERS
            p.at+=1
        end
        word=part(p.text, start, p.at-1)
        word=="true" && return Value("boolean", true)
        word=="false" && return Value("boolean", false)
        word=="null" && return Value("null")
        jsonfail(p, "invalid literal '$word'", start)
    end
    c in ('{', '[') || jsonfail(p, "unexpected character '$c'")
    object=c=='{'
    closing=object ? '}' : ']'
    v=Value(object ? "object" : "array")
    p.at+=1
    whitespace!(p)
    if current(p)==closing
        p.at+=1
        return v
    end
    while true
        if object
            whitespace!(p)
            expect!(p, '"', "expected key")
            start=p.at
            key=readstring!(p)
            findkey(v, key)==0 || jsonfail(p, "duplicate key "*quoted(key), start)
            whitespace!(p)
            expect!(p, ':', "expected ':'")
            p.at+=1
            push!(v.keys, key)
        end
        push!(v.items, readvalue!(p))
        whitespace!(p)
        if current(p)==closing
            p.at+=1
            return v
        end
        expect!(p, ',', object ? "expected ',' or '}'" : "expected ',' or ']'")
        p.at+=1
        whitespace!(p)
        current(p)==closing && jsonfail(p, "trailing comma")
    end
end
function parsejson(s)
    p=JsonReader(s)
    v=readvalue!(p)
    whitespace!(p)
    p.at<=length(s) && jsonfail(p, "trailing characters")
    v
end
struct Segment
    kind::String
    key::String
    index::Int
    start::Union{Nothing,Int}
    stop::Union{Nothing,Int}
    descendant::Bool
end
Segment(kind; key = "", index = 0, start = nothing, stop = nothing, descendant = false) =
    Segment(kind, key, index, start, stop, descendant)
mutable struct PathReader
    text::String
    at::Int
    message::String
end
pathcurrent(p) = p.at<=length(p.text) ? p.text[p.at] : '\0'
function acceptpath!(p, c)
    pathcurrent(p)==c || return false
    p.at+=1
    true
end
expectpath!(p, c) = acceptpath!(p, c) ? nothing : fail(p.message)
function readidentifier!(p)
    start=p.at
    c=pathcurrent(p)
    (c in LETTERS || c=='_') || fail(p.message)
    while (c=pathcurrent(p)) in LETTERS || c in DIGITS || c=='_'
        p.at+=1
    end
    part(p.text, start, p.at-1)
end
function readkey!(p)
    expectpath!(p, '\'')
    io=IOBuffer()
    escapes=Dict(
        '\''=>'\'',
        '\\'=>'\\',
        '/'=>'/',
        'b'=>'\b',
        'f'=>'\f',
        'n'=>'\n',
        'r'=>'\r',
        't'=>'\t',
    )
    while true
        c=pathcurrent(p)
        c=='\0' && fail(p.message)
        p.at+=1
        c=='\'' && return String(take!(io))
        if c=='\\'
            e=pathcurrent(p)
            p.at+=1
            if e=='u'
                n=p.at+3<=length(p.text) ? hexvalue(part(p.text, p.at, p.at+3)) : -1
                0<=n<=127 || fail(p.message)
                print(io, Char(n))
                p.at+=4
            else
                haskey(escapes, e) || fail(p.message)
                print(io, escapes[e])
            end
        else
            print(io, c)
        end
    end
end
function selection!(p, descendant = false)
    if pathcurrent(p)=='\''
        key=readkey!(p)
        expectpath!(p, ']')
        return Segment("key"; key, descendant)
    end
    start=p.at
    while !(pathcurrent(p) in (']', '\0'))
        p.at+=1
    end
    expectpath!(p, ']')
    content=part(p.text, start, p.at-2)
    content=="*" && return Segment("all"; descendant)
    integerword(content) && return Segment("index"; index = parse(Int, content), descendant)
    parts=split(content, ':'; keepempty = true)
    length(parts)==2 && all(x->isempty(x) || integerword(x), parts) || fail(p.message)
    Segment(
        "slice";
        start = isempty(parts[1]) ? nothing : parse(Int, parts[1]),
        stop = isempty(parts[2]) ? nothing : parse(Int, parts[2]),
        descendant,
    )
end
function parsepath(s, field = false)
    p=PathReader(s, 1, field ? "bad field" : "bad path")
    expectpath!(p, field ? '@' : '$')
    result=Segment[]
    while p.at<=length(s)
        if acceptpath!(p, '[')
            segment=selection!(p)
            field && !(segment.kind in ("key", "index")) && fail(p.message)
        else
            expectpath!(p, '.')
            descendant=!field && acceptpath!(p, '.')
            if !field && acceptpath!(p, '*')
                segment=Segment("all"; descendant)
            elseif descendant && acceptpath!(p, '[')
                segment=selection!(p, true)
            else
                segment=Segment("key"; key = readidentifier!(p), descendant)
            end
        end
        push!(result, segment)
    end
    result
end
function parsekey(s)
    p=PathReader(s, 1, "bad key")
    key=pathcurrent(p)=='\'' ? readkey!(p) : readidentifier!(p)
    p.at>length(s) || fail(p.message)
    key
end
struct Step
    key::Union{Nothing,String}
    position::Int
end
struct Match
    value::Value
    steps::Vector{Step}
end
function child(m, i)
    Match(
        m.value.items[i],
        [m.steps; [Step(m.value.kind=="object" ? m.value.keys[i] : nothing, i)]],
    )
end
function location(m)
    "\$"*join(
        s.key===nothing ? "[$(s.position-1)]" :
        identifier(s.key) ? "."*s.key : "["*quoted(s.key, '\'')*"]" for s in m.steps
    )
end
function preorder(m)
    result=[m]
    for i in eachindex(m.value.items)
        append!(result, preorder(child(m, i)))
    end
    result
end
function childposition(v, s)
    s.kind=="key" && return v.kind=="object" ? findkey(v, s.key) : 0
    v.kind=="array" || return 0
    i=s.index<0 ? length(v.items)+s.index+1 : s.index+1
    1<=i<=length(v.items) ? i : 0
end
clampbound(b, n) = clamp(b<0 ? n+b : b, 0, n)
function applysegment(s, matches)
    result=Match[]
    for m in matches, source in (s.descendant ? preorder(m) : [m])
        v=source.value
        positions=Int[]
        if s.kind=="all"
            positions=collect(eachindex(v.items))
        elseif s.kind=="slice" && v.kind=="array"
            n=length(v.items)
            a=s.start===nothing ? 0 : clampbound(s.start, n)
            b=s.stop===nothing ? n : clampbound(s.stop, n)
            positions=collect((a+1):b)
        elseif s.kind in ("key", "index")
            p=childposition(v, s)
            p!=0 && push!(positions, p)
        end
        for p in positions
            push!(result, child(source, p))
        end
    end
    result
end
function evaluate(root, segments)
    matches=[Match(root, Step[])]
    for s in segments
        matches=applysegment(s, matches)
    end
    matches
end
function fieldvalue(v, segments)
    for s in segments
        p=childposition(v, s)
        p==0 && return nothing
        v=v.items[p]
    end
    v
end
function filterholds(op, v, r)
    op=="EXISTS" && return v!==nothing
    if op in ("==", "!=")
        same=v!==nothing && equalvalue(v, r)
        return op=="==" ? same : !same
    end
    v!==nothing && v.kind==r.kind && v.kind in ("number", "string") || return false
    op=="<" ? v.scalar<r.scalar :
    op=="<=" ? v.scalar<=r.scalar : op==">" ? v.scalar>r.scalar : v.scalar>=r.scalar
end
sortkey(v) =
    v===nothing ? (3, 0) :
    v.kind=="null" ? (0, 0) :
    v.kind=="number" ? (1, v.scalar) : v.kind=="string" ? (2, v.scalar) : (3, 0)
function requirekind(matches, kind, message)
    for m in matches
        require(m.value.kind==kind, message*" at "*location(m))
    end
end
function targets(matches)
    result=sort(matches; by = m->Tuple(s.position for s in m.steps), rev = true)
    seen=Set{Tuple}()
    out=Match[]
    for m in result
        p=Tuple(s.position for s in m.steps)
        p in seen && continue
        push!(seen, p)
        push!(out, m)
    end
    out
end
function resolve(root, steps)
    for s in steps
        root=root.items[s.position]
    end
    root
end
function deepmerge!(target, patch)
    for (k, x) in zip(patch.keys, patch.items)
        p=findkey(target, k)
        if p==0
            push!(target.keys, k)
            push!(target.items, deepcopy(x))
        elseif target.items[p].kind=="object" && x.kind=="object"
            deepmerge!(target.items[p], x)
        else
            target.items[p]=deepcopy(x)
        end
    end
end
mutable struct QueryTool
    document::Value
    history::Vector{Value}
end
QueryTool() = QueryTool(Value("null"), Value[])
function commit!(t, v)
    push!(t.history, t.document)
    t.document=v
end
function load!(t, lines)
    text=join(lines, "\n")
    try
        v=parsejson(text)
        commit!(t, v)
        println("LOADED nodes=$(valuecount(v)) depth=$(valuedepth(v))")
    catch e
        e isa JsonError || rethrow()
        before=part(text, 1, e.position-1)
        line=count(==('\n'), before)+1
        last=something(findlast('\n', before), 0)
        println("PARSE ERROR line $line col $(e.position-last): $(e.reason)")
    end
end
function arguments(s, n)
    result=s===nothing ? String[] : String.(split(s, ' '; limit = n, keepempty = true))
    require(length(result)==n)
    result
end
function words(s, minimum, maximum)
    result=s===nothing ? String[] : String.(split(s, ' '; keepempty = true))
    require(minimum<=length(result)<=maximum)
    result
end
function execute!(t, line)
    at=findfirst(' ', line)
    command=at===nothing ? line : part(line, 1, at-1)
    arg=at===nothing ? nothing : part(line, at+1)
    known=(
        "GET",
        "COMPACT",
        "PRETTY",
        "TYPE",
        "LENGTH",
        "KEYS",
        "FLATTEN",
        "COUNT",
        "SUM",
        "MIN",
        "MAX",
        "AVG",
        "FILTER",
        "SET",
        "DELETE",
        "INSERT",
        "MERGE",
        "SORT",
        "RENAME",
        "UNDO",
    )
    command in known || fail("unknown command '$command'")
    if command=="UNDO"
        words(arg, 0, 0)
        require(!isempty(t.history), "nothing to undo")
        t.document=pop!(t.history)
        println("UNDO $(length(t.history))")
        return
    end
    field=Segment[]
    op=""
    value=Value("null")
    index=0
    key=""
    descending=false
    if command in ("SET", "MERGE")
        args=arguments(arg, 2)
        path=parsepath(args[1])
        value=parsejson(args[2])
        command=="MERGE" && require(value.kind=="object", "merge value is not an object")
    elseif command=="INSERT"
        args=arguments(arg, 3)
        path=parsepath(args[1])
        require(integerword(args[2]), "bad index")
        index=parse(Int, args[2])
        value=parsejson(args[3])
    elseif command=="FILTER"
        args=arg===nothing ? String[] : String.(split(arg, ' '; limit = 4, keepempty = true))
        require(length(args)>=3 && ((length(args)==4)!=(args[3]=="EXISTS")))
        path=parsepath(args[1])
        field=parsepath(args[2], true)
        op=args[3]
        require(op in ("==", "!=", "<", "<=", ">", ">=", "EXISTS"), "bad operator")
        length(args)==4 && (value=parsejson(args[4]))
    elseif command=="SORT"
        args=words(arg, 1, 3)
        options=args[2:end]
        descending=!isempty(options) && options[end]=="DESC"
        descending && pop!(options)
        require(length(options)<=1 && !("DESC" in options))
        path=parsepath(args[1])
        field=parsepath(isempty(options) ? "@" : options[1], true)
    elseif command=="RENAME"
        args=words(arg, 2, 2)
        path=parsepath(args[1])
        key=parsekey(args[2])
    else
        optional=command in ("COMPACT", "PRETTY", "FLATTEN")
        args=words(arg, optional ? 0 : 1, 1)
        path=parsepath(isempty(args) ? "\$" : args[1])
    end
    command=="DELETE" && require(!isempty(path), "cannot delete root")
    matches=evaluate(t.document, path)
    if command=="LENGTH"
        for m in matches
            require(m.value.kind in ("array", "object", "string"), "no length at "*location(m))
        end
    elseif command in ("KEYS", "MERGE")
        requirekind(matches, "object", "not an object")
    elseif command in ("FILTER", "INSERT", "SORT")
        requirekind(matches, "array", "not an array")
    end
    if command=="INSERT"
        for m in matches
            n=length(m.value.items)
            require(-n-1<=index<=n, "index out of range at "*location(m))
        end
    elseif command=="RENAME"
        for m in matches
            require(!isempty(m.steps) && m.steps[end].key!==nothing, "not a member at "*location(m))
        end
    end
    if command=="COUNT"
        println("COUNT $(length(matches))")
        return
    end
    if command in ("SUM", "MIN", "MAX", "AVG")
        numbers=[m.value.scalar for m in matches if m.value.kind=="number"]
        total=sum(numbers; init = 0)
        text=command=="SUM" ? string(total) :
             isempty(numbers) ? "null" :
             command=="MIN" ? string(minimum(numbers)) :
             command=="MAX" ? string(maximum(numbers)) : ""
        if command=="AVG" && !isempty(numbers)
            n=length(numbers)
            q=div(abs(total)*200+n, 2n)
            text=(total<0 && q>0 ? "-" : "")*string(div(q, 100))*"."*lpad(string(q%100), 2, '0')
        end
        println(command, " ", text)
        return
    end
    if command=="FILTER"
        found=false
        for m in matches, i in eachindex(m.value.items)
            x=child(m, i)
            if filterholds(op, fieldvalue(x.value, field), value)
                println(location(x), " = ", compact(x.value))
                found=true
            end
        end
        !found && println("no match")
        return
    end
    if command in ("SET", "DELETE", "INSERT", "MERGE", "SORT", "RENAME")
        selected=matches
        if command=="SET" && !isempty(path)
            selected=Match[]
            last=path[end]
            for m in evaluate(t.document, path[1:(end-1)])
                if last.kind=="key" && !last.descendant && m.value.kind=="object"
                    p=findkey(m.value, last.key)
                    p==0 && (p=length(m.value.items)+1)
                    push!(selected, Match(value, [m.steps; [Step(last.key, p)]]))
                else
                    append!(selected, applysegment(last, [m]))
                end
            end
        end
        selected=targets(selected)
        document=deepcopy(t.document)
        for m in selected
            if command=="SET"
                if isempty(m.steps)
                    document=deepcopy(value)
                else
                    parent=resolve(document, m.steps[1:(end-1)])
                    p=m.steps[end].position
                    if p>length(parent.items)
                        push!(parent.keys, m.steps[end].key)
                        push!(parent.items, deepcopy(value))
                    else
                        parent.items[p]=deepcopy(value)
                    end
                end
            elseif command=="DELETE"
                parent=resolve(document, m.steps[1:(end-1)])
                p=m.steps[end].position
                deleteat!(parent.items, p)
                parent.kind=="object" && deleteat!(parent.keys, p)
            elseif command=="INSERT"
                array=resolve(document, m.steps)
                p=index<0 ? length(array.items)+2+index : index+1
                insert!(array.items, p, deepcopy(value))
            elseif command=="MERGE"
                deepmerge!(resolve(document, m.steps), value)
            elseif command=="SORT"
                sort!(
                    resolve(document, m.steps).items;
                    by = x->sortkey(fieldvalue(x, field)),
                    rev = descending,
                    alg = Base.Sort.MergeSort,
                )
            else
                parent=resolve(document, m.steps[1:(end-1)])
                p=m.steps[end].position
                require(
                    parent.keys[p]==key || findkey(parent, key)==0,
                    "key exists at "*location(m),
                )
                parent.keys[p]=key
            end
        end
        commit!(t, document)
        println(command, " ", length(selected))
        return
    end
    isempty(matches) && println("no match")
    for m in matches
        v=m.value
        if command=="GET"
            println(location(m), " = ", compact(v))
        elseif command=="COMPACT"
            println(compact(v))
        elseif command=="PRETTY"
            println(pretty(v))
        elseif command=="TYPE"
            println(location(m), " ", v.kind)
        elseif command=="LENGTH"
            println(location(m), " ", v.kind=="string" ? length(v.scalar) : length(v.items))
        elseif command=="KEYS"
            println(location(m), " [", join(quoted.(v.keys), ","), "]")
        elseif command=="FLATTEN"
            for leaf in preorder(m)
                isempty(leaf.value.items) && println(location(leaf), " = ", compact(leaf.value))
            end
        end
    end
end
function main()
    lines=readlines()
    t=QueryTool()
    at=1
    function block!()
        start=at
        while at<=length(lines) && lines[at]!="%%"
            at+=1
        end
        load!(t, lines[start:(at-1)])
        at+=1
    end
    block!()
    while at<=length(lines) && lines[at]!="END"
        line=lines[at]
        at+=1
        if line=="LOAD"
            block!()
            continue
        end
        try
            execute!(t, line)
        catch e
            if e isa CommandError
                println("ERROR $(e.message)")
            elseif e isa JsonError
                println("PARSE ERROR col $(e.position): $(e.reason)")
            else
                rethrow()
            end
        end
    end
end
main()
