struct SyntaxFault <: Exception end
struct BasicFault <: Exception
    message::String
end

const SIGNATURES = Dict(
    "ABS"=>["I"], "SGN"=>["I"], "INT"=>["I"], "SQR"=>["I"], "RND"=>["I"],
    "LEN"=>["S"], "ASC"=>["S"], "VAL"=>["S"], "CHR\$"=>["I"], "STR\$"=>["I"],
    "LEFT\$"=>["SI"], "RIGHT\$"=>["SI"], "MID\$"=>["SI","SII"], "INSTR"=>["SS"]
)

const ERROR_CODES = Dict(
    "NEXT WITHOUT FOR"=>1, "RETURN WITHOUT GOSUB"=>3, "OUT OF DATA"=>4,
    "ILLEGAL FUNCTION CALL"=>5, "OVERFLOW"=>6, "OUT OF MEMORY"=>7,
    "UNDEFINED LINE NUMBER"=>8, "SUBSCRIPT OUT OF RANGE"=>9,
    "DUPLICATE DEFINITION"=>10, "DIVISION BY ZERO"=>11, "TYPE MISMATCH"=>13,
    "STRING TOO LONG"=>15, "RESUME WITHOUT ERROR"=>20,
    "FOR WITHOUT NEXT"=>26, "WHILE WITHOUT WEND"=>29,
    "WEND WITHOUT WHILE"=>30, "INPUT PAST END"=>62
)

const OPERATORS = [
    Set(["OR"]), Set(["AND"]), Set{String}(),
    Set(["=", "<>", "<", ">", "<=", ">="]),
    Set(["+", "-"]), Set(["*", "/", "MOD"]),
    Set{String}(), Set(["^"])
]

fault(message) = throw(BasicFault(message))
syntax() = throw(SyntaxFault())

function variable_name(name::String)
    letters = collect(name)
    if !isempty(letters) && letters[end] == '$'
        pop!(letters)
    end
    length(letters) in (1,2) || return false
    'A' <= letters[1] <= 'Z' || return false
    return length(letters) == 1 || '0' <= letters[2] <= '9'
end

name_type(name::String) = endswith(name, "\$") ? "S" : "I"
value_type(value) = value isa AbstractString ? "S" : "I"

mutable struct Expr
    kind::Symbol
    typ::String
    value::Any
    args::Vector{Expr}
end

expr(kind, typ, value, args=Expr[]) = Expr(kind, typ, value, args)

mutable struct Stmt
    kind::String
    line::Int
    next::Union{Nothing, Stmt}
    expr::Union{Nothing, Expr}
    target::Union{Nothing, Expr}
    targets::Vector{Expr}
    expressions::Vector{Expr}
    values::Vector{Any}
    numbers::Vector{Int}
    name::String
    mode::String
    clauses::Vector{Any}
    items::Vector{Any}
end

Stmt(kind::String) = Stmt(
    kind, 0, nothing, nothing, nothing, Expr[], Expr[], Any[], Int[],
    "", "", Any[], Any[]
)

function tokenize(text::String)
    bytes = Vector{UInt8}(codeunits(text))
    tokens = Any[]
    p = 1
    while p <= length(bytes)
        ch = Char(bytes[p])
        if ch == ' '
            p += 1
        elseif ch == '"'
            q = findnext(==('"'), Char.(bytes), p + 1)
            q === nothing && syntax()
            value = String(bytes[p+1:q-1])
            push!(tokens, (;kind="S",text=String(bytes[p:q]),value))
            p = q + 1
        elseif '0' <= ch <= '9'
            start = p
            while p <= length(bytes) && '0' <= Char(bytes[p]) <= '9'
                p += 1
            end
            word = String(bytes[start:p-1])
            number = tryparse(Int, word)
            (number === nothing || number > 32767) && syntax()
            push!(tokens, (;kind="I",text=word,value=number))
        elseif 'A' <= ch <= 'Z'
            if p + 2 <= length(bytes) && String(bytes[p:p+2]) == "REM"
                push!(tokens, (;kind="W",text="REM",value="REM"))
                break
            end
            start = p
            while p <= length(bytes) && (
                'A' <= Char(bytes[p]) <= 'Z' || '0' <= Char(bytes[p]) <= '9'
            )
                p += 1
            end
            if p <= length(bytes) && Char(bytes[p]) == '$'
                p += 1
            end
            word = String(bytes[start:p-1])
            push!(tokens, (;kind="W",text=word,value=word))
        else
            ch in "+-*/^=<>() ,;:" || syntax()
            word = string(ch)
            if p < length(bytes)
                pair = String(bytes[p:p+1])
                if pair in ("<>", "<=", ">=")
                    word = pair
                end
            end
            push!(tokens, (;kind="P",text=word,value=word))
            p += ncodeunits(word)
        end
    end
    push!(tokens, (;kind="E",text="",value=""))
    tokens
