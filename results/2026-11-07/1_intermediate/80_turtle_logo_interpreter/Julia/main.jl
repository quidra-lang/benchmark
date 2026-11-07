const COMMANDS=Dict(
    "FD"=>"E",
    "BK"=>"E",
    "RT"=>"E",
    "LT"=>"E",
    "SETH"=>"E",
    "PU"=>"",
    "PD"=>"",
    "PE"=>"",
    "SETPEN"=>"E",
    "SETXY"=>"EE",
    "SETX"=>"E",
    "SETY"=>"E",
    "HOME"=>"",
    "CS"=>"",
    "CLEAN"=>"",
    "FILL"=>"",
    "LABEL"=>"P",
    "SNAPSHOT"=>"",
    "REPEAT"=>"EL",
    "FOR"=>"QEEL",
    "WHILE"=>"EL",
    "IF"=>"EL",
    "IFELSE"=>"ELL",
    "TEST"=>"E",
    "IFTRUE"=>"L",
    "IFFALSE"=>"L",
    "STOP"=>"",
    "OUTPUT"=>"E",
    "MAKE"=>"QE",
    "LOCAL"=>"Q",
    "LOCALMAKE"=>"QE",
    "TRACE"=>"Q",
    "UNTRACE"=>"Q",
    "SEED"=>"E",
    "PRINT"=>"P",
)
const FUNCTIONS=Dict(
    "XCOR"=>0,
    "YCOR"=>0,
    "HEADING"=>0,
    "REPCOUNT"=>0,
    "RANDOM"=>1,
    "ABS"=>1,
    "NOT"=>1,
    "AND"=>2,
    "OR"=>2,
    "MAX"=>2,
    "MIN"=>2,
)
const ALIASES=Dict(
    "FORWARD"=>"FD",
    "BACK"=>"BK",
    "RIGHT"=>"RT",
    "LEFT"=>"LT",
    "SETHEADING"=>"SETH",
    "PENUP"=>"PU",
    "PENDOWN"=>"PD",
    "PENERASE"=>"PE",
    "CLEARSCREEN"=>"CS",
    "IFT"=>"IFTRUE",
    "IFF"=>"IFFALSE",
    "OP"=>"OUTPUT",
    "PR"=>"PRINT",
)
const PRIMITIVES=union(
    Set(keys(COMMANDS)),
    Set(keys(FUNCTIONS)),
    Set(keys(ALIASES)),
    Set(["TO", "END", "MOD"]),
)
const OPLEVELS=(("=", "<>", "<", ">", "<=", ">="), ("+", "-"), ("*", "/", "MOD"))
const DIRECTIONS=((0, 1), (1, 1), (1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1))
struct LogoError <: Exception
    line::Int
    reason::String
end
logoerror(line, reason) = throw(LogoError(line, reason))
reject(line, owner, value) = logoerror(line, "$owner doesn't like $value as input")
struct Token
    kind::Symbol
    spelling::String
    line::Int
    value::String
end
abstract type LogoNode end
struct NumberNode <: LogoNode
    value::Int
end
struct VariableNode <: LogoNode
    name::String
    line::Int
end
struct QuotedNode <: LogoNode
    value::String
    line::Int
end
struct NegationNode <: LogoNode
    operand::LogoNode
end
struct BinaryNode <: LogoNode
    operator::String
    left::LogoNode
    right::LogoNode
    line::Int
end
struct CallNode <: LogoNode
    name::String
    spelling::String
    line::Int
    inputs::Vector{LogoNode}
end
struct ListNode <: LogoNode
    commands::Vector{CallNode}
end
mutable struct Procedure
    name::String
    parameters::Vector{String}
    line::Int
    tokens::Vector{Token}
    body::ListNode
end
namevalid(s) = occursin(r"\A[A-Z][A-Z0-9_]*\z", s)
function classify(s, line)
    occursin(r"\A[0-9]+\z", s) && return Token(:number, s, line, s)
    namevalid(s) && return Token(:word, s, line, s)
    s[1] in (':', '"') &&
        namevalid(s[2:end]) &&
        return Token(s[1]==':' ? :variable : :quoted, s, line, s[2:end])
    logoerror(line, "bad token '$s'")
