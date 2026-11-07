const OPERATORS = Dict("||"=>(1,true),"&&"=>(2,true),"="=>(3,false),"<>"=>(3,false),"<"=>(3,false),">"=>(3,false),"<="=>(3,false),">="=>(3,false),"::"=>(4,true),"^"=>(4,true),"+"=>(5,false),"-"=>(5,false),"*"=>(6,false),"/"=>(6,false),"mod"=>(6,false))
mutable struct MLNode
    kind::String
    position::MLPosition
    children::Vector{MLNode}
    value::Any
    inferred::Union{Nothing,MLType}
end
ml_node(kind,position,children=MLNode[];value=nothing) = MLNode(kind,position,children,value,nothing)
mutable struct Binding
    name::String
    position::MLPosition
    expression::MLNode
    scheme::Union{Nothing,Scheme}
    classification::String
end
Binding(name,expression) = Binding(name.spelling,name.position,expression,nothing,"")
struct BindingGroup
    bindings::Vector{Binding}
    rec_position::Union{Nothing,MLPosition}
end
struct MLItem
    kind::String
    value::Any
end
struct SyntaxFailure <: Exception
    token::MLToken
end
mutable struct MLParser
    tokens::Vector{MLToken}
    index::Int
end
MLParser(tokens) = MLParser(tokens,1)
next_token(parser) = parser.tokens[parser.index]
function accept_token!(parser,kind)
    next_token(parser).kind == kind || return nothing
    token = next_token(parser)
    parser.index += 1
    token
end
function expect_token!(parser,kind)
    token = accept_token!(parser,kind)
    token === nothing && throw(SyntaxFailure(next_token(parser)))
    token
end
function parse_name!(parser)
    is_name(next_token(parser)) || throw(SyntaxFailure(next_token(parser)))
    expect_token!(parser,"identifier")
end
function recover!(parser)
    while !(next_token(parser).kind in (";;","EOF"))
        parser.index += 1
    end
    accept_token!(parser,";;")
end
function parse_item!(parser)
    if accept_token!(parser,"val") !== nothing
        name = parse_name!(parser)
        expect_token!(parser,":")
        declared = parse_type!(parser)
        expect_token!(parser,";;")
        return MLItem("signature",(name,declared))
    end
    opening = accept_token!(parser,"let")
    if opening !== nothing
        group = parse_group!(parser)
        if accept_token!(parser,"in") !== nothing
            result = MLItem("expression",ml_node("let",opening.position,[parse_expression!(parser)];value=group))
        else
            result = MLItem("declaration",group)
        end
    else
        result = MLItem("expression",parse_expression!(parser))
    end
    expect_token!(parser,";;")
    result
end
function parse_group!(parser)
    rec = accept_token!(parser,"rec")
    bindings = [parse_binding!(parser)]
    while accept_token!(parser,"and") !== nothing
        push!(bindings,parse_binding!(parser))
    end
    BindingGroup(bindings,rec === nothing ? nothing : rec.position)
end
function parse_binding!(parser)
    name = parse_name!(parser)
    parameters = MLToken[]
    while next_token(parser).kind == "identifier"
        push!(parameters,expect_token!(parser,"identifier"))
    end
    expect_token!(parser,"=")
    expression = parse_expression!(parser)
    for parameter in reverse(parameters)
        expression = ml_node("fun",parameter.position,[expression];value=parameter)
    end
    Binding(name,expression)
end
function parse_expression!(parser)
    opening = accept_token!(parser,"let")
    if opening !== nothing
        group = parse_group!(parser)
        expect_token!(parser,"in")
        return ml_node("let",opening.position,[parse_expression!(parser)];value=group)
    end
    opening = accept_token!(parser,"fun")
    if opening !== nothing
        parameters = [expect_token!(parser,"identifier")]
        while next_token(parser).kind == "identifier"
            push!(parameters,expect_token!(parser,"identifier"))
        end
        expect_token!(parser,"->")
        expression = parse_expression!(parser)
        for parameter in reverse(parameters)
            expression = ml_node("fun",parameter.position,[expression];value=parameter)
        end
        expression.position = opening.position
        return expression
    end
    opening = accept_token!(parser,"if")
    if opening !== nothing
        condition = parse_expression!(parser)
        expect_token!(parser,"then")
        first = parse_expression!(parser)
        expect_token!(parser,"else")
        second = parse_expression!(parser)
        return ml_node("if",opening.position,[condition,first,second])
    end
    opening = accept_token!(parser,"match")
    if opening !== nothing
        expression = parse_expression!(parser)
        expect_token!(parser,"with")
        accept_token!(parser,"|")
        arms = [parse_arm!(parser)]
        while accept_token!(parser,"|") !== nothing
            push!(arms,parse_arm!(parser))
        end
        return ml_node("match",opening.position,[expression];value=arms)
    end
    parse_binary!(parser,1)
