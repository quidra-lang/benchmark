const LEVELS = [Set(["||"]),Set(["&&"]),Set(["|"]),Set(["^"]),Set(["&"]),Set(["==","!="]),Set(["<",">","<=",">="]),Set(["<<",">>"]),Set(["+","-"]),Set(["*","/","%"])]
struct ExpressionError <: Exception
    message::String
end
function integer_value(spelling)
    value = spelling
    for suffix in ("ll","LL","l","L")
        if endswith(value,suffix) && length(value) > length(suffix)
            value = value[1:end-length(suffix)]
            break
        end
    end
    occursin(r"^0[xX][0-9a-fA-F]+$",value) && return parse(Int64,value[3:end];base=16)
    occursin(r"^0[0-7]*$",value) && return parse(Int64,value;base=8)
    occursin(r"^[1-9][0-9]*$",value) && return parse(Int64,value)
    throw(ExpressionError("invalid integer constant \"$spelling\""))
end
function character_value(spelling)
    value = spelling[2:end-1]
    length(value) == 1 && !(value[1] in ('\'','\\')) && return Int64(value[1])
    escapes = Dict('n'=>10,'t'=>9,'\\'=>92,'\''=>39,'"'=>34,'0'=>0)
    length(value) == 2 && value[1] == '\\' && haskey(escapes,value[2]) && return Int64(escapes[value[2]])
    throw(ExpressionError("invalid character constant " * spelling))
end
struct PPExpression
    kind::String
    value::Any
    children::Vector{PPExpression}
end
pp_expression(kind,value=nothing,children=PPExpression[]) = PPExpression(kind,value,children)
mutable struct ExpressionParser
    tokens::Vector{PPToken}
    index::Int
end
next_spelling(parser) = parser.index <= length(parser.tokens) ? parser.tokens[parser.index].spelling : nothing
function parse_conditional!(parser)
    left = parse_binary!(parser,1)
    if next_spelling(parser) == "?"
        parser.index += 1
        first = parse_conditional!(parser)
        next_spelling(parser) == ":" || throw(ExpressionError("'?' without following ':'"))
        parser.index += 1
        left = pp_expression("conditional",nothing,[left,first,parse_conditional!(parser)])
    end
    left
end
function parse_binary!(parser,level)
    level > length(LEVELS) && return parse_unary!(parser)
    left = parse_binary!(parser,level+1)
    while next_spelling(parser) in LEVELS[level]
        operator = next_spelling(parser)
        parser.index += 1
        left = pp_expression("binary",operator,[left,parse_binary!(parser,level+1)])
    end
    left
end
function parse_unary!(parser)
    if next_spelling(parser) in ("+","-","!","~")
        operator = next_spelling(parser)
        parser.index += 1
        return pp_expression("unary",operator,[parse_unary!(parser)])
    end
    parser.index > length(parser.tokens) && throw(ExpressionError("expected value at end of expression"))
    token = parser.tokens[parser.index]
    parser.index += 1
    token.kind == "number" && return pp_expression("constant",integer_value(token.spelling))
    token.kind == "character" && return pp_expression("constant",character_value(token.spelling))
    token.kind == "identifier" && return pp_expression("identifier",token.spelling)
    if token.spelling == "("
        value = parse_conditional!(parser)
        next_spelling(parser) == ")" || throw(ExpressionError("missing ')' in expression"))
        parser.index += 1
        return value
    end
    throw(ExpressionError("expected value before \"$(token.spelling)\""))
end
function parse_expression(tokens,directive)
    isempty(tokens) && throw(ExpressionError("#$directive with no expression"))
    parser = ExpressionParser(tokens,1)
    tree = parse_conditional!(parser)
    next_spelling(parser) === nothing || throw(ExpressionError("missing binary operator before \"$(next_spelling(parser))\""))
    tree
end
function binary_value(operator,first,second)
    if operator in ("/","%")
        second == 0 && throw(ExpressionError("division by zero in #if"))
        return operator == "/" ? div(first,second) : rem(first,second)
    end
    operator == "+" && return first+second
    operator == "-" && return first-second
    operator == "*" && return first*second
    operator == "<<" && return first << second
    operator == ">>" && return first >> second
    operator == "&" && return first & second
    operator == "|" && return first | second
    operator == "^" && return xor(first,second)
    operator == "==" && return Int64(first == second)
    operator == "!=" && return Int64(first != second)
    operator == "<" && return Int64(first < second)
    operator == ">" && return Int64(first > second)
    operator == "<=" ? Int64(first <= second) : Int64(first >= second)
end
function evaluate_expression(tree,warning)
    pending,values = Tuple{String,Any}[("evaluate",tree)],Int64[]
    while !isempty(pending)
        operation,item = pop!(pending)
        if operation == "evaluate"
            kind = item.kind
            if kind == "constant"
                push!(values,item.value)
            elseif kind == "identifier"
                warning("identifier \"$(item.value)\" evaluates to 0")
                push!(values,0)
            elseif kind == "unary"
                append!(pending,[("unary",item.value),("evaluate",item.children[1])])
            elseif kind == "conditional"
                append!(pending,[("choose",(item.children[2],item.children[3])),("evaluate",item.children[1])])
            elseif item.value in ("&&","||")
                append!(pending,[("logical",(item.value,item.children[2])),("evaluate",item.children[1])])
            else
                append!(pending,[("binary",item.value),("evaluate",item.children[2]),("evaluate",item.children[1])])
            end
        elseif operation == "choose"
            push!(pending,("evaluate",item[pop!(values) != 0 ? 1 : 2]))
        elseif operation == "logical"
            first = pop!(values)
            if (item[1] == "&&" && first == 0) || (item[1] == "||" && first != 0)
                push!(values,Int64(first != 0))
            else
                append!(pending,[("truth",nothing),("evaluate",item[2])])
            end
        elseif operation == "truth"
            push!(values,Int64(pop!(values) != 0))
        elseif operation == "unary"
            value = pop!(values)
            push!(values,item == "+" ? value : item == "-" ? -value : item == "!" ? Int64(value == 0) : -value-1)
        else
            second,first = pop!(values),pop!(values)
            push!(values,binary_value(item,first,second))
        end
    end
    values[1]
end