end
function tokenize(text, line)
    source=uppercase(first(split(text, ';'; limit = 2)))
    result=Token[]
    i=1
    delimiters=" []()+-*/=<>"
    while i<=length(source)
        c=source[i]
        following=i<length(source) ? source[i+1] : '\0'
        if c==' '
            i+=1
        elseif c=='-'
            sign=(i==1 || source[i-1] in " [(") && following!='\0' && following!=' '
            push!(result, Token(sign ? :sign : :symbol, "-", line, ""))
            i+=1
        elseif c in "<>"
            pair=string(c, following)
            spelling=pair in ("<=", "<>", ">=") ? pair : string(c)
            push!(result, Token(:symbol, spelling, line, ""))
            i+=length(spelling)
        elseif c in delimiters
            push!(result, Token(:symbol, string(c), line, ""))
            i+=1
        else
            start=i
            while i<=length(source) && !(source[i] in delimiters)
                i+=1
            end
            push!(result, classify(source[start:(i-1)], line))
        end
    end
    result
end
isword(t, s) = t.kind==:word && t.spelling==s
function extract(source)
    procedures=Dict{String,Procedure}()
    order=String[]
    top=Token[]
    current=nothing
    for (line, text) in source
        tokens=tokenize(text, line)
        isempty(tokens) && continue
        if isword(tokens[1], "TO")
            current!==nothing && logoerror(line, "TO inside definition of $(current.name)")
            length(tokens)>=2 && tokens[2].kind==:word || logoerror(line, "bad procedure header")
            name=tokens[2].spelling
            name in PRIMITIVES && logoerror(line, "$name is a primitive")
            haskey(procedures, name) && logoerror(line, "$name is already defined")
            parameters=String[]
            for token in tokens[3:end]
                token.kind==:variable || logoerror(line, "bad procedure header")
                token.value in parameters && logoerror(line, "duplicate input $(token.spelling)")
                push!(parameters, token.value)
            end
            current=Procedure(name, parameters, line, Token[], ListNode(CallNode[]))
            procedures[name]=current
            push!(order, name)
        elseif length(tokens)==1 && isword(tokens[1], "END")
            current===nothing && logoerror(line, "END without TO")
            current=nothing
        elseif current===nothing
            append!(top, tokens)
        else
            append!(current.tokens, tokens)
        end
    end
    current!==nothing && logoerror(current.line, "missing END for $(current.name)")
    procedures, order, top
end
mutable struct Parser
    tokens::Vector{Token}
    procedures::Dict{String,Procedure}
    inprocedure::Bool
    position::Int
end
Parser(tokens, procedures, inprocedure) = Parser(tokens, procedures, inprocedure, 1)
peek(p) = p.position<=length(p.tokens) ? p.tokens[p.position] : nothing
function advance!(p)
    t=p.tokens[p.position]
    p.position+=1
    t
end
nextis(p, spellings) = peek(p)!==nothing && peek(p).kind!=:sign && peek(p).spelling in spellings
unknown(p, t) = t.kind==:word && !(t.spelling in PRIMITIVES) && !haskey(p.procedures, t.spelling)
function inputtoken(p, owner)
    t=peek(p)
    (t===nothing || t.spelling in ("]", ")")) &&
        logoerror(owner.line, "not enough inputs to $(owner.spelling)")
    unknown(p, t) && logoerror(t.line, "I don't know how to $(t.spelling)")
    t
end
function parsesequence!(p)
    commands=CallNode[]
    while peek(p)!==nothing
        t=peek(p)
        t.spelling=="]" && logoerror(t.line, "unexpected ]")
        push!(commands, parsecommand!(p))
    end
    ListNode(commands)
end
function parselist!(p)
    opening=advance!(p)
    commands=CallNode[]
    while !nextis(p, ("]",))
        peek(p)===nothing && logoerror(opening.line, "missing ]")
        push!(commands, parsecommand!(p))
    end
    advance!(p)
    ListNode(commands)
