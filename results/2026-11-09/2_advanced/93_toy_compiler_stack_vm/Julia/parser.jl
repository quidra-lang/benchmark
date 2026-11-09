const TYPES = Set(["int","bool","void"])
const OPERATORS = [Set(["||"]),Set(["&&"]),Set(["==","!="]),Set(["<","<=",">",">="]),Set(["+","-"]),Set(["*","/","%"])]
mutable struct ToyNode
    kind::String
    position::ToyPosition
    fields::Dict{Symbol,Any}
end
toy_node(kind,position;fields...) = ToyNode(kind,position,Dict{Symbol,Any}(fields))
function Base.getproperty(node::ToyNode,name::Symbol)
    name in (:kind,:position,:fields) ? getfield(node,name) : getfield(node,:fields)[name]
end
function Base.setproperty!(node::ToyNode,name::Symbol,value)
    name in (:kind,:position,:fields) ? setfield!(node,name,value) : (getfield(node,:fields)[name] = value)
end
function expression_children(node)
    node.kind == "binary" && return [node.left,node.right]
    node.kind == "unary" && return [node.operand]
    node.kind == "array" && return [node.index]
    node.kind == "call" && return node.arguments
    ToyNode[]
end
function statement_children(node)
    node.kind == "block" && return node.statements
    node.kind == "if" && return node.otherwise === nothing ? [node.then] : [node.then,node.otherwise]
    node.kind == "while" && return [node.body]
    node.kind == "for" && return ToyNode[child for child in (node.initial,node.update,node.body) if child !== nothing]
    ToyNode[]
end
mutable struct ToyParser
    tokens::Vector{ToyToken}
    index::Int
end
ToyParser(tokens) = ToyParser(tokens,1)
next_token(parser) = parser.tokens[parser.index]
function syntax_error(parser)
    token = next_token(parser)
    message = token.kind == "end" ? "unexpected end of program" : "unexpected '$(token.spelling)'"
    throw(CompileError("syntax",token.position,message))
end
function take_token!(parser)
    token = next_token(parser)
    parser.index += 1
    token
end
accept_token!(parser,spelling) = next_token(parser).spelling == spelling ? take_token!(parser) : nothing
function expect_token!(parser,spelling)
    next_token(parser).spelling == spelling || syntax_error(parser)
    take_token!(parser)
end
function identifier!(parser)
    next_token(parser).kind == "identifier" || syntax_error(parser)
    take_token!(parser)
end
function declaration_head!(parser)
    next_token(parser).spelling in TYPES || syntax_error(parser)
    type_token,name = take_token!(parser),identifier!(parser)
    type_token.position,(type=type_token.spelling,name=name.spelling,name_position=name.position)
end
function parse_program!(parser)
    declarations = ToyNode[]
    while next_token(parser).kind != "end"
        position,fields = declaration_head!(parser)
        if accept_token!(parser,"(") !== nothing
            parameters = ToyNode[]
            if next_token(parser).spelling != ")"
                while true
                    parameter_position,parameter_fields = declaration_head!(parser)
                    push!(parameters,toy_node("parameter",parameter_position;parameter_fields...))
                    accept_token!(parser,",") === nothing && break
                end
            end
            expect_token!(parser,")")
            push!(declarations,toy_node("function",position;parameters,body=parse_block!(parser),fields...))
        else
            size,size_position,initializer = nothing,nothing,nothing
            if accept_token!(parser,"[") !== nothing
                next_token(parser).kind == "integer" || syntax_error(parser)
                token = take_token!(parser)
                size,size_position = parse(Int,token.spelling),token.position
                expect_token!(parser,"]")
            elseif accept_token!(parser,"=") !== nothing
                initializer = parse_expression!(parser)
            end
            expect_token!(parser,";")
            push!(declarations,toy_node("global",position;size,size_position,initializer,fields...))
        end
    end
    declarations
end
function parse_declaration!(parser;for_initial=false)
    position,fields = declaration_head!(parser)
    initializer = nothing
    if for_initial
        expect_token!(parser,"=")
        initializer = parse_expression!(parser)
    else
        accept_token!(parser,"=") === nothing || (initializer = parse_expression!(parser))
        expect_token!(parser,";")
    end
    toy_node("declaration",position;initializer,fields...)
end
function parse_block!(parser)
    opening = expect_token!(parser,"{")
    statements = ToyNode[]
    while next_token(parser).spelling != "}"
        push!(statements,next_token(parser).spelling in TYPES ? parse_declaration!(parser) : parse_statement!(parser))
    end
    closing = expect_token!(parser,"}")
    toy_node("block",opening.position;statements,end_position=closing.position)