end

mutable struct Parser
    tokens::Vector{Any}
    pos::Int
end

Parser(tokens::Vector{Any}) = Parser(tokens, 1)
current(p::Parser) = p.tokens[p.pos]
at(p::Parser, word::String) = current(p).kind in ("P", "W") && current(p).text == word

function take!(p::Parser, word::String)
    at(p, word) || return false
    p.pos += 1
    true
end

function expect!(p::Parser, word::String)
    take!(p,word) || syntax()
end

function number!(p::Parser)
    token = current(p)
    token.kind == "I" || syntax()
    p.pos += 1
    token.value
end

function integer!(p::Parser)
    result = expression!(p)
    result.typ == "I" || syntax()
    result
end

function integer_at!(p::Parser, level)
    result = expression!(p, level)
    result.typ == "I" || syntax()
    result
end

function target!(p::Parser)
    token = current(p)
    token.kind == "W" && variable_name(token.text) || syntax()
    p.pos += 1
    args = Expr[]
    if take!(p, "(")
        push!(args, integer!(p))
        if take!(p, ",")
            push!(args, integer!(p))
        end
        expect!(p, ")")
    end
    expr(isempty(args) ? :variable : :array, name_type(token.text), token.text, args)
end

function primary!(p::Parser)
    token = current(p)
    if token.kind in ("I", "S")
        p.pos += 1
        return expr(:constant, token.kind, token.value)
    end
    if take!(p, "(")
        result = expression!(p)
        expect!(p, ")")
        return result
    end
    if token.kind == "W" && variable_name(token.text)
        return target!(p)
    end
    if take!(p, "ERR")
        return expr(:builtin, "I", "ERR")
    end
    if take!(p, "ERL")
        return expr(:builtin, "I", "ERL")
    end
    if token.kind == "W" && haskey(SIGNATURES, token.text)
        p.pos += 1
        expect!(p, "(")
        args = Expr[expression!(p)]
        while take!(p, ",")
            push!(args, expression!(p))
        end
        expect!(p, ")")
        join(e.typ for e in args) in SIGNATURES[token.text] || syntax()
        return expr(:call, name_type(token.text), token.text, args)
    end
    syntax()
end

function expression!(p::Parser, level::Int=0)
    if level == 2 && take!(p, "NOT")
        return expr(:unary, "I", "NOT", Expr[integer_at!(p, 2)])
    end
    if level == 6 && take!(p, "-")
        return expr(:unary, "I", "-", Expr[integer_at!(p, 6)])
    end
    level == 8 && return primary!(p)
    left = expression!(p, level + 1)
    while current(p).text in OPERATORS[level + 1]
        op = current(p).text
        p.pos += 1
        right = expression!(p, level == 7 ? 6 : level + 1)
        if left.typ != right.typ || (left.typ == "S" && level != 3 && op != "+")
            syntax()
        end
        left = expr(:binary, level == 3 ? "I" : left.typ, op, Expr[left,right])
        level == 7 && break
    end
    left
end

function clause!(p::Parser)
    if current(p).kind == "I"
        return (;line=number!(p),body=Stmt[])
    end
    (;line=nothing,body=listing!(p,true))
end

function listing!(p::Parser, in_clause::Bool=false)
    statements = Stmt[statement!(p,in_clause)]
    while take!(p, ":")
        push!(statements, statement!(p,in_clause))
    end
    statements
