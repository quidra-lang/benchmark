include("lexer.jl")
include("parser.jl")
include("doc_builder.jl")
include("printer.jl")
include("report.jl")
struct SourceFile
    header::String
    filename::String
    profile::String
    lines::Vector{String}
end
struct FormatPass
    lines::Vector{String}
    comments::Vector{CodeComment}
    document::Union{Nothing,Document}
    first_function::Union{Nothing,SyntaxNode}
    function_doc::Union{Nothing,Document}
end
mutable struct FormatResult
    source::SourceFile
    original::Vector{String}
    formatted::Vector{String}
    error::Union{Nothing,SourceError}
    first::Union{Nothing,FormatPass}
    idempotency::String
    diagnostics::Vector{String}
end
function read_profiles()
    profiles = Dict{String,Dict{String,Any}}()
    current = ""
    for line in readlines("input/style.txt")
        isempty(line) && continue
        if startswith(line,"[")
            current = line[2:end-1]
            profiles[current] = Dict{String,Any}()
        else
            key,value = split(line,"=";limit=2)
            profiles[current][key] = key in ("width","indent","max_blank_lines","comment_column") ? parse(Int,value) :
                key in ("space_around_operators","space_after_keyword","indent_case_labels","add_braces","remove_parens") ? value == "yes" : value
        end
    end
    profiles
end
function read_sources()
    sources = SourceFile[]
    for line in readlines("input/sources.txt")
        if startswith(line,"=== ")
            _,filename,profile = split(line," ")
            push!(sources,SourceFile(line,filename,profile,String[]))
        else
            push!(sources[end].lines,line)
        end
    end
    sources
end
function attach_comments!(tokens,comments,items)
    real_tokens = tokens[1:end-1]
    for comment in comments
        before = [token for token in real_tokens if (token.line,token.column) < (comment.line,comment.column)]
        after = [token for token in real_tokens if (token.line,token.column) > (comment.line,comment.column)]
        previous = isempty(before) ? nothing : before[end]
        following = isempty(after) ? nothing : after[1]
        index = findfirst(entry -> entry === comment,items)
        next_item = index == length(items) ? nothing : items[index+1]
        comment.own_line = comment.kind == "line_comment" || next_item === nothing || next_item.line > comment.line
        if previous !== nothing && previous.line == comment.line && (following === nothing || following.line > comment.line)
            push!(previous.trailing,comment)
        else
            push!((following === nothing ? tokens[end] : following).leading,comment)
        end
    end
    for token in tokens
        token.original_trailing = !isempty(token.trailing)
    end
end
function check_comment_positions(tokens)
    for token in tokens, comment in token.leading
        if token.trailing_comma || (comment.own_line && !token.allowed)
            source_error(comment.line,comment.column,"comment not allowed here")
        end
    end
end
struct CodeFormatter
    profile::Dict{String,Any}
    tokens::Vector{CodeToken}
    indent_width::Int
    max_blank::Int
    separator::String
    operator_break::Document
    keyword_gap::String
    kr::Bool
end
function CodeFormatter(profile,tokens)
    spaced = profile["space_around_operators"]
    CodeFormatter(profile,tokens,profile["indent"],profile["max_blank_lines"],spaced ? " " : "",spaced ? LINE : SOFTLINE,
        profile["space_after_keyword"] ? " " : "",profile["brace_style"] == "kr")
end
sep_doc(formatter,blank) = concat(fill(HARDLINE,1+min(blank,formatter.max_blank)))
pre_blank(token) = isempty(token.leading) ? token.blank : token.leading[1].blank
function comment_doc(formatter,comments,following)
    parts = Any[]
    for (index,comment) in enumerate(comments)
        push!(parts,doc_text(comment.text))
        next_entry = index < length(comments) ? comments[index+1] : following
        next_entry === nothing && continue
        push!(parts,comment.own_line ? sep_doc(formatter,next_entry.blank) : doc_text(" "))
    end
    concat(parts)
end
function token_doc(formatter,token;leading=token.leading)
    concat(comment_doc(formatter,leading,token),doc_text(token.text),
        isempty(token.trailing) ? nothing : suffix(join([c.text for c in token.trailing]," ")))
