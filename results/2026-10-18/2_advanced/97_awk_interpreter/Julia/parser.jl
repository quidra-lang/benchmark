const ASSIGNMENTS = Set(["=","+=","-=","*=","/=","%=","^="])
const COMPARISONS = Set(["<","<=","==","!=",">=",">"])
const LVALUE_KINDS = Set(["name","array","field"])
const STATEMENTS = Set(["if","while","do","for","for_in","print","printf","delete","next","break","continue","exit","return","expression_statement"])

mutable struct AwkNode
    kind::String
    position::Tuple{Int,Int}
    children::Vector{AwkNode}
    attributes::Dict{Symbol,Any}
end
function awk_node(kind,position,children=AwkNode[];kwargs...)
    AwkNode(kind,position,AwkNode[child for child in children if child !== nothing],Dict{Symbol,Any}(kwargs))
end
function Base.getproperty(node::AwkNode,name::Symbol)
    name in (:kind,:position,:children,:attributes) && return getfield(node,name)
    get(getfield(node,:attributes),name,nothing)
end
function Base.setproperty!(node::AwkNode,name::Symbol,value)
    if name in (:kind,:position,:children,:attributes)
        setfield!(node,name,value)
    else
        getfield(node,:attributes)[name] = value
    end
end
mutable struct AwkParser
    tokens::Vector{AwkToken}
    index::Int
    in_function::Bool
    phase::Union{Nothing,String}
    loop_depth::Int
end
AwkParser(tokens) = AwkParser(tokens,1,false,nothing,0)
current_token(parser) = parser.tokens[parser.index]
function take_token!(parser)
    token = current_token(parser)
    parser.index += 1
    token
end
syntax_error(parser,position=current_token(parser).position) = throw(SyntaxIssue(position))
accept_token!(parser,spelling) = current_token(parser).spelling == spelling ? take_token!(parser) : nothing
function expect_token!(parser,spelling)
    current_token(parser).spelling == spelling || syntax_error(parser)
    take_token!(parser)
end
function parse_name!(parser)
    current_token(parser).kind == "name" || syntax_error(parser)
    token = take_token!(parser)
    awk_node("name",token.position;name=token.spelling)
end
function skip_newlines!(parser)
    while accept_token!(parser,"\n") !== nothing
    end
end
function parse_program!(parser)
    items = AwkNode[]
    while current_token(parser).kind != "end"
        if current_token(parser).spelling in ("\n",";")
            take_token!(parser)
            continue
        end
        opening = current_token(parser)
        if accept_token!(parser,"function") !== nothing
            current_token(parser).kind in ("name","function_name") || syntax_error(parser)
            name = take_token!(parser)
            expect_token!(parser,"(")
            parameters = AwkNode[]
            if current_token(parser).spelling != ")"
                while true
                    parameter = parse_name!(parser)
                    parameter.kind = "parameter"
                    push!(parameters,parameter)
                    accept_token!(parser,",") === nothing && break
                    skip_newlines!(parser)
                end
            end
            expect_token!(parser,")")
            skip_newlines!(parser)
            parser.in_function = true
            body = parse_block!(parser)
            parser.in_function = false
            push!(items,awk_node("function",opening.position,[parameters;[body]];name=name.spelling,name_position=name.position,parameters=parameters,body=body))
            continue
        end
        patterns = AwkNode[]
        if opening.spelling in ("BEGIN","END")
            flavor = take_token!(parser).spelling
        elseif opening.spelling == "{"
            flavor = "all"
        else
            push!(patterns,parse_expression!(parser))
            if accept_token!(parser,",") !== nothing
                skip_newlines!(parser)
                push!(patterns,parse_expression!(parser))
            end
            flavor = length(patterns) == 2 ? "range" : "pattern"
        end
        parser.phase = flavor
        if flavor in ("BEGIN","END","all") || current_token(parser).spelling == "{"
            action = parse_block!(parser)
        else
            (current_token(parser).spelling in ("\n",";") || current_token(parser).kind == "end") || syntax_error(parser)
            action = nothing
        end
        parser.phase = nothing
        push!(items,awk_node("rule",opening.position,[patterns;[action]];flavor=flavor,patterns=patterns,action=action))
    end
    items