end
function parseinput!(p, owner, kind)
    t=inputtoken(p, owner)
    kind=='L' && t.spelling=="[" && return parselist!(p)
    if kind in ('Q', 'P') && t.kind==:quoted
        advance!(p)
        return QuotedNode(t.value, t.line)
    end
    kind in ('E', 'P') && return parseexpression!(p, owner)
    reject(t.line, owner.spelling, t.spelling)
end
function parsecall!(p, t, n)
    inputs=LogoNode[]
    for _ in 1:n
        push!(inputs, parseexpression!(p, t))
    end
    CallNode(t.spelling, t.spelling, t.line, inputs)
end
function parsecommand!(p)
    t=advance!(p)
    if t.spelling=="(" && nextis(p, ("PRINT", "PR"))
        word=advance!(p)
        inputs=LogoNode[]
        while !nextis(p, (")",))
            (peek(p)===nothing || nextis(p, ("]",))) && logoerror(t.line, "missing )")
            push!(inputs, parseinput!(p, word, 'P'))
        end
        advance!(p)
        return CallNode("PRINT", word.spelling, t.line, inputs)
    end
    if t.kind==:word
        name=get(ALIASES, t.spelling, t.spelling)
        name in ("TO", "END") && logoerror(t.line, "misplaced $name")
        if haskey(COMMANDS, name)
            name in ("STOP", "OUTPUT", "LOCAL", "LOCALMAKE") &&
                !p.inprocedure &&
                logoerror(t.line, "can only use $(t.spelling) inside a procedure")
            inputs=LogoNode[]
            for kind in COMMANDS[name]
                push!(inputs, parseinput!(p, t, kind))
            end
            if name in ("TRACE", "UNTRACE") && !haskey(p.procedures, inputs[1].value)
                logoerror(inputs[1].line, "I don't know how to $(inputs[1].value)")
            end
            return CallNode(name, t.spelling, t.line, inputs)
        end
        haskey(p.procedures, name) && return parsecall!(p, t, length(p.procedures[name].parameters))
        unknown(p, t) && logoerror(t.line, "I don't know how to $name")
    end
    logoerror(t.line, "you don't say what to do with $(t.spelling)")
end
function parseexpression!(p, owner, level = 1)
    level>3 && return parseterm!(p, owner)
    left=parseexpression!(p, owner, level+1)
    while nextis(p, OPLEVELS[level])
        op=advance!(p)
        right=parseexpression!(p, op, level+1)
        left=BinaryNode(op.spelling, left, right, op.line)
    end
    left
end
function parseterm!(p, owner)
    t=inputtoken(p, owner)
    advance!(p)
    t.kind==:number && return NumberNode(parse(Int, t.value))
    t.kind==:variable && return VariableNode(t.value, t.line)
    t.spelling=="-" && return NegationNode(parseterm!(p, t))
    if t.spelling=="("
        node=parseexpression!(p, t)
        nextis(p, (")",)) || logoerror(t.line, "missing )")
        advance!(p)
        return node
    end
    haskey(FUNCTIONS, t.spelling) && return parsecall!(p, t, FUNCTIONS[t.spelling])
    haskey(p.procedures, t.spelling) &&
        return parsecall!(p, t, length(p.procedures[t.spelling].parameters))
    reject(t.line, owner.spelling, t.spelling)
end
mutable struct LogoEnvironment
    procedure::String
    variables::Dict{String,Int}
    test::Union{Nothing,Bool}
end
struct ProcedureExit <: Exception
    value::Union{Nothing,Int}
end
mutable struct Interpreter
    procedures::Dict{String,Procedure}
    x::Int
    y::Int
    heading::Int
    pen::String
    character::Char
    canvas::Dict{Tuple{Int,Int},Char}
    environments::Vector{LogoEnvironment}
    repcounts::Vector{Int}
    traced::Set{String}
    randomstate::Int