end
function parse_statement!(parser)
    token = next_token(parser)
    spelling = token.spelling
    spelling == "{" && return parse_block!(parser)
    if spelling in ("if","while")
        take_token!(parser)
        expect_token!(parser,"(")
        condition = parse_expression!(parser)
        expect_token!(parser,")")
        body = parse_statement!(parser)
        spelling == "while" && return toy_node("while",token.position;condition,body)
        otherwise = accept_token!(parser,"else") === nothing ? nothing : parse_statement!(parser)
        return toy_node("if",token.position;condition,then=body,otherwise)
    elseif spelling == "for"
        take_token!(parser)
        expect_token!(parser,"(")
        initial = nothing
        if next_token(parser).spelling in TYPES
            initial = parse_declaration!(parser;for_initial=true)
        elseif next_token(parser).spelling != ";"
            initial = parse_simple!(parser)
        end
        expect_token!(parser,";")
        condition = next_token(parser).spelling == ";" ? nothing : parse_expression!(parser)
        expect_token!(parser,";")
        update = next_token(parser).spelling == ")" ? nothing : parse_simple!(parser)
        expect_token!(parser,")")
        return toy_node("for",token.position;initial,condition,update,body=parse_statement!(parser))
    elseif spelling in ("break","continue")
        take_token!(parser)
        expect_token!(parser,";")
        return toy_node(spelling,token.position)
    elseif spelling == "return"
        take_token!(parser)
        value = next_token(parser).spelling == ";" ? nothing : parse_expression!(parser)
        expect_token!(parser,";")
        return toy_node("return",token.position;value)
    elseif spelling == "print"
        take_token!(parser)
        expect_token!(parser,"(")
        arguments = [parse_expression!(parser)]
        while accept_token!(parser,",") !== nothing
            push!(arguments,parse_expression!(parser))
        end
        expect_token!(parser,")")
        expect_token!(parser,";")
        return toy_node("print",token.position;arguments)
    elseif token.kind == "identifier" || spelling == "read"
        result = parse_simple!(parser)
        expect_token!(parser,";")
        return result
    end
    syntax_error(parser)
end
function parse_simple!(parser)
    token = next_token(parser)
    (token.kind == "identifier" || token.spelling == "read") || syntax_error(parser)
    value = parse_primary!(parser)
    value.kind in ("call","read") && return toy_node("call_statement",value.position;expression=value)
    expect_token!(parser,"=")
    toy_node("assignment",value.position;name=value.name,index=value.kind == "array" ? value.index : nothing,value=parse_expression!(parser))
end
function parse_expression!(parser,level=1)
    if level > length(OPERATORS)
        if next_token(parser).spelling in ("-","!")
            operator = take_token!(parser)
            return toy_node("unary",operator.position;operator=operator.spelling,operand=parse_expression!(parser,level))
        end
        return parse_primary!(parser)
    end
    result = parse_expression!(parser,level+1)
    while next_token(parser).spelling in OPERATORS[level]
        operator = take_token!(parser)
        result = toy_node("binary",operator.position;operator=operator.spelling,left=result,right=parse_expression!(parser,level+1))
    end
    result
end
function parse_primary!(parser)
    token = next_token(parser)
    if token.kind == "integer"
        take_token!(parser)
        return toy_node("integer",token.position;value=parse(Int64,token.spelling))
    elseif token.spelling in ("true","false")
        take_token!(parser)
        return toy_node("boolean",token.position;value=token.spelling == "true")
    elseif token.spelling == "read"
        take_token!(parser)
        expect_token!(parser,"(")
        expect_token!(parser,")")
        return toy_node("read",token.position)
    elseif accept_token!(parser,"(") !== nothing
        result = parse_expression!(parser)
        expect_token!(parser,")")
        return result
    elseif token.kind == "identifier"
        take_token!(parser)
        if accept_token!(parser,"(") !== nothing
            arguments = ToyNode[]
            if next_token(parser).spelling != ")"
                push!(arguments,parse_expression!(parser))
                while accept_token!(parser,",") !== nothing
                    push!(arguments,parse_expression!(parser))
                end
            end
            expect_token!(parser,")")
            return toy_node("call",token.position;name=token.spelling,arguments)
        elseif accept_token!(parser,"[") !== nothing
            index = parse_expression!(parser)
            expect_token!(parser,"]")
            return toy_node("array",token.position;name=token.spelling,index)
        end
        return toy_node("variable",token.position;name=token.spelling)
    end
    syntax_error(parser)
end