end
function parse_block!(parser)
    opening = expect_token!(parser,"{")
    statements = AwkNode[]
    while current_token(parser).spelling != "}"
        if current_token(parser).spelling in ("\n",";")
            take_token!(parser)
        else
            push!(statements,parse_statement!(parser))
        end
    end
    expect_token!(parser,"}")
    awk_node("block",opening.position,statements;statements=statements)
end
function parse_condition!(parser)
    expect_token!(parser,"(")
    value = parse_expression!(parser)
    expect_token!(parser,")")
    value
end
function parse_loop_body!(parser)
    skip_newlines!(parser)
    parser.loop_depth += 1
    body = parse_statement!(parser)
    parser.loop_depth -= 1
    body
end
function parse_terminator!(parser)
    if current_token(parser).spelling in (";","\n")
        take_token!(parser)
    elseif current_token(parser).spelling != "}"
        syntax_error(parser)
    end
end
function parse_statement!(parser)
    token = current_token(parser)
    spelling = token.spelling
    spelling == "{" && return parse_block!(parser)
    accept_token!(parser,";") !== nothing && return awk_node("empty",token.position)
    if accept_token!(parser,"if") !== nothing
        condition = parse_condition!(parser)
        skip_newlines!(parser)
        first = parse_statement!(parser)
        skip_newlines!(parser)
        second = nothing
        if accept_token!(parser,"else") !== nothing
            skip_newlines!(parser)
            second = parse_statement!(parser)
        end
        return awk_node("if",token.position,[condition,first,second];condition=condition,first=first,second=second)
    elseif accept_token!(parser,"while") !== nothing
        condition = parse_condition!(parser)
        body = parse_loop_body!(parser)
        return awk_node("while",token.position,[condition,body];condition=condition,body=body)
    elseif accept_token!(parser,"do") !== nothing
        body = parse_loop_body!(parser)
        skip_newlines!(parser)
        expect_token!(parser,"while")
        condition = parse_condition!(parser)
        parse_terminator!(parser)
        return awk_node("do",token.position,[body,condition];body=body,condition=condition)
    elseif accept_token!(parser,"for") !== nothing
        expect_token!(parser,"(")
        index = parser.index
        if index+3 <= length(parser.tokens) && parser.tokens[index].kind == "name" && parser.tokens[index+1].spelling == "in" && parser.tokens[index+2].kind == "name" && parser.tokens[index+3].spelling == ")"
            variable = parse_name!(parser)
            expect_token!(parser,"in")
            array = parse_name!(parser)
            expect_token!(parser,")")
            body = parse_loop_body!(parser)
            return awk_node("for_in",token.position,[variable,array,body];variable=variable,array=array,body=body)
        end
        initial = current_token(parser).spelling == ";" ? nothing : parse_expression!(parser)
        expect_token!(parser,";")
        skip_newlines!(parser)
        condition = current_token(parser).spelling == ";" ? nothing : parse_expression!(parser)
        expect_token!(parser,";")
        skip_newlines!(parser)
        update = current_token(parser).spelling == ")" ? nothing : parse_expression!(parser)
        expect_token!(parser,")")
        body = parse_loop_body!(parser)
        return awk_node("for",token.position,[initial,condition,update,body];initial=initial,condition=condition,update=update,body=body)
    end
    if spelling in ("print","printf")
        take_token!(parser)
        result = parse_output!(parser,token)
    elseif spelling == "delete"
        take_token!(parser)
        array = parse_name!(parser)
        indexes = nothing
        if accept_token!(parser,"[") !== nothing
            indexes = parse_expression_list!(parser)
            expect_token!(parser,"]")
        end
        result = awk_node("delete",token.position,[array;indexes === nothing ? AwkNode[] : indexes];array=array,indexes=indexes)
    elseif spelling in ("next","break","continue","exit","return")
        take_token!(parser)
        spelling == "next" && !parser.in_function && parser.phase in ("BEGIN","END") && syntax_error(parser,token.position)
        spelling == "return" && !parser.in_function && syntax_error(parser,token.position)
        spelling in ("break","continue") && parser.loop_depth == 0 && syntax_error(parser,token.position)
        value = spelling in ("exit","return") && !(current_token(parser).spelling in (";","\n","}")) ? parse_expression!(parser) : nothing
        result = awk_node(spelling,token.position,[value];value=value)
    else
        expression = parse_expression!(parser)
        result = awk_node("expression_statement",token.position,[expression];expression=expression)
    end
    parse_terminator!(parser)
    result