end

function statement!(p::Parser, in_clause::Bool)
    word = current(p).text
    if in_clause && word in ("IF","FOR","NEXT","WHILE","WEND","DATA")
        syntax()
    end
    s = Stmt(word)
    if any(take!(p, name) for name in ("REM","RETURN","WEND","END","STOP"))
        return s
    end
    if take!(p, "PRINT")
        expression_last = false
        while current(p).kind != "E" && !at(p, ":") && !at(p, "ELSE")
            if take!(p, ";")
                push!(s.items, (;kind=";",node=nothing))
                expression_last = false
            elseif take!(p, ",")
                push!(s.items, (;kind=",",node=nothing))
                expression_last = false
            else
                kind = at(p, "TAB") ? "TAB" : at(p, "SPC") ? "SPC" : "value"
                kind == "value" && expression_last && syntax()
                if kind == "value"
                    e = expression!(p)
                else
                    p.pos += 1
                    expect!(p, "(")
                    e = integer!(p)
                    expect!(p, ")")
                end
                push!(s.items, (;kind,node=e))
                expression_last = kind == "value"
            end
        end
        return s
    end
    if take!(p, "INPUT") || take!(p, "READ") || take!(p, "DIM")
        while true
            t = target!(p)
            word == "DIM" && t.kind != :array && syntax()
            push!(s.targets,t)
            take!(p, ",") || break
        end
        return s
    end
    if take!(p, "DATA")
        while true
            negative = take!(p, "-")
            token = current(p)
            if token.kind != "I" && (token.kind != "S" || negative)
                syntax()
            end
            p.pos += 1
            push!(s.values, negative ? -token.value : token.value)
            take!(p, ",") || break
        end
        return s
    end
    if take!(p, "IF")
        s.expr = integer!(p)
        expect!(p, "THEN")
        push!(s.clauses,clause!(p))
        if take!(p, "ELSE")
            push!(s.clauses,clause!(p))
        end
        current(p).kind == "E" || syntax()
        return s
    end
    if take!(p, "GOTO") || take!(p, "GOSUB")
        push!(s.numbers,number!(p))
        return s
    end
    if take!(p, "ON")
        if take!(p, "ERROR")
            s.kind = "handler"
            expect!(p, "GOTO")
            push!(s.numbers,number!(p))
        else
            s.expr = integer!(p)
            if take!(p, "GOTO")
                s.mode = "GOTO"
            else
                expect!(p, "GOSUB")
                s.mode = "GOSUB"
            end
            push!(s.numbers,number!(p))
            while take!(p, ",")
                push!(s.numbers,number!(p))
            end
        end
        return s
    end
    if take!(p, "RESUME")
        if take!(p, "NEXT")
            s.mode = "NEXT"
        elseif current(p).kind == "I"
            s.mode = "line"
            push!(s.numbers,number!(p))
        end
        return s
    end
    if take!(p, "FOR")
        token = current(p)
        token.kind == "W" && variable_name(token.text) &&
            name_type(token.text) == "I" || syntax()
        s.name = token.text
        p.pos += 1
        expect!(p, "=")
        push!(s.expressions,integer!(p))
        expect!(p, "TO")
        push!(s.expressions,integer!(p))
        push!(s.expressions,take!(p,"STEP") ? integer!(p) : expr(:constant,"I",1))
        return s
    end
    if take!(p, "NEXT")
        token = current(p)
        if token.kind == "W" && variable_name(token.text) && name_type(token.text) == "I"
            s.name = token.text
            p.pos += 1
        end
        return s
    end
    if take!(p, "WHILE") || take!(p, "RANDOMIZE")
        s.expr = integer!(p)
        return s
    end
    if take!(p, "RESTORE")
        if current(p).kind == "I"
            push!(s.numbers,number!(p))
        end
        return s
    end
    take!(p, "LET")
    s.kind = "assign"
    s.target = target!(p)
    expect!(p, "=")
    s.expr = expression!(p)
    s.expr.typ == s.target.typ || syntax()
    s
end

