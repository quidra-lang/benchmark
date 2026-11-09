const PRECEDENCE = Dict("||"=>1,"&&"=>2,"=="=>3,"!="=>3,"<"=>4,"<="=>4,">"=>4,">="=>4,"+"=>5,"-"=>5,"*"=>6,"/"=>6,"%"=>6)
struct SyntaxNode
    tag::String
    first::CodeToken
    fields::NamedTuple
end
function Base.getproperty(node::SyntaxNode,name::Symbol)
    name in (:tag,:first,:fields) ? getfield(node,name) : getproperty(getfield(node,:fields),name)
end
syntax_node(tag,first;kwargs...) = SyntaxNode(tag,first,(;kwargs...))
mutable struct CodeParser
    tokens::Vector{CodeToken}
    cursor::Int
end
CodeParser(tokens) = CodeParser(tokens,1)
next_token(parser) = parser.tokens[parser.cursor]
at_symbol(parser,symbol) = next_token(parser).text == symbol
function syntax_error(parser,expected)
    token = next_token(parser)
    found = token.kind == "end" ? "end of file" : "'$(token.text)'"
    source_error(token.line,token.column,"expected $expected, found $found")
end
function take_symbol(parser,symbol)
    at_symbol(parser,symbol) || syntax_error(parser,"'$symbol'")
    token = next_token(parser)
    parser.cursor += 1
    token
end
function take_identifier(parser)
    next_token(parser).kind == "identifier" || syntax_error(parser,"identifier")
    token = next_token(parser)
    parser.cursor += 1
    token
end
function take_type(parser)
    next_token(parser).text in TYPE_NAMES || syntax_error(parser,"type")
    token = next_token(parser)
    parser.cursor += 1
    token
end
function parse_program(parser)
    items = SyntaxNode[]
    while next_token(parser).kind != "end"
        typ = take_type(parser)
        typ.allowed = true
        name = take_identifier(parser)
        if at_symbol(parser,"(")
            parameters = parse_list(parser,"(",")",parse_parameter,false)
            body = parse_block(parser)
            push!(items,syntax_node("function",typ;typ,name,parameters,body))
        else
            push!(items,parse_variable(parser,typ,name,true))
        end
    end
    items
end
function parse_parameter(parser)
    typ,name = take_type(parser),take_identifier(parser)
    brackets = Tuple{CodeToken,CodeToken}[]
    while at_symbol(parser,"[")
        push!(brackets,(take_symbol(parser,"["),take_symbol(parser,"]")))
    end
    syntax_node("parameter",typ;typ,name,brackets)
end
function parse_variable(parser,typ,name,semicolon)
    dimensions = Any[]
    while at_symbol(parser,"[")
        left = take_symbol(parser,"[")
        expression = at_symbol(parser,"]") ? nothing : parse_expression(parser)
        right = take_symbol(parser,"]")
        push!(dimensions,(left,expression,right))
    end
    equals = at_symbol(parser,"=") ? take_symbol(parser,"=") : nothing
    initializer = equals === nothing ? nothing : parse_initializer(parser)
    semi = semicolon ? take_symbol(parser,";") : nothing
    syntax_node("variable",typ;typ,name,dimensions,equals,initializer,semi)
end
parse_initializer(parser) = at_symbol(parser,"{") ? parse_list(parser,"{","}",parse_initializer,true) : parse_expression(parser)
function parse_list(parser,opening,closing,element,trailing_allowed)
    left = take_symbol(parser,opening)
    elements,commas = SyntaxNode[],CodeToken[]
    trailing = nothing
    if !at_symbol(parser,closing)
        item = element(parser)
        item.first.allowed = true
        push!(elements,item)
        while at_symbol(parser,",")
            comma = take_symbol(parser,",")
            if trailing_allowed && at_symbol(parser,closing)
                comma.trailing_comma = true
                trailing = comma
                break
            end
            push!(commas,comma)
            item = element(parser)
            item.first.allowed = true
            push!(elements,item)
        end
    end
    right = take_symbol(parser,closing)
    syntax_node("list",left;left,right,elements,commas,trailing,role=opening)
end
function parse_block(parser)
    left = take_symbol(parser,"{")
    statements = SyntaxNode[]
    while !at_symbol(parser,"}") && next_token(parser).kind != "end"
        item = parse_statement(parser)
        item.first.allowed = true
        push!(statements,item)
    end
    right = take_symbol(parser,"}")
    right.allowed = true
    syntax_node("block",left;left,right,statements)
end
function parse_statement(parser)
    token = next_token(parser)
    if token.text == "{"
        return parse_block(parser)
    elseif token.text in TYPE_NAMES
        typ,name = take_type(parser),take_identifier(parser)
        return parse_variable(parser,typ,name,true)
    elseif token.text == "if"
        return parse_if(parser)
    elseif token.text == "while"
        keyword = take_symbol(parser,"while")
        left = take_symbol(parser,"(")
        test = parse_expression(parser)
        right = take_symbol(parser,")")
        body = parse_body(parser)
        return syntax_node("while",keyword;keyword,left,test,right,body)
    elseif token.text == "for"
        return parse_for(parser)
    elseif token.text == "switch"
        return parse_switch(parser)
    elseif token.text == "return"
        keyword = take_symbol(parser,"return")
        expr = at_symbol(parser,";") ? nothing : parse_expression(parser)
        semi = take_symbol(parser,";")
        return syntax_node("return",keyword;keyword,expr,semi)
    elseif token.text in ("break","continue")
        parser.cursor += 1
        semi = take_symbol(parser,";")
        return syntax_node("flow",token;keyword=token,semi)
    end
    value = parse_simple(parser)
    semi = take_symbol(parser,";")
    syntax_node("simple_stmt",value.first;value,semi)