end
function splitting_comments(token)
    index = findlast(c -> c.own_line,token.leading)
    stop = index === nothing ? 0 : index
    token.leading[1:stop],token.leading[stop+1:end]
end
function closing_comments(formatter,comments,preceding)
    isempty(comments) && return nothing
    concat(preceding ? sep_doc(formatter,comments[1].blank) : nothing,comment_doc(formatter,comments,nothing))
end
function file_doc(formatter,items,end_token)
    pieces = Any[]
    first_function,function_document = nothing,nothing
    for (index,item) in enumerate(items)
        index == 1 || push!(pieces,sep_doc(formatter,pre_blank(item.first)))
        document = item_doc(formatter,item)
        if item.tag == "function" && first_function === nothing
            first_function,function_document = item,document
        end
        push!(pieces,document)
    end
    if !isempty(end_token.leading)
        isempty(items) || push!(pieces,sep_doc(formatter,end_token.leading[1].blank))
        push!(pieces,comment_doc(formatter,end_token.leading,nothing))
    end
    concat(pieces),first_function,function_document
end
function item_doc(formatter,item)
    item.tag == "function" || return variable_doc(formatter,item)
    concat(token_doc(formatter,item.typ)," ",token_doc(formatter,item.name),list_doc(formatter,item.parameters),HARDLINE,block_doc(formatter,item.body))
end
function parameter_doc(formatter,item)
    parts = Any[token_doc(formatter,item.typ)," ",token_doc(formatter,item.name)]
    for (left,right) in item.brackets
        append!(parts,[token_doc(formatter,left),token_doc(formatter,right)])
    end
    concat(parts)
end
function variable_doc(formatter,item)
    parts = Any[token_doc(formatter,item.typ)," ",token_doc(formatter,item.name)]
    for (left,expression,right) in item.dimensions
        push!(parts,token_doc(formatter,left))
        expression === nothing || push!(parts,expression_doc(formatter,expression,0))
        push!(parts,token_doc(formatter,right))
    end
    if item.equals !== nothing
        append!(parts,[formatter.separator,token_doc(formatter,item.equals),formatter.separator,initializer_doc(formatter,item.initializer)])
    end
    item.semi === nothing || push!(parts,token_doc(formatter,item.semi))
    concat(parts)
end
initializer_doc(formatter,item) = item.tag == "list" ? list_doc(formatter,item) : expression_doc(formatter,item,0)
function list_doc(formatter,item)
    elements = Document[]
    for entry in item.elements
        document = entry.tag == "parameter" ? parameter_doc(formatter,entry) :
            item.role == "{" ? initializer_doc(formatter,entry) : expression_doc(formatter,entry,0)
        push!(elements,document)
    end
    isempty(elements) && return concat(token_doc(formatter,item.left),token_doc(formatter,item.right))
    parts = Any[SOFTLINE,elements[1]]
    for index in 2:length(elements)
        append!(parts,[token_doc(formatter,item.commas[index-1]),LINE,elements[index]])
    end
    if item.role == "{"
        push!(parts,if_break(",",""))
        if item.trailing !== nothing && !isempty(item.trailing.trailing)
            push!(parts,suffix(join([c.text for c in item.trailing.trailing]," ")))
        end
    end
    forced = any(token.original_trailing for token in formatter.tokens[item.left.index:item.right.index-1])
    group(concat(forced ? BREAK_PARENT : nothing,token_doc(formatter,item.left),nest(formatter.indent_width,parts),SOFTLINE,token_doc(formatter,item.right)))
end
function block_doc(formatter,item)
    own,inline = splitting_comments(item.right)
    isempty(item.statements) && isempty(own) && return concat(token_doc(formatter,item.left),token_doc(formatter,item.right;leading=inline))
    parts = Any[]
    isempty(item.statements) && push!(parts,HARDLINE)
    for (index,statement) in enumerate(item.statements)
        push!(parts,index == 1 ? HARDLINE : sep_doc(formatter,pre_blank(statement.first)))
        push!(parts,statement_doc(formatter,statement))
    end
    push!(parts,closing_comments(formatter,own,!isempty(item.statements)))
    concat(token_doc(formatter,item.left),nest(formatter.indent_width,parts),HARDLINE,token_doc(formatter,item.right;leading=inline))
