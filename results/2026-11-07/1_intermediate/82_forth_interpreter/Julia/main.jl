const DIGITS="0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const COMPILE_ONLY=Set(
    split(
        "IF ELSE THEN DO ?DO LOOP +LOOP LEAVE UNLOOP I J BEGIN UNTIL WHILE REPEAT AGAIN CASE OF ENDOF ENDCASE EXIT RECURSE DOES> ; >R R> R@ ABORT\" ['] {:",
    ),
)
const INTERPRET_ONLY=Set([":", ":NONAME", "FORGET"])
const SPECIAL=union(COMPILE_ONLY, INTERPRET_ONLY, Set([".\"", "(", "\\", "TO", "IS"]))
const BUILTINS=split(
    "+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/ = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP 2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @ +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS",
)
mutable struct ForthFailure <: Exception
    reason::String
    code::Union{Nothing,Int}
    token::Union{Nothing,String}
end
failure(reason, code = nothing, token = nothing) = throw(ForthFailure(reason, code, token))
mutable struct Instruction
    op::String
    token::String
    argument::Any
end
mutable struct ControlRecord
    kind::String
    origin::Int
    references::Vector{Int}
end
mutable struct Definition
    name::String
    display::String
    here::Int
    body::Vector{Instruction}
    controls::Vector{ControlRecord}
    locals::Dict{String,Int}
    localcount::Int
end
Definition(name, display, here) =
    Definition(name, display, here, Instruction[], ControlRecord[], Dict{String,Int}(), 0)
mutable struct ForthWord
    name::String
    kind::String
    definition::Union{Nothing,Definition}
    address::Int
    value::Int
    here::Int
    does::Union{Nothing,Tuple{Definition,Int}}
    target::Any
    xt::Int
end
ForthWord(name, kind) = ForthWord(name, kind, nothing, 0, 0, 0, nothing, nothing, 0)
mutable struct Interpreter
    stack::Vector{Int}
    returns::Vector{Int}
    memory::Vector{Int}
    dictionary::Vector{ForthWord}
    builtins::Dict{String,ForthWord}
    tokens::Vector{ForthWord}
    depth::Int
    compiling::Union{Nothing,Definition}
    pending::String
    line::String
    position::Int
end
Interpreter() = Interpreter(
    Int[],
    Int[],
    [10],
    ForthWord[],
    Dict(name=>ForthWord(name, "builtin") for name in BUILTINS),
    ForthWord[],
    0,
    nothing,
    "",
    "",
    1,
)
function pushdata!(r, value)
    length(r.stack)==1000 && failure("stack overflow", -3)
    push!(r.stack, value)
end
function popdata!(r)
    isempty(r.stack) && failure("stack underflow", -4)
    pop!(r.stack)
end
function takevalues!(r, n)
    length(r.stack)<n && failure("stack underflow", -4)
    at=length(r.stack)-n
    values=r.stack[(at+1):end]
    resize!(r.stack, at)
    values
end
function pushvalues!(r, values)
    for value in values
        pushdata!(r, value)
    end
end
function pushreturn!(r, value)
    length(r.returns)==1000 && failure("return stack overflow", -5)
    push!(r.returns, value)
end
requirereturn(r, n) = length(r.returns)<n ? failure("return stack underflow", -6) : nothing
here(r) = 8*length(r.memory)
function cell(r, address)
    (address<0 || address%8!=0 || address>=here(r)) && failure("invalid address", -9)
    div(address, 8)+1
end
function radix(r)
    base=r.memory[1]
    2<=base<=36 || failure("invalid base", -40)
    base
end
function parsedigits(text, base)
    negative=startswith(text, '-')
    digits=negative ? text[2:end] : text
    isempty(digits) && return nothing
    value=0
    for c in uppercase(digits)
        index=findfirst(==(c), DIGITS)
        (index===nothing || index>base) && return nothing
        value=value*base+index-1
    end
    negative ? -value : value
end
function parsenumber(r, text, base = nothing)
    length(text)==3 && text[1]=='\'' && text[3]=='\'' && return Int(text[2])
    text[1] in ('\$', '#', '%') &&
        return parsedigits(text[2:end], text[1]=='\$' ? 16 : text[1]=='#' ? 10 : 2)
    parsedigits(text, base===nothing ? radix(r) : base)