end
function parse_body(parser)
    body = parse_statement(parser)
    body.tag == "block" || (body.first.allowed = true)
    body
end
function parse_if(parser)
    keyword = take_symbol(parser,"if")
    left = take_symbol(parser,"(")
    test = parse_expression(parser)
    right = take_symbol(parser,")")
    body = parse_body(parser)
    else_token = at_symbol(parser,"else") ? take_symbol(parser,"else") : nothing
    alternative = nothing
    if else_token !== nothing
        if at_symbol(parser,"if")
            alternative = parse_if(parser)
            alternative.first.allowed = false
        else
            alternative = parse_body(parser)
        end
    end
    syntax_node("if",keyword;keyword,left,test,right,body,else_token,alternative)
end
function parse_for(parser)
    keyword = take_symbol(parser,"for")
    left = take_symbol(parser,"(")
    if at_symbol(parser,";")
        initial = nothing
    elseif next_token(parser).text in TYPE_NAMES
        typ,name = take_type(parser),take_identifier(parser)
        initial = parse_variable(parser,typ,name,false)
    else
        initial = parse_simple(parser)
    end
    first_semi = take_symbol(parser,";")
    condition = at_symbol(parser,";") ? nothing : parse_expression(parser)
    second_semi = take_symbol(parser,";")
    update = at_symbol(parser,")") ? nothing : parse_simple(parser)
    right = take_symbol(parser,")")
    body = parse_body(parser)
    syntax_node("for",keyword;keyword,left,initial,first_semi,condition,second_semi,update,right,body)
end
function parse_switch(parser)
    keyword = take_symbol(parser,"switch")
    left = take_symbol(parser,"(")
    test = parse_expression(parser)
    right = take_symbol(parser,")")
    opening = take_symbol(parser,"{")
    clauses = SyntaxNode[]
    while next_token(parser).text in ("case","default")
        label = next_token(parser)
        parser.cursor += 1
        label.allowed = true
        value = label.text == "case" ? parse_expression(parser) : nothing
        colon = take_symbol(parser,":")
        statements = SyntaxNode[]
        while !(next_token(parser).text in ("case","default","}")) && next_token(parser).kind != "end"
            item = parse_statement(parser)
            item.first.allowed = true
            push!(statements,item)
        end
        push!(clauses,syntax_node("clause",label;label,value,colon,statements))
    end
    closing = take_symbol(parser,"}")
    closing.allowed = true
    syntax_node("switch",keyword;keyword,left,test,right,opening,closing,clauses)
end
function parse_simple(parser)
    left = parse_expression(parser)
    if next_token(parser).text in ASSIGNMENTS
        op = next_token(parser)
        parser.cursor += 1
        right = parse_expression(parser)
        return syntax_node("assign",left.first;left,op,right)
    end
    syntax_node("expr_stmt",left.first;expr=left)
end
function parse_expression(parser)
    test = parse_binary(parser,1)
    at_symbol(parser,"?") || return test
    question = take_symbol(parser,"?")
    yes = parse_expression(parser)
    colon = take_symbol(parser,":")
    no = parse_expression(parser)
    syntax_node("conditional",test.first;test,question,yes,colon,no,level=0)
end
function parse_binary(parser,precedence)
    precedence > 6 && return parse_unary(parser)
    left = parse_binary(parser,precedence+1)
    while get(PRECEDENCE,next_token(parser).text,0) == precedence
        op = next_token(parser)
        parser.cursor += 1
        right = parse_binary(parser,precedence+1)
        left = syntax_node("binary",left.first;left,op,right,level=precedence)
    end
    left
end
function parse_unary(parser)
    if next_token(parser).text in ("-","!")
        op = next_token(parser)
        parser.cursor += 1
        operand = parse_unary(parser)
        return syntax_node("unary",op;op,operand,level=7)
    end
    target = parse_primary(parser)
    while true
        if at_symbol(parser,"(")
            arguments = parse_list(parser,"(",")",parse_expression,false)
            target = syntax_node("call",target.first;target,arguments,level=8)
        elseif at_symbol(parser,"[")
            left = take_symbol(parser,"[")
            index = parse_expression(parser)
            right = take_symbol(parser,"]")
            target = syntax_node("index",target.first;target,left,index,right,level=8)
        elseif at_symbol(parser,".")
            dot = take_symbol(parser,".")
            member = take_identifier(parser)
            target = syntax_node("member",target.first;target,dot,member,level=8)
        else
            return target
        end
    end
end
function parse_primary(parser)
    token = next_token(parser)
    if token.kind in ("identifier","number","string") || token.text in ("true","false")
        parser.cursor += 1
        return syntax_node("primary",token;value=token,level=8)
    elseif at_symbol(parser,"(")
        left = take_symbol(parser,"(")
        inner = parse_expression(parser)
        right = take_symbol(parser,")")
        return syntax_node("paren",left;left,inner,right,level=8)
    end
    syntax_error(parser,"expression")
end