function parse_program(p::Parser)
    result = listing!(p)
    current(p).kind == "E" || syntax()
    result
end

mutable struct BasicArray
    bounds::Vector{Int}
    values::Vector{Any}
end

mutable struct Machine
    inputs::Vector{String}
    variables::Dict{String,Any}
    arrays::Dict{String,BasicArray}
    stack::Vector{Any}
    entries::Dict{Int,Stmt}
    sequence::Vector{Stmt}
    data::Vector{Any}
    data_position::Int
    input_position::Int
    random::Int
    handler::Int
    handling::Bool
    remembered::Union{Nothing,Stmt}
    err::Int
    erl::Int
    buffer::String
    output::Vector{String}
end

Machine(inputs::Vector{String}) = Machine(
    inputs, Dict{String,Any}(), Dict{String,BasicArray}(), Any[],
    Dict{Int,Stmt}(), Stmt[], Any[], 1, 1, 1, 0, false,
    nothing, 0, 0, "", String[]
)

function end_line!(m::Machine)
    push!(m.output,rstrip(m.buffer,' '))
    m.buffer = ""
end

function message!(m::Machine, text::String)
    !isempty(m.buffer) && end_line!(m)
    push!(m.output,text)
end

function checked(value)
    (-32768 <= value <= 32767) || fault("OVERFLOW")
    Int(value)
end

get_variable(m::Machine, name::String) =
    get(m.variables,name,name_type(name) == "S" ? "" : 0)

function declare!(m::Machine,name,bounds)
    size = prod(b+1 for b in bounds)
    default = name_type(name) == "S" ? "" : 0
    m.arrays[name] = BasicArray(bounds,Any[default for _ in 1:size])
end

function address(m::Machine,target::Expr)
    name = target.value
    target.kind == :variable && return (;name,index=nothing)
    indices = Int[evaluate(m,e) for e in target.args]
    if !haskey(m.arrays,name)
        declare!(m,name,fill(10,length(indices)))
    end
    arr = m.arrays[name]
    length(indices) == length(arr.bounds) || fault("SUBSCRIPT OUT OF RANGE")
    index = 0
    for (i,v) in enumerate(indices)
        (0 <= v <= arr.bounds[i]) || fault("SUBSCRIPT OUT OF RANGE")
        index = index*(arr.bounds[i]+1)+v
    end
    (;name,index=index+1)
end

function load(m::Machine,addr)
    addr.index === nothing && return get_variable(m,addr.name)
    m.arrays[addr.name].values[addr.index]
end

function store!(m::Machine,addr,value)
    if addr.index === nothing
        m.variables[addr.name] = value
    else
        m.arrays[addr.name].values[addr.index] = value
    end
end

function evaluate(m::Machine,e::Expr)
    op = e.value
    e.kind == :constant && return op
    e.kind in (:variable,:array) && return load(m,address(m,e))
    e.kind == :builtin && return op == "ERR" ? m.err : m.erl
    if e.kind == :unary
        a = evaluate(m,e.args[1])
        return op == "NOT" ? ~a : checked(-a)
    end
    args = [evaluate(m,arg) for arg in e.args]
    e.kind == :call && return call_function(m,op,args)
    a,b = args
    if op in OPERATORS[4]
        result = if op == "="
            a == b
        elseif op == "<>"
            a != b
        elseif op == "<"
            isless(a,b)
        elseif op == ">"
            isless(b,a)
        elseif op == "<="
            !isless(b,a)
        else
            !isless(a,b)
        end
        return result ? -1 : 0
    end
    if e.typ == "S"
        text = a*b
        ncodeunits(text) <= 255 || fault("STRING TOO LONG")
        return text
    end
    if op == "+"
        return checked(a+b)
    elseif op == "-"
        return checked(a-b)
    elseif op == "*"
        return checked(a*b)
    elseif op == "/" || op == "MOD"
        b == 0 && fault("DIVISION BY ZERO")
        return op == "/" ? checked(div(a,b)) : rem(a,b)
    elseif op == "^"
        b < 0 && fault("ILLEGAL FUNCTION CALL")
        abs(a)>1 && b>15 && fault("OVERFLOW")
        total = 1
        for _ in 1:b
            total = checked(total*a)
        end
        return total
    elseif op == "AND"
        return a & b
    elseif op == "OR"
        return a | b
    end
    fault("ILLEGAL FUNCTION CALL")