end
function literal(r, text)
    value=parsenumber(r, text)
    value===nothing && failure("undefined word", -13)
    value
end
function formatnumber(r, number)
    base=radix(r)
    value=abs(number)
    text=string(DIGITS[mod(value, base)+1])
    while value>=base
        value=div(value, base)
        text=string(DIGITS[mod(value, base)+1])*text
    end
    number<0 ? "-"*text : text
end
writepending!(r, text) = (r.pending*=text)
function flushline!(r)
    println(rstrip(r.pending, ' '))
    r.pending=""
end
function readword!(r)
    at=r.position
    while at<=length(r.line) && r.line[at]==' '
        at+=1
    end
    start=at
    while at<=length(r.line) && r.line[at]!=' '
        at+=1
    end
    r.position=at
    start==at ? nothing : r.line[start:(at-1)]
end
function readname!(r)
    name=readword!(r)
    name===nothing && failure("missing name", -16)
    name
end
function readstring!(r)
    start=r.position+1
    finish=start<=length(r.line) ? findnext('"', r.line, start) : nothing
    finish===nothing && failure("unterminated string")
    r.position=finish+1
    r.line[start:(finish-1)]
end
function findword(r, name)
    for word in Iterators.reverse(r.dictionary)
        word.name==name && return word
    end
    get(r.builtins, name, nothing)
end
function existing(r, name)
    word=findword(r, uppercase(name))
    word===nothing && failure("undefined word", -13, name)
    word
end
function checkname(r, name)
    (uppercase(name) in SPECIAL || parsenumber(r, name, 10)!==nothing) &&
        failure("invalid name", -19, name)
end
function newname!(r)
    name=readname!(r)
    checkname(r, name)
    uppercase(name)
end
function addword!(r, word)
    word.here=here(r)
    push!(r.dictionary, word)
end
function executiontoken!(r, word)
    if word.xt==0
        push!(r.tokens, word)
        word.xt=length(r.tokens)
    end
    word.xt
end
function tokenword(r, xt)
    1<=xt<=length(r.tokens) || failure("invalid argument", -24)
    r.tokens[xt]
end
function setdeferred!(r, word)
    word.target=tokenword(r, popdata!(r))
end
function executeword!(r, word, token)
    try
        while word.kind=="defer"
            word.target===nothing && failure("deferred word not set", -21)
            word=word.target
            token=word.name
        end
        if word.kind=="builtin"
            builtin!(r, word.name)
        elseif word.kind=="colon"
            rundefinition!(r, word.definition, 1)
        elseif word.kind in ("create", "variable")
            pushdata!(r, word.address)
            word.does!==nothing && rundefinition!(r, word.does...)
        elseif word.kind=="constant"
            pushdata!(r, word.value)
        elseif word.kind=="value"
            pushdata!(r, r.memory[div(word.address, 8)+1])
        end
    catch error
        error isa ForthFailure || rethrow()
        error.token===nothing && (error.token=token)
        rethrow()
    end