end
Interpreter(procedures) = Interpreter(
    procedures,
    0,
    0,
    0,
    "DOWN",
    '*',
    Dict{Tuple{Int,Int},Char}(),
    [LogoEnvironment("", Dict{String,Int}(), nothing)],
    Int[],
    Set{String}(),
    1,
)
function lookup(r, node)
    for env in Iterators.reverse(r.environments)
        haskey(env.variables, node.name) && return env.variables[node.name]
    end
    logoerror(node.line, "$(node.name) has no value")
end
function make!(r, name, value)
    for env in Iterators.reverse(r.environments[2:end])
        if haskey(env.variables, name)
            env.variables[name]=value
            return
        end
    end
    r.environments[1].variables[name]=value
end
function callprocedure!(r, call)
    procedure=r.procedures[call.name]
    values=Int[]
    for arg in call.inputs
        push!(values, evaluate!(r, arg))
    end
    depth=length(r.environments)-1
    depth>=100 && logoerror(call.line, "recursion too deep")
    traced=procedure.name in r.traced
    indent=repeat("  ", depth)
    traced && println(indent, "( ", join([procedure.name; string.(values)], ' '), " )")
    push!(
        r.environments,
        LogoEnvironment(procedure.name, Dict(zip(procedure.parameters, values)), nothing),
    )
    result=nothing
    try
        runlist!(r, procedure.body)
    catch signal
        signal isa ProcedureExit || rethrow()
        result=signal.value
    end
    pop!(r.environments)
    traced && println(indent, procedure.name, result===nothing ? " stops" : " outputs $result")
    result
end
function evaluate!(r, node)
    node isa NumberNode && return node.value
    node isa VariableNode && return lookup(r, node)
    node isa NegationNode && return -evaluate!(r, node.operand)
    if node isa BinaryNode
        a=evaluate!(r, node.left)
        b=evaluate!(r, node.right)
        op=node.operator
        if op in ("/", "MOD")
            b==0 && reject(node.line, op, 0)
            q=div(a, b)
            return op=="/" ? q : a-b*q
        end
        op=="+" && return a+b
        op=="-" && return a-b
        op=="*" && return a*b
        return Int(
            op=="=" ? a==b :
            op=="<>" ? a!=b : op=="<" ? a<b : op==">" ? a>b : op=="<=" ? a<=b : a>=b,
        )
    end
    if haskey(r.procedures, node.name)
        value=callprocedure!(r, node)
        value===nothing && logoerror(node.line, "$(node.name) did not output")
        return value
    end
    args=Int[]
    for arg in node.inputs
        push!(args, evaluate!(r, arg))
    end
    name=node.name
    name=="XCOR" && return r.x
    name=="YCOR" && return r.y
    name=="HEADING" && return r.heading
    if name=="REPCOUNT"
        isempty(r.repcounts) && logoerror(node.line, "REPCOUNT outside REPEAT")
        return r.repcounts[end]
    end
    if name=="RANDOM"
        args[1]<1 && reject(node.line, node.spelling, args[1])
        r.randomstate=mod(48271*r.randomstate, 2147483647)
        return mod(r.randomstate, args[1])
    end
    name=="ABS" && return abs(args[1])
    name=="NOT" && return Int(args[1]==0)
    name=="AND" && return Int(args[1]!=0 && args[2]!=0)
    name=="OR" && return Int(args[1]!=0 || args[2]!=0)
    name=="MAX" ? max(args...) : min(args...)
end
printitem!(r, node) = node isa QuotedNode ? node.value : string(evaluate!(r, node))
function applypen!(r, x, y)
    if r.pen=="DOWN"
        r.canvas[(x, y)]=r.character
    elseif r.pen=="ERASE"
        delete!(r.canvas, (x, y))
    end
end
function forward!(r, steps)
    dx, dy=DIRECTIONS[div(r.heading, 45)+1]
    steps<0 && ((dx, dy, steps)=(-dx, -dy, -steps))
    applypen!(r, r.x, r.y)
    for _ in 1:steps
        r.x+=dx
        r.y+=dy
        applypen!(r, r.x, r.y)
    end