end

function call_function(m::Machine,name,args)
    a = args[1]
    b = length(args)>1 ? args[2] : nothing
    c = length(args)>2 ? args[3] : nothing
    if name == "ABS"
        return checked(abs(a))
    elseif name == "SGN"
        return sign(a)
    elseif name == "INT"
        return a
    elseif name == "SQR"
        a < 0 && fault("ILLEGAL FUNCTION CALL")
        return isqrt(a)
    elseif name == "RND"
        a < 1 && fault("ILLEGAL FUNCTION CALL")
        m.random = mod(48271*m.random,2147483647)
        return mod(m.random,a)+1
    elseif name == "LEN"
        return ncodeunits(a)
    elseif name == "ASC"
        isempty(a) && fault("ILLEGAL FUNCTION CALL")
        return Int(first(codeunits(a)))
    elseif name == "VAL"
        match_result = match(r"^ *([+-]?[0-9]+)",a)
        match_result === nothing && return 0
        word = match_result.captures[1]
        length(word)>16 && fault("OVERFLOW")
        return checked(parse(Int,word))
    elseif name == "CHR\$"
        (32<=a<=126) || fault("ILLEGAL FUNCTION CALL")
        return string(Char(a))
    elseif name == "STR\$"
        return string(a)
    elseif name == "LEFT\$"
        b<0 && fault("ILLEGAL FUNCTION CALL")
        return String(Vector{UInt8}(codeunits(a)[1:min(b,ncodeunits(a))]))
    elseif name == "RIGHT\$"
        b<0 && fault("ILLEGAL FUNCTION CALL")
        b==0 && return ""
        count = min(b,ncodeunits(a))
        return String(Vector{UInt8}(codeunits(a)[ncodeunits(a)-count+1:end]))
    elseif name == "MID\$"
        (b<1 || (c!==nothing && c<0)) && fault("ILLEGAL FUNCTION CALL")
        b>ncodeunits(a) && return ""
        ending = c===nothing ? ncodeunits(a) : min(ncodeunits(a),b+c-1)
        ending<b && return ""
        return String(Vector{UInt8}(codeunits(a)[b:ending]))
    elseif name == "INSTR"
        isempty(b) && return 1
        index = findfirst(b,a)
        return index===nothing ? 0 : first(index)
    end
    fault("ILLEGAL FUNCTION CALL")
end

function line(m::Machine,number::Int)
    haskey(m.entries,number) || fault("UNDEFINED LINE NUMBER")
    m.entries[number]
end

function push_frame!(m::Machine,frame)
    length(m.stack)==100 && fault("OUT OF MEMORY")
    push!(m.stack,frame)
end

function search_frame(m::Machine,kind::String,name::String="")
    for i in length(m.stack):-1:1
        f = m.stack[i]
        f.kind == "GOSUB" && break
        if f.kind == kind && (isempty(name) || f.name == name)
            return i
        end
    end
    nothing
end

function matching(m::Machine,s::Stmt,opening,closing)
    start = findfirst(x->x===s,m.sequence)
    depth = 0
    for i in start+1:length(m.sequence)
        t = m.sequence[i]
        if t.kind == opening
            depth += 1
        elseif t.kind == closing
            depth==0 && return t.next
            depth -= 1
        end
    end
    fault(opening*" WITHOUT "*closing)
end

function subroutine!(m::Machine,number::Int,after)
    target = line(m,number)
    push_frame!(m,(;kind="GOSUB",position=after,name="",final=0,step=0))
    target
end