end
function builtin!(r, name)
    if name in (
        "+",
        "-",
        "*",
        "/",
        "MOD",
        "/MOD",
        "*/",
        "*/MOD",
        "MIN",
        "MAX",
        "=",
        "<>",
        "<",
        ">",
        "AND",
        "OR",
        "XOR",
        "WITHIN",
    )
        values=takevalues!(r, name in ("*/", "*/MOD", "WITHIN") ? 3 : 2)
        a, b=values[1:2]
        if name in ("/", "MOD", "/MOD", "*/", "*/MOD")
            if length(values)==3
                a*=b
                b=values[3]
            end
            b==0 && failure("division by zero", -10)
            q=fld(a, b)
            rem=a-b*q
            pushvalues!(r, name in ("/MOD", "*/MOD") ? [rem, q] : [name=="MOD" ? rem : q])
        else
            value=name=="+" ? a+b :
                  name=="-" ? a-b :
                  name=="*" ? a*b :
                  name=="MIN" ? min(a, b) :
                  name=="MAX" ? max(a, b) :
                  name=="AND" ? a&b :
                  name=="OR" ? a|b :
                  name=="XOR" ? xor(a, b) :
                  -Int(
                name=="=" ? a==b :
                name=="<>" ? a!=b : name=="<" ? a<b : name==">" ? a>b : b<=a<values[3],
            )
            pushdata!(r, value)
        end
    elseif name in (
        "NEGATE",
        "ABS",
        "1+",
        "1-",
        "2*",
        "2/",
        "0=",
        "0<>",
        "0<",
        "0>",
        "INVERT",
        "CELLS",
        "CELL+",
    )
        a=popdata!(r)
        value=name=="NEGATE" ? -a :
              name=="ABS" ? abs(a) :
              name=="1+" ? a+1 :
              name=="1-" ? a-1 :
              name=="2*" ? 2a :
              name=="2/" ? fld(a, 2) :
              name=="INVERT" ? -a-1 :
              name=="CELLS" ? 8a :
              name=="CELL+" ? a+8 :
              -Int(name=="0=" ? a==0 : name=="0<>" ? a!=0 : name=="0<" ? a<0 : a>0)
        pushdata!(r, value)
    elseif name in (
        "DUP",
        "?DUP",
        "DROP",
        "SWAP",
        "OVER",
        "ROT",
        "-ROT",
        "NIP",
        "TUCK",
        "2DUP",
        "2DROP",
        "2SWAP",
        "2OVER",
    )
        n=name in ("DUP", "?DUP", "DROP") ? 1 :
          name in ("ROT", "-ROT") ? 3 : name in ("2SWAP", "2OVER") ? 4 : 2
        v=takevalues!(r, n)
        out=name=="DUP" ? v[[1, 1]] :
            name=="?DUP" ? (v[1]==0 ? v : v[[1, 1]]) :
            name in ("DROP", "2DROP") ? Int[] :
            name=="SWAP" ? v[[2, 1]] :
            name=="OVER" ? v[[1, 2, 1]] :
            name=="ROT" ? v[[2, 3, 1]] :
            name=="-ROT" ? v[[3, 1, 2]] :
            name=="NIP" ? v[[2]] :
            name=="TUCK" ? v[[2, 1, 2]] :
            name=="2DUP" ? v[[1, 2, 1, 2]] : name=="2SWAP" ? v[[3, 4, 1, 2]] : v[[1, 2, 3, 4, 1, 2]]
        pushvalues!(r, out)
    elseif name in ("TRUE", "FALSE", "DEPTH", "BL", "HERE", "BASE")
        pushdata!(
            r,
            name=="TRUE" ? -1 :
            name=="FALSE" || name=="BASE" ? 0 :
            name=="DEPTH" ? length(r.stack) : name=="BL" ? 32 : here(r),
        )
    elseif name in ("PICK", "ROLL")
        index=popdata!(r)
        index<0 && failure("invalid argument", -24)
        length(r.stack)<=index && failure("stack underflow", -4)
        at=length(r.stack)-index
        value=r.stack[at]
        if name=="ROLL"
            deleteat!(r.stack, at)
        end
        pushdata!(r, value)
    elseif name=="."
        value=popdata!(r)
        writepending!(r, formatnumber(r, value)*" ")
    elseif name==".R"
        value, width=takevalues!(r, 2)
        text=formatnumber(r, value)
        writepending!(r, repeat(" ", max(0, width-length(text)))*text)
    elseif name==".S"
        text="<$(formatnumber(r,length(r.stack)))> "
        for value in r.stack
            text*=formatnumber(r, value)*" "
        end
        writepending!(r, text)
    elseif name=="?"
        address=popdata!(r)
        value=r.memory[cell(r, address)]
        writepending!(r, formatnumber(r, value)*" ")
    elseif name=="CR"
        flushline!(r)
    elseif name=="EMIT"
        code=popdata!(r)
        32<=code<=126 || failure("invalid argument", -24)
        writepending!(r, string(Char(code)))
    elseif name=="SPACE"
        writepending!(r, " ")
    elseif name=="SPACES"
        count=popdata!(r)
        writepending!(r, repeat(" ", max(0, count)))
    elseif name in ("!", "+!")
        value, address=takevalues!(r, 2)
        at=cell(r, address)
        r.memory[at]=name=="!" ? value : r.memory[at]+value
    elseif name=="@"
        address=popdata!(r)
        pushdata!(r, r.memory[cell(r, address)])
    elseif name==","
        push!(r.memory, popdata!(r))
    elseif name=="ALLOT"
        count=popdata!(r)
        (count<0 || count%8!=0) && failure("invalid argument", -24)
        append!(r.memory, zeros(Int, div(count, 8)))
    elseif name in ("HEX", "DECIMAL")
        r.memory[1]=name=="HEX" ? 16 : 10
    elseif name in ("CREATE", "VARIABLE", "CONSTANT", "VALUE", "DEFER")
        word=ForthWord(newname!(r), lowercase(name))
        word.address=here(r)
        name in ("CONSTANT", "VALUE") && (word.value=popdata!(r))
        addword!(r, word)
        name in ("VARIABLE", "VALUE") && push!(r.memory, name=="VALUE" ? word.value : 0)
    elseif name=="'"
        word=existing(r, readname!(r))
        pushdata!(r, executiontoken!(r, word))
    elseif name=="EXECUTE"
        word=tokenword(r, popdata!(r))
        executeword!(r, word, word.name)
    elseif name=="CATCH"
        word=tokenword(r, popdata!(r))
        saved=copy(r.stack)
        returnsize=length(r.returns)
        depth=r.depth
        try
            executeword!(r, word, word.name)
        catch error
            error isa ForthFailure || rethrow()
            error.code===nothing && rethrow()
            r.stack=saved
            resize!(r.returns, min(returnsize, length(r.returns)))
            r.depth=depth
            pushdata!(r, error.code)
            return
        end
        pushdata!(r, 0)
    elseif name=="THROW"
        code=popdata!(r)
        code!=0 && failure("exception $code", code)
    elseif name=="ABORT"
        failure("aborted", -1)
    elseif name=="WORDS"
        for word in Iterators.reverse(r.dictionary)
            writepending!(r, word.name*" ")
        end
    end
