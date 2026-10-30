const SYMBOLS = Set("+-*/\\^<>=~:.?@#&\$")
const INFIX = let table = Dict{String,Tuple{Int,Int,Int}}()
    for (priority,kind,names) in ((1200,"xfx",[":-"]),(1100,"xfy",[";"]),(1050,"xfy",["->"]),(1000,"xfy",[","]),
        (700,"xfx",["=","\\=","==","\\==","is","=:=","=\\=","<",">","=<",">=","=.."]),
        (500,"yfx",["+","-"]),(400,"yfx",["*","/","//","mod","rem"]))
        for name in names
            table[name] = (priority,kind == "yfx" ? priority : priority-1,kind == "xfy" ? priority : priority-1)
        end
    end
    table
end
const PREFIX = Dict("\\+"=>900,"-"=>200)
struct PrologToken
    kind::String
    value::Union{Nothing,Int,String}
    spelling::String
    line::Int
    column::Int
    space::Bool
    index::Int
end
struct PrologSyntaxError <: Exception
    token::PrologToken
    message::String
end
function syntax_error(token,message=nothing)
    if message === nothing
        message = if token.kind == "invalid"
            token.value
        elseif token.kind == "eof"
            "unexpected end of file"
        elseif token.kind == "end"
            "unexpected end of clause"
        elseif token.kind == "name" && haskey(INFIX,token.value)
            "operator priority clash"
        else
            "unexpected \"$(token.spelling)\""
        end
    end
    throw(PrologSyntaxError(token,message))
end
lowercase_letter(character) = 'a' <= character <= 'z'
uppercase_letter(character) = 'A' <= character <= 'Z'
digit(character) = '0' <= character <= '9'
alphanumeric(character) = lowercase_letter(character) || uppercase_letter(character) || digit(character) || character == '_'
function tokenize(text,column=1)
    tokens = PrologToken[]
    position,line,space = 1,1,true
    while position <= length(text)
        character = text[position]
        if character in (' ','\n')
            if character == '\n'
                line,column = line+1,1
            else
                column += 1
            end
            position += 1
            space = true
            continue
        elseif character == '%'
            while position <= length(text) && text[position] != '\n'
                position += 1
                column += 1
            end
            space = true
            continue
        end
        beginning,start_column = position,column
        if digit(character)
            position += 1
            while position <= length(text) && digit(text[position])
                position += 1
            end
            integer = parse(BigInt,text[beginning:position-1])
            kind,value = integer > 2147483647 ? ("invalid","integer too large") : ("integer",Int(integer))
        elseif lowercase_letter(character) || uppercase_letter(character) || character == '_'
            position += 1
            while position <= length(text) && alphanumeric(text[position])
                position += 1
            end
            value = text[beginning:position-1]
            kind = lowercase_letter(character) ? "name" : "variable"
        elseif character in SYMBOLS
            position += 1
            while position <= length(text) && text[position] in SYMBOLS
                position += 1
            end
            value = text[beginning:position-1]
            kind = value == "." && (position > length(text) || text[position] in (' ','\n','%')) ? "end" : "name"
        elseif character in ('!',';')
            kind,value = "name",string(character)
            position += 1
        elseif character in (',','|','(',')','[',']')
            kind,value = "punct",string(character)
            position += 1
        elseif character == '\''
            position += 1
            represented = Char[]
            incorrect = false
            while true
                if position > length(text) || text[position] == '\n'
                    kind,value = "invalid","unterminated quoted atom"
                    break
                end
                current = text[position]
                if current == '\''
                    if position < length(text) && text[position+1] == '\''
                        push!(represented,'\'')
                        position += 2
                    else
                        position += 1
                        kind,value = incorrect ? ("invalid","undefined escape sequence") : ("quoted",join(represented))
                        break
                    end
                elseif current == '\\'
                    position += 1
                    if position <= length(text) && text[position] != '\n'
                        escaped = text[position]
                        !(escaped in ('n','t','\\','\'')) && (incorrect = true)
                        push!(represented,escaped == 'n' ? '\n' : escaped == 't' ? '\t' : escaped)
                        position += 1
                    end
                else
                    push!(represented,current)
                    position += 1
                end
            end
        else
            kind,value = "invalid","illegal character '$character'"
            position += 1
        end
        push!(tokens,PrologToken(kind,value,text[beginning:position-1],line,start_column,space,length(tokens)+1))
        column += position-beginning
        space = false
    end
    push!(tokens,PrologToken("eof",nothing,"",line,column,space,length(tokens)+1))
    tokens