end
function parse_arm!(parser)
    pattern = parse_pattern!(parser)
    expect_token!(parser,"->")
    pattern,parse_expression!(parser)
end
function parse_binary!(parser,minimum)
    expression = parse_unary!(parser)
    while haskey(OPERATORS,next_token(parser).kind)
        precedence,right_associative = OPERATORS[next_token(parser).kind]
        precedence < minimum && break
        operator = next_token(parser)
        parser.index += 1
        right = parse_binary!(parser,right_associative ? precedence : precedence+1)
        expression = ml_node("binary",expression.position,[expression,right];value=operator)
    end
    expression
end
starts_atom(parser) = next_token(parser).kind in ("integer","string","true","false","(","[") || is_name(next_token(parser))
function parse_unary!(parser)
    operator = accept_token!(parser,"-")
    operator === nothing || return ml_node("negate",operator.position,[parse_unary!(parser)];value=operator)
    expression = parse_atom!(parser)
    while starts_atom(parser)
        expression = ml_node("apply",expression.position,[expression,parse_atom!(parser)])
    end
    expression
end
function parse_atom!(parser)
    token = next_token(parser)
    if token.kind in ("integer","string")
        parser.index += 1
        return ml_node(token.kind,token.position;value=token.value)
    elseif token.kind in ("true","false")
        parser.index += 1
        return ml_node("boolean",token.position;value=token.kind == "true")
    elseif is_name(token)
        parser.index += 1
        return ml_node("name",token.position;value=token.spelling)
    elseif accept_token!(parser,"(") !== nothing
        first = parse_expression!(parser)
        if accept_token!(parser,",") !== nothing
            second = parse_expression!(parser)
            expect_token!(parser,")")
            return ml_node("pair",token.position,[first,second])
        end
        expect_token!(parser,")")
        return first
    elseif accept_token!(parser,"[") !== nothing
        elements = MLNode[]
        if accept_token!(parser,"]") === nothing
            push!(elements,parse_expression!(parser))
            while accept_token!(parser,";") !== nothing
                push!(elements,parse_expression!(parser))
            end
            expect_token!(parser,"]")
        end
        return ml_node("list",token.position,elements)
    end
    throw(SyntaxFailure(token))
end
function parse_pattern!(parser)
    first = parse_pattern_atom!(parser)
    accept_token!(parser,"::") === nothing ? first : ml_node("cons",first.position,[first,parse_pattern!(parser)])
end
function parse_pattern_atom!(parser)
    token = next_token(parser)
    if token.kind == "identifier"
        parser.index += 1
        return ml_node(token.spelling == "_" ? "wildcard" : "name",token.position;value=token.spelling)
    elseif accept_token!(parser,"-") !== nothing
        integer = expect_token!(parser,"integer")
        return ml_node("integer",token.position;value=-integer.value)
    elseif token.kind in ("integer","string","true","false")
        return parse_atom!(parser)
    elseif accept_token!(parser,"(") !== nothing
        first = parse_pattern!(parser)
        if accept_token!(parser,",") !== nothing
            second = parse_pattern!(parser)
            expect_token!(parser,")")
            return ml_node("pair",token.position,[first,second])
        end
        expect_token!(parser,")")
        return first
    elseif accept_token!(parser,"[") !== nothing
        elements = MLNode[]
        if accept_token!(parser,"]") === nothing
            push!(elements,parse_pattern!(parser))
            while accept_token!(parser,";") !== nothing
                push!(elements,parse_pattern!(parser))
            end
            expect_token!(parser,"]")
        end
        return ml_node("list",token.position,elements)
    end
    throw(SyntaxFailure(token))
end
function parse_type!(parser)
    first = parse_list_type!(parser)
    if accept_token!(parser,"*") !== nothing
        first = ml_node("pair",first.position,[first,parse_list_type!(parser)])
    end
    if accept_token!(parser,"->") !== nothing
        first = ml_node("function",first.position,[first,parse_type!(parser)])
    end
    first
end
function parse_list_type!(parser)
    expression = parse_type_atom!(parser)
    while next_token(parser).kind == "identifier" && next_token(parser).spelling == "list"
        parser.index += 1
        expression = ml_node("list",expression.position,[expression])
    end
    expression
end
function parse_type_atom!(parser)
    token = next_token(parser)
    if token.kind == "identifier" && token.spelling in ("int","bool","string")
        parser.index += 1
        return ml_node(token.spelling,token.position)
    elseif accept_token!(parser,"type_variable") !== nothing
        return ml_node("type_variable",token.position;value=token.spelling)
    elseif accept_token!(parser,"(") !== nothing
        expression = parse_type!(parser)
        expect_token!(parser,")")
        return expression
    end
    throw(SyntaxFailure(token))
end