end
function body_doc(formatter,item)
    before = formatter.kr ? doc_text(" ") : HARDLINE
    item.tag == "block" && return concat(before,block_doc(formatter,item))
    content = nest(formatter.indent_width,concat(HARDLINE,statement_doc(formatter,item)))
    formatter.profile["add_braces"] ? concat(before,"{",content,HARDLINE,"}") : content
end
function simple_doc(formatter,item)
    item.tag == "assign" || return expression_doc(formatter,item.expr,0)
    concat(expression_doc(formatter,item.left,0),formatter.separator,token_doc(formatter,item.op),formatter.separator,expression_doc(formatter,item.right,0))
end
function if_doc(formatter,item)
    parts = Any[token_doc(formatter,item.keyword),formatter.keyword_gap,token_doc(formatter,item.left),expression_doc(formatter,item.test,0),token_doc(formatter,item.right),body_doc(formatter,item.body)]
    if item.else_token !== nothing
        before = formatter.kr && (item.body.tag == "block" || formatter.profile["add_braces"]) ? doc_text(" ") : HARDLINE
        append!(parts,[before,token_doc(formatter,item.else_token)])
        if item.alternative.tag == "if"
            append!(parts,[" ",if_doc(formatter,item.alternative)])
        else
            push!(parts,body_doc(formatter,item.alternative))
        end
    end
    concat(parts)
end
function for_doc(formatter,item)
    parts = Any[]
    if item.initial !== nothing
        push!(parts,item.initial.tag == "variable" ? variable_doc(formatter,item.initial) : simple_doc(formatter,item.initial))
    end
    push!(parts,token_doc(formatter,item.first_semi))
    item.condition === nothing || append!(parts,[LINE,expression_doc(formatter,item.condition,0)])
    push!(parts,token_doc(formatter,item.second_semi))
    item.update === nothing || append!(parts,[LINE,simple_doc(formatter,item.update)])
    concat(token_doc(formatter,item.keyword),formatter.keyword_gap,token_doc(formatter,item.left),group(align_doc(parts)),token_doc(formatter,item.right),body_doc(formatter,item.body))
end
function clause_doc(formatter,item)
    parts = Any[token_doc(formatter,item.label)]
    item.value === nothing || append!(parts,[" ",expression_doc(formatter,item.value,0)])
    push!(parts,token_doc(formatter,item.colon))
    if !isempty(item.statements)
        inner = Any[]
        for (index,statement) in enumerate(item.statements)
            push!(inner,index == 1 ? HARDLINE : sep_doc(formatter,pre_blank(statement.first)))
            push!(inner,statement_doc(formatter,statement))
        end
        push!(parts,nest(formatter.indent_width,inner))
    end
    concat(parts)
end
function switch_doc(formatter,item)
    own,inline = splitting_comments(item.closing)
    parts = Any[]
    isempty(item.clauses) && !isempty(own) && push!(parts,HARDLINE)
    for (index,clause) in enumerate(item.clauses)
        push!(parts,index == 1 ? HARDLINE : sep_doc(formatter,pre_blank(clause.first)))
        push!(parts,clause_doc(formatter,clause))
    end
    push!(parts,closing_comments(formatter,own,!isempty(item.clauses)))
    header = concat(token_doc(formatter,item.keyword),formatter.keyword_gap,token_doc(formatter,item.left),expression_doc(formatter,item.test,0),token_doc(formatter,item.right),formatter.kr ? doc_text(" ") : HARDLINE,token_doc(formatter,item.opening))
    isempty(item.clauses) && isempty(own) && return concat(header,token_doc(formatter,item.closing;leading=inline))
    amount = formatter.profile["indent_case_labels"] ? formatter.indent_width : 0
    concat(header,nest(amount,parts),HARDLINE,token_doc(formatter,item.closing;leading=inline))