function execute!(m::Machine,s::Stmt)
    following = s.next
    if s.kind == "assign"
        place = address(m,s.target)
        store!(m,place,evaluate(m,s.expr))
    elseif s.kind == "PRINT"
        for item in s.items
            if item.kind == ","
                m.buffer *= repeat(" ",10-mod(ncodeunits(m.buffer),10))
            elseif item.kind != ";"
                value = evaluate(m,item.node)
                if item.kind == "value"
                    m.buffer *= string(value)
                else
                    value<0 && fault("ILLEGAL FUNCTION CALL")
                    amount = item.kind == "SPC" ? value : max(0,value-ncodeunits(m.buffer))
                    m.buffer *= repeat(" ",amount)
                end
            end
        end
        if isempty(s.items) || !(s.items[end].kind in (";",","))
            end_line!(m)
        end
    elseif s.kind in ("INPUT","READ")
        for target in s.targets
            place = address(m,target)
            if s.kind == "READ"
                m.data_position>length(m.data) && fault("OUT OF DATA")
                value = m.data[m.data_position].value
                m.data_position += 1
                value_type(value)==target.typ || fault("TYPE MISMATCH")
            else
                while true
                    m.input_position>length(m.inputs) && fault("INPUT PAST END")
                    text = m.inputs[m.input_position]
                    m.input_position += 1
                    if target.typ=="S"
                        value = text
                        break
                    end
                    match_result = match(r"^-[0-9]+$|^[0-9]+$",text)
                    number = match_result===nothing ? nothing : tryparse(Int,text)
                    if number!==nothing && -32768<=number<=32767
                        value = number
                        break
                    end
                    message!(m,"?REDO FROM START")
                end
            end
            store!(m,place,value)
        end
    elseif s.kind == "RESTORE"
        if isempty(s.numbers)
            m.data_position = 1
        else
            number = s.numbers[1]
            line(m,number)
            m.data_position = length(m.data)+1
            for (i,d) in enumerate(m.data)
                if d.line>=number
                    m.data_position = i
                    break
                end
            end
        end
    elseif s.kind == "IF"
        index = evaluate(m,s.expr)==0 ? 2 : 1
        if index<=length(s.clauses)
            chosen = s.clauses[index]
            following = chosen.line===nothing ? first(chosen.body) : line(m,chosen.line)
        end
    elseif s.kind == "GOTO"
        following = line(m,s.numbers[1])
    elseif s.kind == "GOSUB"
        following = subroutine!(m,s.numbers[1],following)
    elseif s.kind == "ON"
        n = evaluate(m,s.expr)
        n<0 && fault("ILLEGAL FUNCTION CALL")
        if 1<=n<=length(s.numbers)
            following = s.mode=="GOTO" ? line(m,s.numbers[n]) :
                         subroutine!(m,s.numbers[n],following)
        end
    elseif s.kind == "RETURN"
        index = findlast(f->f.kind=="GOSUB",m.stack)
        index===nothing && fault("RETURN WITHOUT GOSUB")
        following = m.stack[index].position
        resize!(m.stack,index-1)
    elseif s.kind == "FOR"
        start,limit,step = [evaluate(m,e) for e in s.expressions]
        step==0 && fault("ILLEGAL FUNCTION CALL")
        index = search_frame(m,"FOR",s.name)
        index!==nothing && resize!(m.stack,index-1)
        m.variables[s.name] = start
        if (step>0 && start>limit) || (step<0 && start<limit)
            following = matching(m,s,"FOR","NEXT")
        else
            push_frame!(m,(;kind="FOR",position=following,name=s.name,final=limit,step))
        end
    elseif s.kind == "NEXT"
        index = search_frame(m,"FOR",s.name)
        index===nothing && fault("NEXT WITHOUT FOR")
        resize!(m.stack,index)
        frame = m.stack[index]
        value = checked(get_variable(m,frame.name)+frame.step)
        m.variables[frame.name] = value
        if (frame.step>0 && value>frame.final) ||
           (frame.step<0 && value<frame.final)
            pop!(m.stack)
        else
            following = frame.position
        end
    elseif s.kind == "WHILE"
        if evaluate(m,s.expr)==0
            following = matching(m,s,"WHILE","WEND")
        else
            push_frame!(m,(;kind="WHILE",position=s,name="",final=0,step=0))
        end
    elseif s.kind == "WEND"
        index = search_frame(m,"WHILE")
        index===nothing && fault("WEND WITHOUT WHILE")
        following = m.stack[index].position
        resize!(m.stack,index-1)
    elseif s.kind == "DIM"
        for target in s.targets
            name = target.value
            bounds = Int[evaluate(m,e) for e in target.args]
            haskey(m.arrays,name) && fault("DUPLICATE DEFINITION")
            any(x->x<0,bounds) && fault("ILLEGAL FUNCTION CALL")
            prod(x+1 for x in bounds)>10000 && fault("OUT OF MEMORY")
            declare!(m,name,bounds)
        end
    elseif s.kind == "RANDOMIZE"
        n = evaluate(m,s.expr)
        n<1 && fault("ILLEGAL FUNCTION CALL")
        m.random = n
    elseif s.kind == "handler"
        s.numbers[1]!=0 && line(m,s.numbers[1])
        m.handler = s.numbers[1]
    elseif s.kind == "RESUME"
        !m.handling && fault("RESUME WITHOUT ERROR")
        following = s.mode=="line" ? line(m,s.numbers[1]) :
                    s.mode=="NEXT" ? m.remembered.next : m.remembered
        m.handling = false
    elseif s.kind == "STOP"
        message!(m,"BREAK IN LINE "*string(s.line))
        return nothing
    elseif s.kind == "END"
        return nothing
    end
    following