end
function parenthesized_output(parser)
    current_token(parser).spelling == "(" || return false
    depth = 0
    for index in parser.index:length(parser.tokens)-1
        spelling = parser.tokens[index].spelling
        if spelling == "("
            depth += 1
        elseif spelling == ")"
            depth -= 1
            if depth == 0
                following = parser.tokens[index+1]
                return following.spelling in (";","\n","}",">",">>") || following.kind == "end"
            end
        end
    end
    false
end
function parse_output!(parser,token)
    arguments = AwkNode[]
    if parenthesized_output(parser)
        expect_token!(parser,"(")
        arguments = parse_expression_list!(parser)
        expect_token!(parser,")")
    elseif !(current_token(parser).spelling in (";","\n","}",">",">>"))
        arguments = parse_expression_list!(parser,false)
    end
    token.spelling == "printf" && isempty(arguments) && syntax_error(parser)
    redirect = current_token(parser).spelling in (">",">>") ? take_token!(parser) : nothing
    filename = redirect === nothing ? nothing : parse_concatenation!(parser)
    awk_node(token.spelling,token.position,[arguments;[filename]];
        arguments=arguments,redirect=redirect === nothing ? nothing : redirect.spelling,
        redirect_position=redirect === nothing ? nothing : redirect.position,filename=filename)
end
function parse_expression_list!(parser,greater=true)
    result = AwkNode[parse_expression!(parser,greater)]
    while accept_token!(parser,",") !== nothing
        skip_newlines!(parser)
        push!(result,parse_expression!(parser,greater))
    end
    result
end
function parse_expression!(parser,greater=true)
    left = parse_conditional!(parser,greater)
    if left.kind in LVALUE_KINDS && current_token(parser).spelling in ASSIGNMENTS
        operator = take_token!(parser)
        right = parse_expression!(parser,greater)
        return awk_node("assignment",operator.position,[left,right];operator=operator.spelling,location=left,value=right)
    end
    left
end
function parse_conditional!(parser,greater)
    condition = parse_logical!(parser,0,greater)
    operator = accept_token!(parser,"?")
    operator === nothing && return condition
    first = parse_conditional!(parser,greater)
    expect_token!(parser,":")
    second = parse_conditional!(parser,greater)
    awk_node("conditional",operator.position,[condition,first,second];condition=condition,first=first,second=second)
end
binary_node(operator,left,right) = awk_node("binary",operator.position,[left,right];operator=operator.spelling,left=left,right=right)
function parse_logical!(parser,level,greater)
    level == 2 && return parse_membership!(parser,greater)
    spelling = level == 0 ? "||" : "&&"
    left = parse_logical!(parser,level+1,greater)
    while current_token(parser).spelling == spelling
        operator = take_token!(parser)
        skip_newlines!(parser)
        left = binary_node(operator,left,parse_logical!(parser,level+1,greater))
    end
    left
end
function parse_membership!(parser,greater)
    left = parse_comparison!(parser,greater)
    while current_token(parser).spelling == "in"
        operator = take_token!(parser)
        array = parse_name!(parser)
        left = awk_node("membership",operator.position,[left,array];indexes=[left],array=array)
    end
    left
end
function parse_comparison!(parser,greater)
    left = parse_concatenation!(parser)
    while current_token(parser).spelling in COMPARISONS && (greater || current_token(parser).spelling != ">")
        operator = take_token!(parser)
        left = binary_node(operator,left,parse_concatenation!(parser))
    end
    left
end
function parse_concatenation!(parser)
    left = parse_additive!(parser)
    while current_token(parser).kind in ("number","string","name","function_name","builtin") || current_token(parser).spelling in ("\$","(","++","--")
        position = current_token(parser).position
        right = parse_additive!(parser)
        left = awk_node("binary",position,[left,right];operator="concat",left=left,right=right)
    end
    left