end
function rundefinition!(r, definition, start)
    r.depth==100 && failure("nesting too deep", -7)
    r.depth+=1
    returnsize=length(r.returns)
    frame=zeros(Int, definition.localcount)
    ip=start
    while ip<=length(definition.body)
        action=definition.body[ip]
        next=ip+1
        op=action.op
        arg=action.argument
        try
            if op=="call"
                executeword!(r, arg, action.token)
            elseif op=="push"
                pushdata!(r, arg)
            elseif op=="local"
                pushdata!(r, frame[arg])
            elseif op==".\""
                writepending!(r, arg)
            elseif op=="branch"
                next=arg
            elseif op=="zbranch"
                popdata!(r)==0 && (next=arg)
            elseif op in ("DO", "?DO")
                limit, index=takevalues!(r, 2)
                if op=="?DO" && limit==index
                    next=arg
                else
                    pushreturn!(r, limit)
                    pushreturn!(r, index)
                end
            elseif op in ("LOOP", "+LOOP")
                step=op=="LOOP" ? 1 : popdata!(r)
                requirereturn(r, 2)
                limit, index=r.returns[(end-1):end]
                if (index-limit<0)!=(index+step-limit<0)
                    resize!(r.returns, length(r.returns)-2)
                else
                    r.returns[end]=index+step
                    next=arg
                end
            elseif op in ("LEAVE", "UNLOOP")
                requirereturn(r, 2)
                resize!(r.returns, length(r.returns)-2)
                op=="LEAVE" && (next=arg)
            elseif op==">R"
                pushreturn!(r, popdata!(r))
            elseif op=="R>"
                requirereturn(r, 1)
                pushdata!(r, pop!(r.returns))
            elseif op in ("R@", "I", "J")
                count=op=="J" ? 3 : 1
                requirereturn(r, count)
                pushdata!(r, r.returns[end-count+1])
            elseif op=="OF"
                selector, candidate=takevalues!(r, 2)
                if selector!=candidate
                    pushdata!(r, selector)
                    next=arg
                end
            elseif op=="ENDCASE"
                popdata!(r)
            elseif op=="ABORT\""
                popdata!(r)!=0 && failure(arg, -2)
            elseif op=="{:"
                values=takevalues!(r, length(arg))
                for (slot, value) in zip(arg, values)
                    frame[slot]=value
                end
            elseif op=="to_local"
                frame[arg]=popdata!(r)
            elseif op=="to_value"
                r.memory[div(arg.address, 8)+1]=popdata!(r)
            elseif op=="IS"
                setdeferred!(r, arg)
            elseif op=="RECURSE"
                rundefinition!(r, arg, 1)
            elseif op=="DOES>"
                (isempty(r.dictionary) || r.dictionary[end].kind!="create") &&
                    failure("no CREATE word", -31)
                r.dictionary[end].does=(definition, arg)
                next=length(definition.body)+1
            elseif op=="EXIT"
                next=length(definition.body)+1
            end
        catch error
            error isa ForthFailure || rethrow()
            error.token===nothing && (error.token=action.token)
            rethrow()
        end
        ip=next
    end
    resize!(r.returns, min(returnsize, length(r.returns)))
    r.depth-=1