end
function statement_doc(formatter,item)
    tag = item.tag
    tag == "block" && return block_doc(formatter,item)
    tag == "variable" && return variable_doc(formatter,item)
    tag == "if" && return if_doc(formatter,item)
    tag == "for" && return for_doc(formatter,item)
    tag == "switch" && return switch_doc(formatter,item)
    if tag == "while"
        return concat(token_doc(formatter,item.keyword),formatter.keyword_gap,token_doc(formatter,item.left),expression_doc(formatter,item.test,0),token_doc(formatter,item.right),body_doc(formatter,item.body))
    elseif tag == "return"
        return concat(token_doc(formatter,item.keyword),item.expr === nothing ? nothing : concat(" ",expression_doc(formatter,item.expr,0)),token_doc(formatter,item.semi))
    elseif tag == "flow"
        return concat(token_doc(formatter,item.keyword),token_doc(formatter,item.semi))
    end
    concat(simple_doc(formatter,item.value),token_doc(formatter,item.semi))
end
function last_expression_token(item)
    item.tag == "primary" && return item.value
    item.tag in ("paren","index") && return item.right
    item.tag == "unary" && return last_expression_token(item.operand)
    item.tag == "binary" && return last_expression_token(item.right)
    item.tag == "conditional" && return last_expression_token(item.no)
    item.tag == "call" && return item.arguments.right
    item.member
end
function opened_expression(formatter,item,required)
    while formatter.profile["remove_parens"] && item.tag == "paren" && item.inner.level >= required && isempty(item.left.leading) && isempty(item.right.leading)
        inner = item.inner
        if !isempty(item.left.trailing)
            inner.first.trailing = [item.left.trailing;inner.first.trailing]
            empty!(item.left.trailing)
        end
        if !isempty(item.right.trailing)
            append!(last_expression_token(inner).trailing,item.right.trailing)
            empty!(item.right.trailing)
        end
        item = inner
    end
    item
end
function binary_doc(formatter,item)
    precedence = item.level
    operators,operands = CodeToken[],SyntaxNode[]
    current = item
    while current.tag == "binary" && current.level == precedence
        push!(operators,current.op)
        push!(operands,current.right)
        current = opened_expression(formatter,current.left,precedence)
    end
    reverse!(operators)
    reverse!(operands)
    parts = Any[]
    for (operator,operand) in zip(operators,operands)
        append!(parts,[formatter.operator_break,token_doc(formatter,operator),formatter.separator,expression_doc(formatter,operand,precedence+1)])
    end
    group(concat(expression_doc(formatter,current,precedence),nest(formatter.indent_width,parts)))
end
function conditional_doc(formatter,item)
    parts = Any[]
    current = item
    while true
        append!(parts,[formatter.operator_break,token_doc(formatter,current.question),formatter.separator,expression_doc(formatter,current.yes,0),formatter.operator_break,token_doc(formatter,current.colon),formatter.separator])
        following = opened_expression(formatter,current.no,0)
        if following.tag != "conditional"
            push!(parts,expression_doc(formatter,following,0))
            break
        end
        push!(parts,expression_doc(formatter,following.test,1))
        current = following
    end
    group(concat(expression_doc(formatter,item.test,1),nest(formatter.indent_width,parts)))
end
function postfix_piece(formatter,item)
    item.tag == "call" && return list_doc(formatter,item.arguments)
    item.tag == "index" && return concat(token_doc(formatter,item.left),expression_doc(formatter,item.index,0),token_doc(formatter,item.right))
    concat(token_doc(formatter,item.dot),token_doc(formatter,item.member))
end
function postfix_doc(formatter,item)
    operators = SyntaxNode[]
    current = item
    while current.tag in ("call","index","member")
        push!(operators,current)
        current = opened_expression(formatter,current.target,8)
    end
    reverse!(operators)
    segments = [SyntaxNode[]]
    for operator in operators
        operator.tag == "member" && push!(segments,SyntaxNode[])
        push!(segments[end],operator)
    end
    calls = [index for index in 2:length(segments) if any(op -> op.tag == "call",segments[index])]
    head = expression_doc(formatter,current,8)
    length(calls) < 2 && return concat(head,[postfix_piece(formatter,operator) for operator in operators])
    split_at = calls[1]
    preceding = [postfix_piece(formatter,operator) for segment in segments[1:split_at-1] for operator in segment]
    following = Any[]
    for segment in segments[split_at:end]
        push!(following,SOFTLINE)
        append!(following,[postfix_piece(formatter,operator) for operator in segment])
    end
    group(concat(head,preceding,nest(formatter.indent_width,following)))