end
function parse_additive!(parser)
    left = parse_multiplicative!(parser)
    while current_token(parser).spelling in ("+","-")
        operator = take_token!(parser)
        left = binary_node(operator,left,parse_multiplicative!(parser))
    end
    left
end
function parse_multiplicative!(parser)
    left = parse_unary!(parser)
    while current_token(parser).spelling in ("*","/","%")
        operator = take_token!(parser)
        left = binary_node(operator,left,parse_unary!(parser))
    end
    left
end
function parse_unary!(parser)
    if current_token(parser).spelling in ("!","-","+")
        operator = take_token!(parser)
        operand = parse_unary!(parser)
        return awk_node("unary",operator.position,[operand];operator=operator.spelling,operand=operand)
    end
    left = parse_postfix!(parser)
    if current_token(parser).spelling == "^"
        operator = take_token!(parser)
        left = binary_node(operator,left,parse_unary!(parser))
    end
    left
end
function parse_prefix!(parser)
    operator = take_token!(parser)
    location = parse_lvalue!(parser)
    awk_node("increment",operator.position,[location];location=location,delta=operator.spelling == "++" ? 1 : -1,prefix=true)
end
function parse_postfix!(parser)
    current_token(parser).spelling in ("++","--") && return parse_prefix!(parser)
    left = parse_atom!(parser)
    if left.kind in LVALUE_KINDS && current_token(parser).spelling in ("++","--")
        operator = take_token!(parser)
        return awk_node("increment",operator.position,[left];location=left,delta=operator.spelling == "++" ? 1 : -1,prefix=false)
    end
    left
end
function parse_lvalue!(parser)
    if current_token(parser).kind == "name"
        node = parse_name!(parser)
        if accept_token!(parser,"[") !== nothing
            indexes = parse_expression_list!(parser)
            expect_token!(parser,"]")
            return awk_node("array",node.position,indexes;name=node.name,indexes=indexes)
        end
        return node
    end
    dollar = accept_token!(parser,"\$")
    if dollar !== nothing
        index = current_token(parser).spelling in ("++","--") ? parse_prefix!(parser) : parse_atom!(parser)
        return awk_node("field",dollar.position,[index];index=index)
    end
    syntax_error(parser)
end
function parse_atom!(parser)
    token = current_token(parser)
    if token.kind in ("number","string")
        take_token!(parser)
        return awk_node(token.kind,token.position;value=token.value)
    elseif token.kind == "name" || token.spelling == "\$"
        return parse_lvalue!(parser)
    elseif accept_token!(parser,"(") !== nothing
        expressions = parse_expression_list!(parser)
        expect_token!(parser,")")
        length(expressions) == 1 && return awk_node("paren",token.position,expressions;expression=expressions[1])
        expect_token!(parser,"in")
        array = parse_name!(parser)
        return awk_node("membership",token.position,[expressions;[array]];indexes=expressions,array=array)
    elseif token.kind in ("function_name","builtin")
        take_token!(parser)
        arguments = AwkNode[]
        if accept_token!(parser,"(") !== nothing
            current_token(parser).spelling != ")" && (arguments = parse_expression_list!(parser))
            expect_token!(parser,")")
        elseif token.kind == "function_name" || token.spelling != "length"
            syntax_error(parser)
        end
        kind = token.kind == "function_name" ? "call" : "builtin"
        kind == "builtin" && check_builtin(parser,token,arguments)
        return awk_node(kind,token.position,arguments;name=token.spelling,arguments=arguments)
    elseif accept_token!(parser,"getline") !== nothing
        target = current_token(parser).kind == "name" || current_token(parser).spelling == "\$" ? parse_lvalue!(parser) : nothing
        filename = accept_token!(parser,"<") !== nothing ? parse_atom!(parser) : nothing
        return awk_node("getline",token.position,[target,filename];target=target,filename=filename)
    end
    syntax_error(parser)
end
function check_builtin(parser,token,arguments)
    count,name = length(arguments),token.spelling
    valid = name == "length" ? count in (0,1) : name in ("substr","split") ? count in (2,3) : name == "index" ? count == 2 : name == "sprintf" ? count >= 1 : count == 1
    (!valid || (name == "split" && arguments[2].kind != "name")) && syntax_error(parser,token.position)
end
