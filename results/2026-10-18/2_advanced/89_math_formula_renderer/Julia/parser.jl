const ATOM_KINDS = Set(["identifier","number","symbol","command","text"])
const TERMINATORS = Set(["}","&","newline","right","end","eof"])
const ARGUMENT_KINDS = union(ATOM_KINDS,Set(["eqref","{","frac","binom","overset","underset","sqrt","accent"]))
const UNEXPECTED = Dict("right"=>"unexpected \\right","end"=>"unexpected \\end","&"=>"misplaced &","newline"=>"misplaced \\\\")
struct FormulaNode
    kind::String
    children::Vector{Any}
    value::Any
    column::Int
end
node(kind,children=Any[];value=nothing,column=0) = FormulaNode(kind,Any[children...],value,column)
collapse(elements) = length(elements) == 1 ? elements[1] : node("row",elements)
function check_braces(tokens)
    stack = Int[]
    for token in tokens
        if token.kind == "{"
            push!(stack,token.column)
        elseif token.kind == "}"
            isempty(stack) && formula_error(token.column,"unmatched }")
            pop!(stack)
        end
    end
    isempty(stack) || formula_error(stack[end],"unclosed {")
end
mutable struct FormulaParser
    tokens::Vector{FormulaToken}
    position::Int
    tag::Union{Nothing,FormulaToken}
    label::Union{Nothing,FormulaToken}
end
peek_token(parser) = parser.tokens[parser.position]
function take_token!(parser)
    token = peek_token(parser)
    token.kind != "eof" && (parser.position += 1)
    token
end
function unexpected!(parser)
    token = peek_token(parser)
    formula_error(token.column,UNEXPECTED[token.kind])
end
function parse_formula!(parser)
    elements = element_list!(parser;top=true)
    peek_token(parser).kind == "eof" || unexpected!(parser)
    elements
end
function element_list!(parser;top=false,index=false)
    elements = FormulaNode[]
    while true
        token = peek_token(parser)
        (token.kind in TERMINATORS || (index && token.kind == "symbol" && token.value == "]")) && return elements
        if token.kind in ("tag","label")
            top || formula_error(token.column,"misplaced \\" * token.kind)
            previous = token.kind == "tag" ? parser.tag : parser.label
            previous === nothing || formula_error(token.column,"duplicate \\" * token.kind)
            token = take_token!(parser)
            token.kind == "tag" ? (parser.tag = token) : (parser.label = token)
        else
            push!(elements,read_element!(parser))
        end
    end
end
function read_element!(parser)
    base = peek_token(parser).kind in ("^","_") ? node("row") : nucleus!(parser)
    sub,sup = nothing,nothing
    while peek_token(parser).kind in ("^","_")
        token = take_token!(parser)
        if token.kind == "^"
            sup === nothing || formula_error(token.column,"double superscript")
            sup = argument!(parser,"^")
        else
            sub === nothing || formula_error(token.column,"double subscript")
            sub = argument!(parser,"_")
        end
    end
    sub === nothing && sup === nothing ? base : node("script",Any[base,sub,sup])
end
function argument!(parser,name)
    peek_token(parser).kind in ARGUMENT_KINDS || formula_error(peek_token(parser).column,"missing argument for " * name)
    nucleus!(parser)
end
function delimiter!(parser)
    token = take_token!(parser)
    token.kind == "symbol" && token.value in ("(",")","[","]","|",".") && return token.value
    token.kind == "command" && token.value in ("\\{","\\}") && return token.value
    formula_error(token.column,"invalid delimiter")
end
function nucleus!(parser)
    token = take_token!(parser)
    kind = token.kind
    kind in ATOM_KINDS && return node(kind;value=token.value,column=token.column)
    kind == "eqref" && return node("reference";value=token.value,column=token.column)
    if kind == "{"
        elements = element_list!(parser)
        peek_token(parser).kind == "}" || unexpected!(parser)
        take_token!(parser)
        return collapse(elements)
    elseif kind in ("frac","binom","overset","underset")
        first = argument!(parser,"\\" * kind)
        second = argument!(parser,"\\" * kind)
        return node(kind,[first,second])
    elseif kind == "sqrt"
        index = nothing
        if peek_token(parser).kind == "symbol" && peek_token(parser).value == "["
            opening = take_token!(parser)
            elements = element_list!(parser;index=true)
            (peek_token(parser).kind == "symbol" && peek_token(parser).value == "]") || formula_error(opening.column,"missing ]")
            take_token!(parser)
            index = collapse(elements)
        end
        body = argument!(parser,"\\sqrt")
        return index === nothing ? node("sqrt",[body]) : node("root",[index,body])
    elseif kind == "accent"
        return node("accent",[argument!(parser,"\\" * token.value)];value=token.value)
    elseif kind == "left"
        left = delimiter!(parser)
        elements = element_list!(parser)
        peek_token(parser).kind == "right" || formula_error(token.column,"missing \\right")
        closing = take_token!(parser)
        right = delimiter!(parser)
        return node("delim",[collapse(elements)];value=(left,right),column=closing.column)
    end
    read_matrix!(parser,token.value,token.column)
end
function read_matrix!(parser,environment,column)
    rows = [FormulaNode[]]
    while true
        push!(rows[end],collapse(element_list!(parser)))
        token = take_token!(parser)
        token.kind == "&" && continue
        if token.kind == "newline"
            push!(rows,FormulaNode[])
            continue
        end
        token.kind == "end" || formula_error(column,"missing \\end")
        token.value == environment || formula_error(token.column,"mismatched \\end")
        break
    end
    if length(rows) >= 2 && length(rows[end]) == 1 && rows[end][1].kind == "row" && isempty(rows[end][1].children)
        pop!(rows)
    end
    columns = maximum(length.(rows))
    for row in rows
        while length(row) < columns
            push!(row,node("row"))
        end
    end
    node("matrix",rows;value=environment)
end