end

function connect!(body::Vector{Stmt},after,number::Int)
    following = after
    for s in Iterators.reverse(body)
        s.line = number
        s.next = following
        for clause in s.clauses
            connect!(clause.body,following,number)
        end
        following = s
    end
end

function finish!(m::Machine)
    !isempty(m.buffer) && end_line!(m)
    push!(m.output,"READY")
    m.output
end

function run!(m::Machine,source::Dict{Int,String})
    parsed = Any[]
    for number in sort(collect(keys(source)))
        try
            body = parse_program(Parser(tokenize(source[number])))
            push!(parsed,(;number,body))
        catch e
            e isa SyntaxFault || rethrow()
            message!(m,"ERROR IN LINE "*string(number)*": SYNTAX ERROR")
            return finish!(m)
        end
    end
    after = nothing
    for entry in Iterators.reverse(parsed)
        connect!(entry.body,after,entry.number)
        m.entries[entry.number] = first(entry.body)
        after = first(entry.body)
    end
    for entry in parsed
        for s in entry.body
            push!(m.sequence,s)
            if s.kind=="DATA"
                for value in s.values
                    push!(m.data,(;line=s.line,value))
                end
            end
        end
    end
    position = after
    while position!==nothing
        s = position
        try
            position = execute!(m,s)
        catch e
            e isa BasicFault || rethrow()
            if m.handler!=0 && !m.handling
                m.err = get(ERROR_CODES,e.message,0)
                m.erl = s.line
                m.remembered = s
                m.handling = true
                try
                    position = line(m,m.handler)
                catch secondary
                    secondary isa BasicFault || rethrow()
                    message!(m,"ERROR IN LINE "*string(s.line)*": "*secondary.message)
                    position = nothing
                end
            else
                message!(m,"ERROR IN LINE "*string(s.line)*": "*e.message)
                position = nothing
            end
        end
    end
    finish!(m)
end

function main()
    lines = String.(split(replace(read(stdin,String),"\r\n"=>"\n"),'\n';keepempty=true))
    cursor = 2
    output = String[]
    for _ in 1:parse(Int,lines[1])
        source = Dict{Int,String}()
        while lines[cursor]!="RUN"
            match_result = match(r"^([0-9]+)(?: +(.*))?$",lines[cursor])
            cursor += 1
            number = parse(Int,match_result.captures[1])
            body = match_result.captures[2]
            if body===nothing
                delete!(source,number)
            else
                source[number] = body
            end
        end
        cursor += 1
        inputs = String[]
        while lines[cursor]!="END"
            push!(inputs,lines[cursor])
            cursor += 1
        end
        cursor += 1
        append!(output,run!(Machine(inputs),source))
    end
    println(join(output,"\n"))
end

main()