end
function moveto!(r, x, y)
    dx=x-r.x
    dy=y-r.y
    s=max(abs(dx), abs(dy))
    if s==0
        applypen!(r, r.x, r.y)
    else
        for i in 0:s
            applypen!(r, r.x+fld(2i*dx+s, 2s), r.y+fld(2i*dy+s, 2s))
        end
    end
    r.x=x
    r.y=y
end
function canvasbounds(r)
    (
        minimum(p[1] for p in keys(r.canvas)),
        minimum(p[2] for p in keys(r.canvas)),
        maximum(p[1] for p in keys(r.canvas)),
        maximum(p[2] for p in keys(r.canvas)),
    )
end
function fillcanvas!(r)
    (isempty(r.canvas) || haskey(r.canvas, (r.x, r.y))) && return
    x, y, u, v=canvasbounds(r)
    x<=r.x<=u && y<=r.y<=v || return
    pending=[(r.x, r.y)]
    r.canvas[(r.x, r.y)]=r.character
    while !isempty(pending)
        a, b=pop!(pending)
        for (p, q) in ((a-1, b), (a+1, b), (a, b-1), (a, b+1))
            if x<=p<=u && y<=q<=v && !haskey(r.canvas, (p, q))
                r.canvas[(p, q)]=r.character
                push!(pending, (p, q))
            end
        end
    end
end
function writecanvas(r)
    if isempty(r.canvas)
        println("CANVAS 0 0 0")
        return
    end
    x, y, u, v=canvasbounds(r)
    println("CANVAS $(u-x+1) $(v-y+1) $(length(r.canvas))")
    for row in v:-1:y
        println(rstrip(join(get(r.canvas, (col, row), ' ') for col in x:u), ' '))
    end
end
function runlist!(r, list)
    for command in list.commands
        execute!(r, command)
    end