end
mutable struct PrologReader
    tokens::Vector{PrologToken}
    index::Int
    names::Dict{String,VariableTerm}
    name_order::Vector{String}
    counts::Dict{String,Int}
    count_order::Vector{String}
end
PrologReader(text,column=1) = PrologReader(tokenize(text,column),1,Dict{String,VariableTerm}(),String[],Dict{String,Int}(),String[])
reader_token(reader) = reader.tokens[reader.index]
function take_token!(reader)
    token = reader_token(reader)
    token.kind != "eof" && (reader.index += 1)
    token
end
punctuation(reader,spelling) = reader_token(reader).kind == "punct" && reader_token(reader).value == spelling
function expect_punctuation!(reader,spelling)
    token = take_token!(reader)
    token.kind == "punct" && token.value == spelling || syntax_error(token)
end
function read_clause!(reader,query=false)
    empty!(reader.names)
    empty!(reader.name_order)
    empty!(reader.counts)
    empty!(reader.count_order)
    term,_ = read_term!(reader,1200)
    token = take_token!(reader)
    token.kind == "end" || syntax_error(token)
    query && reader_token(reader).kind != "eof" && syntax_error(reader_token(reader))
    term
end
function read_term!(reader,limit)
    term,priority = read_primary!(reader,limit)
    while true
        token = reader_token(reader)
        operator = (token.kind == "name" && haskey(INFIX,token.value)) || (token.kind == "punct" && token.value == ",")
        operator || return term,priority
        p,left,right = INFIX[token.value]
        (p > limit || priority > left) && return term,priority
        take_token!(reader)
        argument,_ = read_term!(reader,right)
        term,priority = compound(token.value,term,argument),p
    end
end
function can_start(reader)
    token = reader_token(reader)
    token.kind in ("integer","variable","quoted") || (token.kind == "punct" && token.value in ("(","[")) ||
        (token.kind == "name" && (!haskey(INFIX,token.value) || haskey(PREFIX,token.value)))
end
function read_primary!(reader,limit)
    token = take_token!(reader)
    token.kind == "integer" && return IntegerTerm(token.value),0
    if token.kind == "variable"
        name = token.value
        !haskey(reader.counts,name) && push!(reader.count_order,name)
        reader.counts[name] = get(reader.counts,name,0)+1
        name == "_" && return VariableTerm(),0
        if !haskey(reader.names,name)
            reader.names[name] = VariableTerm()
            push!(reader.name_order,name)
        end
        return reader.names[name],0
    elseif token.kind == "punct" && token.value == "("
        term,_ = read_term!(reader,1200)
        expect_punctuation!(reader,")")
        return term,0
    elseif token.kind == "punct" && token.value == "["
        if punctuation(reader,"]")
            take_token!(reader)
            return NIL,0
        end
        elements = PrologTerm[read_term!(reader,999)[1]]
        while punctuation(reader,",")
            take_token!(reader)
            push!(elements,read_term!(reader,999)[1])
        end
        tail = NIL
        if punctuation(reader,"|")
            take_token!(reader)
            tail = read_term!(reader,999)[1]
        end
        expect_punctuation!(reader,"]")
        return make_list(elements,tail),0
    elseif token.kind in ("name","quoted")
        if punctuation(reader,"(") && !reader_token(reader).space
            take_token!(reader)
            arguments = PrologTerm[read_term!(reader,999)[1]]
            while punctuation(reader,",")
                take_token!(reader)
                push!(arguments,read_term!(reader,999)[1])
            end
            expect_punctuation!(reader,")")
            return CompoundTerm(token.value,arguments),0
        elseif token.kind == "name" && token.value == "-" && reader_token(reader).kind == "integer" && !reader_token(reader).space
            return IntegerTerm(-take_token!(reader).value),0
        elseif token.kind == "name" && haskey(PREFIX,token.value) && can_start(reader)
            priority = PREFIX[token.value]
            priority > limit && syntax_error(token,"operator priority clash")
            return compound(token.value,read_term!(reader,priority)[1]),priority
        end
        return AtomTerm(token.value),0
    end
    syntax_error(token)
end