end
function expression_doc(formatter,item,required)
    item = opened_expression(formatter,item,required)
    item.tag == "primary" && return token_doc(formatter,item.value)
    item.tag == "paren" && return concat(token_doc(formatter,item.left),expression_doc(formatter,item.inner,0),token_doc(formatter,item.right))
    item.tag == "unary" && return concat(token_doc(formatter,item.op),expression_doc(formatter,item.operand,8))
    item.tag == "binary" && return binary_doc(formatter,item)
    item.tag == "conditional" && return conditional_doc(formatter,item)
    postfix_doc(formatter,item)
end
function render_once(lines,profile)
    tokens,comments,items = lexical_analysis(lines)
    attach_comments!(tokens,comments,items)
    syntax = parse_program(CodeParser(tokens))
    check_comment_positions(tokens)
    isempty(syntax) && isempty(tokens[end].leading) && return FormatPass(String[],comments,nothing,nothing,nothing)
    document,first_function,function_document = file_doc(CodeFormatter(profile,tokens),syntax,tokens[end])
    FormatPass(print_document(document,profile),comments,document,first_function,function_document)
end
function format_source(source,profiles)
    profile = profiles[source.profile]
    original = String[trim_spaces(line) for line in source.lines]
    result = FormatResult(source,original,original,nothing,nothing,"",String[])
    try
        result.first = render_once(source.lines,profile)
    catch error
        error isa SourceError || rethrow()
        result.error = error
        result.idempotency = "$(source.filename): skipped (syntax error)"
        push!(result.diagnostics,"$(source.filename):$(error.line):$(error.column): error: $(error.message)")
        return result
    end
    result.formatted = result.first.lines
    try
        second = render_once(result.formatted,profile)
        if result.formatted == second.lines
            result.idempotency = "$(source.filename): stable"
        else
            difference = findfirst(index -> result.formatted[index] != second.lines[index],1:min(length(result.formatted),length(second.lines)))
            difference === nothing && (difference = min(length(result.formatted),length(second.lines))+1)
            result.idempotency = "$(source.filename): unstable at line $difference"
        end
    catch error
        error isa SourceError || rethrow()
        result.idempotency = "$(source.filename): unstable (second pass: $(error.line):$(error.column): $(error.message))"
    end
    for (line_number,line) in enumerate(result.formatted)
        length(line) <= profile["width"] && continue
        push!(result.diagnostics,"$(source.filename):$line_number: warning: line too long ($(length(line)) > $(profile["width"]))")
    end
    result
end
function main()
    profiles = read_profiles()
    results = [format_source(source,profiles) for source in read_sources()]
    formatted,idempotency,diagnostics,trees,changes = String[],String[],String[],String[],String[]
    for result in results
        push!(formatted,result.source.header)
        append!(formatted,result.formatted)
        push!(idempotency,result.idempotency)
        append!(diagnostics,result.diagnostics)
        push!(trees,"=== $(result.source.filename)")
        push!(changes,"=== $(result.source.filename)")
        if result.error !== nothing
            push!(trees,"syntax error")
            push!(changes,"skipped (syntax error)")
            continue
        end
        first = result.first
        groups = all_groups(first.document)
        longest = isempty(first.lines) ? 0 : maximum(length,first.lines)
        broken = count(g -> g.mode in (:break,:forced),groups)
        forced = count(g -> g.mode == :forced,groups)
        push!(trees,"metrics lines=$(length(first.lines)) longest=$longest comments=$(length(first.comments)) groups=$(length(groups)) broken=$broken forced=$forced")
        if first.first_function === nothing
            push!(trees,"no function")
        else
            push!(trees,"function $(first.first_function.name.text)")
            append!(trees,doc_tree(first.function_doc))
        end
        append!(changes,diff_lines(result.original,result.formatted))
    end
    isempty(diagnostics) && push!(diagnostics,"no diagnostics")
    for (name,lines) in [("formatted.txt",formatted),("idempotency.txt",idempotency),("diagnostics.txt",diagnostics),("doc_tree.txt",trees),("changes.txt",changes)]
        write_lines(name,lines)
    end
end
main()