end
function execute!(r, command)
    name=command.name
    inputs=command.inputs
    if haskey(r.procedures, name)
        value=callprocedure!(r, command)
        value!==nothing && logoerror(command.line, "you don't say what to do with $value")
        return
    end
    if name in ("FD", "BK")
        n=evaluate!(r, inputs[1])
        forward!(r, name=="FD" ? n : -n)
    elseif name in ("RT", "LT", "SETH")
        angle=evaluate!(r, inputs[1])
        angle%45!=0 && reject(command.line, command.spelling, angle)
        r.heading=mod(name=="SETH" ? angle : r.heading+(name=="RT" ? angle : -angle), 360)
    elseif name in ("PU", "PD", "PE")
        r.pen=name=="PU" ? "UP" : name=="PD" ? "DOWN" : "ERASE"
    elseif name=="SETPEN"
        code=evaluate!(r, inputs[1])
        33<=code<=126 || reject(command.line, command.spelling, code)
        r.character=Char(code)
    elseif name=="SETXY"
        x=evaluate!(r, inputs[1])
        y=evaluate!(r, inputs[2])
        moveto!(r, x, y)
    elseif name=="SETX"
        x=evaluate!(r, inputs[1])
        moveto!(r, x, r.y)
    elseif name=="SETY"
        y=evaluate!(r, inputs[1])
        moveto!(r, r.x, y)
    elseif name=="HOME"
        moveto!(r, 0, 0)
        r.heading=0
    elseif name=="CS"
        empty!(r.canvas)
        r.x=r.y=r.heading=0
    elseif name=="CLEAN"
        empty!(r.canvas)
    elseif name=="FILL"
        fillcanvas!(r)
    elseif name=="LABEL"
        text=printitem!(r, inputs[1])
        dx, dy=DIRECTIONS[div(r.heading, 45)+1]
        for (i, c) in enumerate(text)
            r.canvas[(r.x+(i-1)*dx, r.y+(i-1)*dy)]=c
        end
    elseif name=="SNAPSHOT"
        writecanvas(r)
    elseif name=="REPEAT"
        n=evaluate!(r, inputs[1])
        for k in (isempty(inputs[2].commands) ? (1:0) : (1:n))
            push!(r.repcounts, k)
            try
                runlist!(r, inputs[2])
            finally
                pop!(r.repcounts)
            end
        end
    elseif name=="FOR"
        variable=inputs[1].value
        a=evaluate!(r, inputs[2])
        b=evaluate!(r, inputs[3])
        step=a<=b ? 1 : -1
        if isempty(inputs[4].commands)
            make!(r, variable, b)
        else
            for value in a:step:b
                make!(r, variable, value)
                runlist!(r, inputs[4])
            end
        end
    elseif name=="WHILE"
        while evaluate!(r, inputs[1])!=0
            runlist!(r, inputs[2])
        end
    elseif name=="IF"
        evaluate!(r, inputs[1])!=0 && runlist!(r, inputs[2])
    elseif name=="IFELSE"
        value=evaluate!(r, inputs[1])
        runlist!(r, inputs[value!=0 ? 2 : 3])
    elseif name=="TEST"
        value=evaluate!(r, inputs[1])
        r.environments[end].test=value!=0
    elseif name in ("IFTRUE", "IFFALSE")
        test=r.environments[end].test
        test===nothing && logoerror(command.line, "$(command.spelling) without TEST")
        test==(name=="IFTRUE") && runlist!(r, inputs[1])
    elseif name=="STOP"
        throw(ProcedureExit(nothing))
    elseif name=="OUTPUT"
        throw(ProcedureExit(evaluate!(r, inputs[1])))
    elseif name=="MAKE"
        value=evaluate!(r, inputs[2])
        make!(r, inputs[1].value, value)
    elseif name=="LOCAL"
        r.environments[end].variables[inputs[1].value]=0
    elseif name=="LOCALMAKE"
        value=evaluate!(r, inputs[2])
        r.environments[end].variables[inputs[1].value]=value
    elseif name=="TRACE"
        push!(r.traced, inputs[1].value)
    elseif name=="UNTRACE"
        delete!(r.traced, inputs[1].value)
    elseif name=="SEED"
        value=evaluate!(r, inputs[1])
        value<1 && reject(command.line, command.spelling, value)
        r.randomstate=value
    elseif name=="PRINT"
        texts=String[]
        for item in inputs
            push!(texts, printitem!(r, item))
        end
        println(join(texts, ' '))
    end
end
function runprogram(name, source)
    println("PROGRAM $name")
    local procedures, order, top, commands
    try
        procedures, order, top=extract(source)
        for name in order
            procedure=procedures[name]
            procedure.body=parsesequence!(Parser(procedure.tokens, procedures, true))
        end
        commands=parsesequence!(Parser(top, procedures, false))
    catch e
        e isa LogoError || rethrow()
        println("ERROR line $(e.line): $(e.reason)")
        return
    end
    runtime=Interpreter(procedures)
    try
        runlist!(runtime, commands)
        println(
            "TURTLE $(runtime.x) $(runtime.y) $(runtime.heading) $(runtime.pen) $(runtime.character)",
        )
        writecanvas(runtime)
    catch e
        e isa LogoError || rethrow()
        println("ERROR line $(e.line): $(e.reason)")
        calls=[env.procedure for env in Iterators.reverse(runtime.environments[2:end])]
        at=1
        while at<=length(calls)
            finish=at+1
            while finish<=length(calls) && calls[finish]==calls[at]
                finish+=1
            end
            count=finish-at
            println("  in ", calls[at], count==1 ? "" : " x$count")
            at=finish
        end
    end
end
function main()
    name=""
    source=Tuple{Int,String}[]
    for (number, line) in enumerate(eachline())
        if line=="#EOF"
            runprogram(name, source)
            break
        elseif startswith(line, "#PROGRAM ")
            !isempty(name) && runprogram(name, source)
            name=line[10:end]
            source=Tuple{Int,String}[]
        else
            push!(source, (number, line))
        end
    end
end
main()
