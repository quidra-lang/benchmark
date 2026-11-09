mutable struct QueryParser
    tokens::Vector{String}
    position::Int
end

function query_tokens(text)
    tokens = String[]
    position = 1
    while position <= length(text)
        character = text[position]
        if character == ' '
            position += 1
            continue
        end
        start = position
        if character == '\''
            position = findnext(==('\''), text, position + 1) + 1
        elseif isletter(character) || character == '_'
            position += 1
            while position <= length(text) && (isletter(text[position]) || isdigit(text[position]) || text[position] == '_')
                position += 1
            end
        elseif isdigit(character) || character == '-'
            position += 1
            while position <= length(text) && isdigit(text[position])
                position += 1
            end
        elseif position < length(text) && text[position:position + 1] in ("<=", ">=", "<>")
            position += 2
        else
            position += 1
        end
        push!(tokens, text[start:position - 1])
    end
    return tokens
end

peek_token(parser) = parser.position > length(parser.tokens) ? "" : parser.tokens[parser.position]
function take_token!(parser)
    token = parser.tokens[parser.position]
    parser.position += 1
    return token
end
function accept_token!(parser, token)
    peek_token(parser) != token && return false
    parser.position += 1
    return true
end

function parse_item!(parser)
    name = take_token!(parser)
    islowercase(name[1]) && return (operation="COLUMN", name=name)
    take_token!(parser)
    operation = accept_token!(parser, "DISTINCT") ? "COUNT_DISTINCT" : name
    column = accept_token!(parser, "*") ? nothing : take_token!(parser)
    take_token!(parser)
    return (operation=operation, name=column)
end

function parse_literal!(parser)
    token = take_token!(parser)
    startswith(token, "'") && return (kind="STRING", value=token[2:end - 1])
    token in ("TRUE", "FALSE") && return (kind="BOOL", value=token == "TRUE")
    return (kind="INT", value=parse(Int, token))
end

function parse_negation!(parser)
    accept_token!(parser, "NOT") && return (operation="NOT", left=parse_negation!(parser))
    if accept_token!(parser, "(")
        tree = parse_condition!(parser)
        take_token!(parser)
        return tree
    end
    column, operation = take_token!(parser), take_token!(parser)
    literals = Any[]
    if operation == "IS"
        operation = accept_token!(parser, "NOT") ? "IS_NOT_NULL" : "IS_NULL"
        take_token!(parser)
    elseif operation == "BETWEEN"
        push!(literals, parse_literal!(parser))
        take_token!(parser)
        push!(literals, parse_literal!(parser))
    elseif operation == "IN"
        take_token!(parser)
        push!(literals, parse_literal!(parser))
        while accept_token!(parser, ",")
            push!(literals, parse_literal!(parser))
        end
        take_token!(parser)
    else
        push!(literals, parse_literal!(parser))
    end
    return (operation=operation, column=column, literals=literals)
end

function parse_conjunction!(parser)
    tree = parse_negation!(parser)
    while accept_token!(parser, "AND")
        tree = (operation="AND", left=tree, right=parse_negation!(parser))
    end
    return tree
end

function parse_condition!(parser)
    tree = parse_conjunction!(parser)
    while accept_token!(parser, "OR")
        tree = (operation="OR", left=tree, right=parse_conjunction!(parser))
    end
    return tree
end

function parse_query(text)
    parser = QueryParser(query_tokens(text), 1)
    take_token!(parser)
    items = nothing
    if !accept_token!(parser, "*")
        items = Any[parse_item!(parser)]
        while accept_token!(parser, ",")
            push!(items, parse_item!(parser))
        end
    end
    condition = accept_token!(parser, "WHERE") ? parse_condition!(parser) : nothing
    group = nothing
    if accept_token!(parser, "GROUP")
        take_token!(parser)
        group = take_token!(parser)
    end
    order, descending = nothing, false
    if accept_token!(parser, "ORDER")
        take_token!(parser)
        order = take_token!(parser)
        descending = accept_token!(parser, "DESC")
        !descending && accept_token!(parser, "ASC")
    end
    limit = accept_token!(parser, "LIMIT") ? parse(Int, take_token!(parser)) : nothing
    return (; items, condition, group, order, descending, limit)
end