end
function addinstruction!(r, op, token, argument = nothing)
    push!(r.compiling.body, Instruction(op, token, argument))
    length(r.compiling.body)
end
function patch!(definition, indices)
    for index in indices
        definition.body[index].argument=length(definition.body)+1
    end
end
function requiretop(r, kinds)
    controls=r.compiling.controls
    (isempty(controls) || !(controls[end].kind in kinds)) && failure("control structure mismatch")
end
function compiletoken!(r, token, name)
    d=r.compiling
    controls=d.controls
    if name=="IF"
        push!(controls, ControlRecord("IF", addinstruction!(r, "zbranch", token), Int[]))
    elseif name=="ELSE"
        requiretop(r, ("IF",))
        index=addinstruction!(r, "branch", token)
        patch!(d, [pop!(controls).origin])
        push!(controls, ControlRecord("ELSE", index, Int[]))
    elseif name=="THEN"
        requiretop(r, ("IF", "ELSE"))
        patch!(d, [pop!(controls).origin])
    elseif name=="BEGIN"
        push!(controls, ControlRecord("BEGIN", length(d.body)+1, Int[]))
    elseif name in ("UNTIL", "AGAIN")
        requiretop(r, ("BEGIN",))
        addinstruction!(r, name=="UNTIL" ? "zbranch" : "branch", token, pop!(controls).origin)
    elseif name=="WHILE"
        requiretop(r, ("BEGIN",))
        index=addinstruction!(r, "zbranch", token)
        controls[end]=ControlRecord("WHILE", controls[end].origin, [index])
    elseif name=="REPEAT"
        requiretop(r, ("WHILE",))
        loop=pop!(controls)
        addinstruction!(r, "branch", token, loop.origin)
        patch!(d, loop.references)
    elseif name in ("DO", "?DO")
        index=addinstruction!(r, name, token)
        push!(controls, ControlRecord(name, index+1, name=="?DO" ? [index] : Int[]))
    elseif name in ("LOOP", "+LOOP")
        requiretop(r, ("DO", "?DO"))
        loop=pop!(controls)
        addinstruction!(r, name, token, loop.origin)
        patch!(d, loop.references)
    elseif name=="LEAVE"
        index=findlast(c->c.kind in ("DO", "?DO"), controls)
        index===nothing && failure("control structure mismatch")
        push!(controls[index].references, addinstruction!(r, "LEAVE", token))
    elseif name=="CASE"
        push!(controls, ControlRecord("CASE", 0, Int[]))
    elseif name=="OF"
        requiretop(r, ("CASE",))
        push!(controls, ControlRecord("OF", addinstruction!(r, "OF", token), Int[]))
    elseif name=="ENDOF"
        requiretop(r, ("OF",))
        index=addinstruction!(r, "branch", token)
        patch!(d, [pop!(controls).origin])
        push!(controls[end].references, index)
    elseif name=="ENDCASE"
        requiretop(r, ("CASE",))
        addinstruction!(r, "ENDCASE", token)
        patch!(d, pop!(controls).references)
    elseif name=="RECURSE"
        addinstruction!(r, "RECURSE", token, d)
    elseif name=="DOES>"
        !isempty(controls) && failure("control structure mismatch")
        addinstruction!(r, "DOES>", token, length(d.body)+2)
    elseif name==";"
        if !isempty(controls)
            kind=controls[end].kind
            kind=kind=="ELSE" ? "IF" : kind=="WHILE" ? "BEGIN" : kind
            failure("unclosed $kind")
        end
        r.compiling=nothing
        word=ForthWord(isempty(d.name) ? ":NONAME" : d.name, "colon")
        word.definition=d
        word.here=d.here
        if isempty(d.name)
            pushdata!(r, executiontoken!(r, word))
        else
            push!(r.dictionary, word)
        end
    elseif name=="[']"
        word=existing(r, readname!(r))
        addinstruction!(r, "push", token, executiontoken!(r, word))
    elseif name=="{:"
        names=String[]
        while true
            word=readword!(r)
            word===nothing && failure("unterminated locals")
            word==":}" && break
            push!(names, word)
        end
        at=findfirst(==("--"), names)
        at!==nothing && resize!(names, at-1)
        for word in names
            checkname(r, word)
        end
        slots=Int[]
        for word in names
            d.localcount+=1
            d.locals[uppercase(word)]=d.localcount
            push!(slots, d.localcount)
        end
        addinstruction!(r, "{:", token, slots)
    elseif name in ("EXIT", ">R", "R>", "R@", "I", "J", "UNLOOP")
        addinstruction!(r, name, token)
    elseif haskey(d.locals, name)
        addinstruction!(r, "local", token, d.locals[name])
    else
        word=findword(r, name)
        word===nothing ? addinstruction!(r, "push", token, literal(r, token)) :
        addinstruction!(r, "call", token, word)
    end
