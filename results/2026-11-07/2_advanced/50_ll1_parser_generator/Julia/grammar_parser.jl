const END_MARKER = "\$"
struct Grammar
    order::Vector{String}
    rules::Dict{String,Vector{Vector{String}}}
    start::String
end
struct GrammarToken
    kind::Symbol
    value::String
    start::Int
    finish::Int
end
is_nonterminal(symbol) = startswith(symbol,"<") && endswith(symbol,">")
format_alternative(symbols) = isempty(symbols) ? "%empty" : join(symbols," ")
format_production(symbol,alternative) = symbol*" -> "*format_alternative(alternative)
function lex_line(line)
    tokens = GrammarToken[]
    i = 1
    while i<=ncodeunits(line)
        if line[i]==' '
            i += 1
            continue
        end
        line[i]=='#' && break
        start = i
        kind,value = :invalid,string(line[i])
        suffix = line[i:end]
        if line[i]=='<'
            found = match(r"^<[A-Za-z][A-Za-z0-9_]*>",suffix)
            if !isnothing(found)
                kind,value = :nonterminal,String(found.match)
                i += ncodeunits(value)
            else
                i += 1
            end
        elseif line[i]=='"'
            j = i+1
            while j<=ncodeunits(line) && !(line[j] in (' ','"'))
                j += 1
            end
            if j>i+1 && j<=ncodeunits(line) && line[j]=='"'
                kind,value = :terminal,line[i+1:j-1]
                i = j+1
            else
                i += 1
            end
        elseif isletter(line[i])
            found = match(r"^[A-Za-z][A-Za-z0-9_]*",suffix)
            kind,value = :word,String(found.match)
            i += ncodeunits(value)
        elseif startswith(suffix,"::=")
            kind,value = :definition,"::="
            i += 3
        elseif line[i]=='|'
            kind,value = :separator,"|"
            i += 1
        elseif line[i]=='%'
            directive = String(match(r"^%[A-Za-z]*",suffix).match)
            if directive in ("%empty","%start","%token")
                kind,value = :directive,directive
                i += ncodeunits(directive)
            else
                i += 1
            end
        else
            i += 1
        end
        push!(tokens,GrammarToken(kind,value,start,i-1))
        kind==:invalid && break
    end
    tokens
end
error_column(tokens,cursor) = cursor<=length(tokens) ? tokens[cursor].start : tokens[end].finish+1
function alternative_list(tokens,cursor)
    alternatives = Vector{String}[]
    while true
        cursor>length(tokens) && return alternatives,error_column(tokens,cursor)
        token = tokens[cursor]
        if token.kind==:directive && token.value=="%empty"
            alternative = String[]
            cursor += 1
        elseif token.kind in (:nonterminal,:terminal,:word)
            alternative = String[]
            while cursor<=length(tokens) && tokens[cursor].kind in (:nonterminal,:terminal,:word)
                push!(alternative,tokens[cursor].value)
                cursor += 1
            end
        else
            return alternatives,error_column(tokens,cursor)
        end
        push!(alternatives,alternative)
        cursor>length(tokens) && return alternatives,0
        tokens[cursor].kind!=:separator && return alternatives,error_column(tokens,cursor)
        cursor += 1
    end
end
function parse_line(tokens)
    isempty(tokens) && return (kind=:blank,lhs="",alternatives=Vector{String}[],error=0)
    token = tokens[1]
    if token.kind==:nonterminal
        (length(tokens)<2 || tokens[2].kind!=:definition) && return (
            kind=:rule,
            lhs="",
            alternatives=Vector{String}[],
            error=error_column(tokens,2)
        )
        alternatives,error = alternative_list(tokens,3)
        return (kind=:rule,lhs=token.value,alternatives=alternatives,error=error)
    elseif token.kind==:separator
        alternatives,error = alternative_list(tokens,2)
        return (kind=:continuation,lhs="",alternatives=alternatives,error=error)
    elseif token.kind==:directive && token.value=="%start"
        cursor = length(tokens)<2 || tokens[2].kind!=:nonterminal ? 2 : length(tokens)>2 ? 3 : 0
        return (
            kind=:start,
            lhs=cursor==0 ? tokens[2].value : "",
            alternatives=Vector{String}[],
            error=cursor==0 ? 0 : error_column(tokens,cursor)
        )
    elseif token.kind==:directive && token.value=="%token"
        bad = length(tokens)<2 ? 2 : 0
        if length(tokens)>=2
            bad = findfirst(t->t.kind!=:word,tokens[2:end])
            bad = isnothing(bad) ? 0 : bad+1
        end
        words = bad==0 ? [t.value for t in tokens[2:end]] : String[]
        return (kind=:declaration,lhs="",alternatives=[words],error=bad==0 ? 0 : error_column(tokens,bad))
    end
    (kind=:invalid,lhs="",alternatives=Vector{String}[],error=token.start)
end
function parse_grammar()
    order,rules = String[],Dict{String,Vector{Vector{String}}}()
    start,attachment = "",""
    declared,word_lines,diagnostics = Set{String}(),Dict{String,Int}(),String[]
    has_declaration = false
    for (line_number,line) in enumerate(readlines("input/grammar.bnf"))
        tokens = lex_line(line)
        parsed = parse_line(tokens)
        if parsed.error!=0
            push!(diagnostics,"line $line_number: syntax error at column $(parsed.error)")
            attachment = ""
            continue
        end
        kind,lhs = parsed.kind,parsed.lhs
        kind==:blank && continue
        if kind==:rule
            attachment = lhs
            if !haskey(rules,lhs)
                push!(order,lhs)
                rules[lhs] = Vector{String}[]
            end
        elseif kind==:continuation
            if isempty(attachment)
                push!(diagnostics,"line $line_number: continuation without a rule")
                continue
            end
            lhs = attachment
        elseif kind==:start
            attachment = ""
            if isempty(start)
                start = lhs
            else
                push!(diagnostics,"line $line_number: duplicate %start")
            end
        else
            attachment = ""
            has_declaration = true
            union!(declared,parsed.alternatives[1])
        end
        if kind in (:rule,:continuation)
            for token in tokens
                token.kind==:word && get!(word_lines,token.value,line_number)
            end
            for alternative in parsed.alternatives
                if alternative in rules[lhs]
                    push!(
                        diagnostics,
                        "line $line_number: duplicate alternative $(format_production(lhs,alternative))"
                    )
                else
                    push!(rules[lhs],alternative)
                end
            end
        end
    end
    (
        grammar=Grammar(order,rules,isempty(start) ? order[1] : start),
        declared=declared,
        words=word_lines,
        has_declaration=has_declaration,
        diagnostics=diagnostics
    )
end