end
function processtoken!(r, token)
    name=uppercase(token)
    compiling=r.compiling!==nothing
    if name=="\\"
        r.position=length(r.line)+1
    elseif name=="("
        at=r.position<=length(r.line) ? findnext(')', r.line, r.position) : nothing
        at===nothing && failure("unterminated comment")
        r.position=at+1
    elseif !compiling && name in COMPILE_ONLY
        failure("compile only")
    elseif compiling && name in INTERPRET_ONLY
        failure("interpret only")
    elseif name in (".\"", "ABORT\"")
        text=readstring!(r)
        compiling ? addinstruction!(r, name, token, text) : writepending!(r, text)
    elseif name in ("TO", "IS")
        raw=readname!(r)
        key=uppercase(raw)
        if name=="TO" && compiling && haskey(r.compiling.locals, key)
            addinstruction!(r, "to_local", token, r.compiling.locals[key])
            return
        end
        word=existing(r, raw)
        word.kind==(name=="TO" ? "value" : "defer") ||
            failure(name=="TO" ? "not a value" : "not deferred", nothing, raw)
        if compiling
            addinstruction!(r, name=="TO" ? "to_value" : "IS", token, word)
        elseif name=="TO"
            r.memory[div(word.address, 8)+1]=popdata!(r)
        else
            setdeferred!(r, word)
        end
    elseif name in (":", ":NONAME")
        raw=name==":" ? readname!(r) : token
        name==":" && checkname(r, raw)
        r.compiling=Definition(name==":" ? uppercase(raw) : "", raw, here(r))
    elseif name=="FORGET"
        raw=readname!(r)
        index=findlast(w->w.name==uppercase(raw), r.dictionary)
        index===nothing && failure("undefined word", -13, raw)
        resize!(r.memory, div(r.dictionary[index].here, 8))
        resize!(r.dictionary, index-1)
    elseif compiling
        compiletoken!(r, token, name)
    else
        word=findword(r, name)
        word===nothing ? pushdata!(r, literal(r, token)) : executeword!(r, word, token)
    end
end
function main()
    r=Interpreter()
    for line in eachline()
        if line=="BYE"
            r.compiling!==nothing &&
                println("ERROR $(r.compiling.display): unterminated definition")
            break
        end
        r.line=line
        r.position=1
        token=""
        try
            while true
                next=readword!(r)
                next===nothing && break
                token=next
                processtoken!(r, token)
            end
        catch error
            error isa ForthFailure || rethrow()
            !isempty(r.pending) && flushline!(r)
            println("ERROR $(error.token===nothing ? token : error.token): $(error.reason)")
            empty!(r.stack)
            empty!(r.returns)
            r.depth=0
            r.compiling=nothing
        end
        !isempty(r.pending) && flushline!(r)
    end
end
main()
