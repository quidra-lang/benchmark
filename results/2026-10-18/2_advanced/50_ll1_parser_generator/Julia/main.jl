include("grammar_parser.jl")
include("transform.jl")
include("first_follow.jl")
include("table.jl")
include("driver.jl")
listed(heading,items) = heading*join((" $item" for item in items))
function reachable(g)
    seen,queue = Set([g.start]),[g.start]
    cursor = 1
    while cursor<=length(queue)
        lhs = queue[cursor]
        cursor += 1
        for rhs in g.rules[lhs],s in rhs
            if is_nonterminal(s) && !(s in seen)
                push!(seen,s)
                push!(queue,s)
            end
        end
    end
    seen
end
function retain_grammar(g,names)
    Grammar(names,Dict(lhs=>g.rules[lhs] for lhs in names),g.start)
end
function clean_grammar(grammar)
    g,diagnostics = clone_grammar(grammar),String[]
    defined = Set(g.order)
    undefined = Set(s for lhs in g.order for rhs in g.rules[lhs] for s in rhs if is_nonterminal(s) && !(s in defined))
    append!(diagnostics,["undefined nonterminal $name" for name in sort(collect(undefined);by=s->s[2:end-1])])
    for lhs in g.order
        kept = Vector{String}[]
        for rhs in g.rules[lhs]
            bad = findfirst(s->s in undefined,rhs)
            if isnothing(bad)
                push!(kept,rhs)
            else
                push!(diagnostics,"removed $(format_production(lhs,rhs)) (undefined $(rhs[bad]))")
            end
        end
        g.rules[lhs] = kept
    end
    productive = Set{String}()
    while true
        changed = false
        for lhs in g.order
            if !(lhs in productive) && any(
                rhs->all(s->!is_nonterminal(s) || s in productive,rhs),
                g.rules[lhs]
            )
                push!(productive,lhs)
                changed = true
            end
        end
        changed || break
    end
    removed = setdiff(Set(g.order),productive)
    append!(diagnostics,["unproductive nonterminal $lhs" for lhs in g.order if lhs in removed])
    g = retain_grammar(g,[lhs for lhs in g.order if !(lhs in removed)])
    for lhs in g.order
        kept = Vector{String}[]
        for rhs in g.rules[lhs]
            bad = findfirst(s->s in removed,rhs)
            if isnothing(bad)
                push!(kept,rhs)
            else
                push!(diagnostics,"removed $(format_production(lhs,rhs)) (unproductive $(rhs[bad]))")
            end
        end
        g.rules[lhs] = kept
    end
    reached = reachable(g)
    append!(diagnostics,["unreachable nonterminal $lhs" for lhs in g.order if !(lhs in reached)])
    retain_grammar(g,[lhs for lhs in g.order if lhs in reached]),diagnostics
end
function left_recursion_diagnostics(g)
    diagnostics = String[]
    for start in g.order
        queue,parent = [start],Dict(start=>"")
        cursor,found = 1,false
        while cursor<=length(queue) && !found
            lhs = queue[cursor]
            cursor += 1
            for rhs in g.rules[lhs]
                (isempty(rhs) || !is_nonterminal(rhs[1])) && continue
                next = rhs[1]
                if next==start
                    path = [lhs]
                    while !isempty(parent[path[end]])
                        push!(path,parent[path[end]])
                    end
                    push!(diagnostics,"left recursion: "*join(vcat(reverse(path),[start])," -> "))
                    found = true
                    break
                elseif !haskey(parent,next)
                    parent[next] = lhs
                    push!(queue,next)
                end
            end
        end
    end
    diagnostics
end
function grammar_summary(g)
    alternatives = [rhs for lhs in g.order for rhs in g.rules[lhs]]
    "start=$(g.start) nonterminals=$(length(g.order)) terminals=$(length(terminals_of(g))) productions=$(length(alternatives)) empty=$(count(isempty,alternatives)) unit=$(count(rhs->length(rhs)==1 && is_nonterminal(rhs[1]),alternatives))"
end
function grammar_listing(g;numbered=false)
    lines = String[]
    total = sum(length(g.rules[lhs]) for lhs in g.order)
    width,number = length(string(total)),0
    for lhs in g.order,(i,rhs) in enumerate(g.rules[lhs])
        number += 1
        line = i==1 ? format_production(lhs,rhs) : repeat(" ",length(lhs))*" | "*format_alternative(rhs)
        push!(lines,numbered ? lpad(number,width)*"  "*line : line)
    end
    lines
end
function grammar_report(cleaned,recursion,factored,final,recursion_log,factor_log,final_log)
    lines = vcat(["== cleaned grammar ==",grammar_summary(cleaned)],grammar_listing(cleaned))
    for (title,g,log,numbered) in (
        ("left recursion elimination",recursion,recursion_log,false),
        ("left factoring",factored,factor_log,false),
        ("final grammar",final,final_log,true)
    )
        append!(lines,["","== $title =="])
        append!(lines,isempty(log) ? ["none"] : log)
        push!(lines,grammar_summary(g))
        append!(lines,grammar_listing(g;numbered=numbered))
    end
    append!(lines,["","== cross reference =="])
    productions = number_productions(final)
    for symbol in vcat(final.order,terminal_order(terminals_of(final)))
        numbers = [p.number for p in productions if symbol in p.rhs]
        name = is_nonterminal(symbol) ? symbol : "\"$symbol\""
        push!(lines,isempty(numbers) ? "$name not used" : listed("$name used in",numbers))
    end
    lines
end
function sequence_measure(rhs,scores)
    length,height = 0,0
    for s in rhs
        if is_nonterminal(s)
            haskey(scores,s) || return nothing
            length += scores[s][1]
            height = max(height,scores[s][2])
        else
            length += 1
        end
    end
    (length,height+1)
end
function expand_sequence(rhs,sentences)
    result = String[]
    for s in rhs
        append!(result,is_nonterminal(s) ? sentences[s] : [s])
    end
    result
end
function shortest_sentences(g)
    scores = Dict{String,Tuple{Int,Int}}()
    while true
        changed = false
        for lhs in g.order,rhs in g.rules[lhs]
            measure = sequence_measure(rhs,scores)
            isnothing(measure) && continue
            if !haskey(scores,lhs) || measure<scores[lhs]
                scores[lhs] = measure
                changed = true
            end
        end
        changed || break
    end
    sentences = Dict{String,Vector{String}}()
    for lhs in sort(g.order;by=lhs->scores[lhs][2])
        selected = first(rhs for rhs in g.rules[lhs] if sequence_measure(rhs,scores)==scores[lhs])
        sentences[lhs] = expand_sequence(selected,sentences)
    end
    scores,sentences
end
function shortest_contexts(g,scores,sentences)
    costs = Dict(g.start=>(0,0))
    parents = Dict{String,Any}()
    productions = number_productions(g)
    while true
        changed = false
        for p in productions
            haskey(costs,p.lhs) || continue
            for (k,s) in enumerate(p.rhs)
                (!is_nonterminal(s) || s==g.start) && continue
                before,after = p.rhs[1:k-1],p.rhs[k+1:end]
                extra = sum((is_nonterminal(x) ? scores[x][1] : 1 for x in vcat(before,after));init=0)
                candidate = (costs[p.lhs][1]+extra,costs[p.lhs][2]+1)
                key = (p.number,k)
                if !haskey(costs,s) || candidate<costs[s] || (candidate==costs[s] && key<parents[s].key)
                    costs[s] = candidate
                    parents[s] = (key=key,lhs=p.lhs,before=before,after=after)
                    changed = true
                end
            end
        end
        changed || break
    end
    contexts = Dict(g.start=>(String[],String[]))
    for s in sort([s for s in g.order if s!=g.start];by=s->costs[s][2])
        parent = parents[s]
        pre,post = contexts[parent.lhs]
        contexts[s] = (
            vcat(pre,expand_sequence(parent.before,sentences)),
            vcat(expand_sequence(parent.after,sentences),post)
        )
    end
    contexts
end
function sets_report(g,sets,sentences)
    passes = sets.passes
    lines = ["passes: nullable=$(passes["nullable"]) first=$(passes["first"]) follow=$(passes["follow"])",""]
    for lhs in g.order
        append!(lines,[lhs,"  nullable: "*(sets.nullable[lhs] ? "yes" : "no"),listed("  first:",terminal_order(sets.first[lhs])),
            listed("  follow:",terminal_order(sets.follow[lhs])),listed("  shortest:",sentences[lhs])])
    end
    lines
end
function first_path(number,token,table,sets)
    queue,parent = [number],Dict(number=>0)
    cursor = 1
    while cursor<=length(queue)
        current = queue[cursor]
        cursor += 1
        for s in table.productions[current].rhs
            if s==token
                path = Int[]
                while current!=number
                    push!(path,current)
                    current = parent[current]
                end
                return reverse(path)
            elseif is_nonterminal(s)
                for p in table.productions
                    if p.lhs==s && !haskey(parent,p.number)
                        parent[p.number] = current
                        push!(queue,p.number)
                    end
                end
                sets.nullable[s] || break
            else
                break
            end
        end
    end
    Int[]
end
function follow_path(lhs,token,g,table,sets)
    queue,paths = [lhs],Dict(lhs=>Int[])
    cursor = 1
    while cursor<=length(queue)
        symbol = queue[cursor]
        cursor += 1
        path = paths[symbol]
        symbol==g.start && token==END_MARKER && return path
        for p in table.productions,(i,s) in enumerate(p.rhs)
            s==symbol || continue
            more,empty = first_sequence(p.rhs[i+1:end],sets.nullable,sets.first)
            token in more && return vcat(path,[p.number])
            if empty && !haskey(paths,p.lhs)
                paths[p.lhs] = vcat(path,[p.number])
                push!(queue,p.lhs)
            end
        end
    end
    Int[]
end
function table_report(g,sets,table,before)
    lines = ["== predict sets =="]
    for p in table.productions
        append!(lines,["$(p.number): $(p.notation)",listed("  predict:",terminal_order(keys(p.predict)))])
    end
    append!(lines,["","== parse table =="])
    tokens = vcat(sets.terminals,[END_MARKER])
    matrix = [vcat([""],tokens)]
    for lhs in g.order
        values = [isempty(table.cells[(lhs,t)]) ? "." : join(
            (entry.number for entry in table.cells[(lhs,t)]),
            "/"
        ) for t in tokens]
        push!(matrix,vcat([lhs],values))
    end
    widths = [maximum(length(row[j]) for row in matrix) for j in eachindex(matrix[1])]
    for row in matrix
        push!(lines,rpad(row[1],widths[1])*join(("  "*lpad(row[j],widths[j]) for j in 2:length(row))))
    end
    append!(lines,["","== conflicts =="])
    isempty(table.conflicts) && push!(lines,"none")
    for conflict in table.conflicts
        lhs,token = conflict.lhs,conflict.token
        push!(lines,"conflict $lhs on $token: $(conflict.kind), chosen $(conflict.chosen)")
        for entry in conflict.entries
            p = table.productions[entry.number]
            path = entry.reason=="FIRST" ? first_path(
                p.number,
                token,
                table,
                sets
            ) : follow_path(lhs,token,g,table,sets)
            reason = entry.reason*(isempty(path) ? "" : listed(" via",path))
            push!(lines,"  $(p.number): $(p.notation) ($reason)")
        end
    end
    append!(
        lines,
        ["LL(1): "*(isempty(table.conflicts) ? "yes" : "no"),"conflicts before transformation: $before"]
    )
    lines
end
function compact_tree(root)
    children = ParseNode[]
    for original in root.children
        original.symbol=="%empty" && continue
        child = compact_tree(original)
        if is_nonterminal(child.symbol) && isempty(child.mark) && isempty(child.children)
            continue
        elseif is_nonterminal(child.symbol) && occursin("'",child.symbol) && isempty(child.mark)
            append!(children,child.children)
        else
            push!(children,child)
        end
    end
    length(children)==1 && isempty(root.mark) ? children[1] : ParseNode(root.symbol,root.mark,children)
end
tree_label(node) = node.symbol*(isempty(node.mark) ? "" : " ($(node.mark))")
function tree_lines(root)
    lines = [tree_label(root)]
    pending = Tuple{ParseNode,String,Bool}[]
    for i in length(root.children):-1:1
        push!(pending,(root.children[i],"",i==length(root.children)))
    end
    while !isempty(pending)
        node,prefix,last_child = pop!(pending)
        push!(lines,prefix*(last_child ? "`-- " : "|-- ")*tree_label(node))
        next_prefix = prefix*(last_child ? "    " : "|   ")
        for i in length(node.children):-1:1
            push!(pending,(node.children[i],next_prefix,i==length(node.children)))
        end
    end
    lines
end
function trace_lines(trace)
    rows = vcat(
        [("step","stack","input","action")],
        [(string(row.step),join(row.stack," "),join(row.input," "),row.action) for row in trace]
    )
    widths = [maximum(length(row[j]) for row in rows) for j in 1:3]
    [join((rpad(row[j],widths[j])*"  " for j in 1:3))*row[4] for row in rows]
end
function error_strings(events,sets,table)
    errors = String[]
    for e in events
        unexpected = e.token==END_MARKER ? "end of input" : "\"$(e.token)\" at token $(e.position)"
        if is_nonterminal(e.symbol)
            names = [t for t in vcat(sets.terminals,[END_MARKER]) if haskey(table.choices,(e.symbol,t))]
            expected = join((t==END_MARKER ? t : "\"$t\"" for t in names)," ")
        else
            expected = e.symbol==END_MARKER ? END_MARKER : "\"$(e.symbol)\""
        end
        recovery = e.kind=="skip" ? "skipped \"$(e.token)\"" : e.kind=="pop" ? "popped $(e.symbol)" : "inserted \"$(e.symbol)\""
        push!(errors,"step $(e.step): unexpected $unexpected; expected $expected; $recovery")
    end
    errors
end
function leftmost_derivation(start,numbers,productions)
    symbols,lines = [start],["  $start"]
    for number in numbers
        position = findfirst(is_nonterminal,symbols)
        splice!(symbols,position:position,productions[number].rhs)
        push!(lines,"  => "*format_alternative(symbols))
    end
    lines
end
function recognize_language(g,tokens)
    productions = number_productions(g)
    rhs(p) = p==0 ? [g.start] : productions[p].rhs
    lhs(p) = p==0 ? "" : productions[p].lhs
    n = length(tokens)
    charts = [Set{NTuple{3,Int}}() for _ in 0:n]
    pending = [NTuple{3,Int}[] for _ in 0:n]
    function add!(position,item)
        if !(item in charts[position+1])
            push!(charts[position+1],item)
            push!(pending[position+1],item)
        end
    end
    add!(0,(0,0,0))
    for position in 0:n
        cursor = 1
        while cursor<=length(pending[position+1])
            p,dot,origin = pending[position+1][cursor]
            cursor += 1
            body = rhs(p)
            if dot==length(body)
                for (a,consumed,start) in copy(pending[origin+1])
                    outer = rhs(a)
                    consumed<length(outer) && outer[consumed+1]==lhs(p) && add!(position,(a,consumed+1,start))
                end
            elseif is_nonterminal(body[dot+1])
                next = body[dot+1]
                for child in productions
                    child.lhs==next && add!(position,(child.number,0,position))
                end
                for (a,consumed,start) in copy(pending[position+1])
                    lhs(a)==next && consumed==length(rhs(a)) && start==position && add!(
                        position,
                        (p,dot+1,origin)
                    )
                end
            elseif position<n && body[dot+1]==tokens[position+1]
                add!(position+1,(p,dot+1,origin))
            end
        end
    end
    (0,1,0) in charts[n+1]
end
function parse_input(tokens,g,sets,table,cleaned)
    kept,unknown = Tuple{String,Int}[],String[]
    for (i,t) in enumerate(tokens)
        if t in sets.terminals
            push!(kept,(t,i))
        else
            push!(unknown,"unknown \"$t\" at token $i; removed")
        end
    end
    parsed = parse_tokens(kept,g,sets,table)
    errors = vcat(unknown,error_strings(parsed.events,sets,table))
    (
        ;parsed...,
        original=tokens,
        unknown=unknown,
        errors=errors,
        accepted=isempty(errors),
        language=recognize_language(cleaned,tokens)
    )
end
function parses_report(parses,g,sets,table,sentences,contexts)
    lines = String[]
    for (i,p) in enumerate(parses)
        append!(lines,["== input $i ==",listed("tokens:",p.original)])
        append!(lines,trace_lines(p.trace))
        push!(
            lines,
            listed("left parse:",p.left_parse),
            "stats: steps=$(length(p.trace)) predicts=$(p.counts["predict"]) matches=$(p.counts["match"]) max_stack=$(p.counts["max_stack"])"
        )
        if !isempty(p.errors)
            push!(lines,"errors:")
            append!(lines,["  $error" for error in p.errors])
        end
        push!(
            lines,
            p.accepted ? "result: accepted" : "result: rejected (errors: $(length(p.errors)))",
            "language: "*(p.language ? "yes" : "no")
        )
        if p.accepted
            push!(lines,"derivation:")
            append!(lines,leftmost_derivation(g.start,p.left_parse,table.productions))
        end
        push!(lines,"tree:")
        append!(lines,tree_lines(p.root))
        push!(lines,"compact tree:")
        append!(lines,tree_lines(compact_tree(p.root)))
        push!(lines,"")
    end
    used = Set(number for p in parses for number in p.left_parse)
    unused = [p for p in table.productions if !(p.number in used)]
    accepted,in_language = count(p->p.accepted,parses),count(p->p.language,parses)
    mismatches = [i for (i,p) in enumerate(parses) if p.accepted!=p.language]
    push!(lines,"== summary ==","inputs=$(length(parses)) accepted=$accepted rejected=$(length(parses)-accepted) in_language=$in_language",listed("mismatches:",mismatches),
        "recovery: unknown=$(sum(length(p.unknown) for p in parses)) skip=$(sum(p.counts["skip"] for p in parses)) pop=$(sum(p.counts["pop"] for p in parses)) missing=$(sum(p.counts["missing"] for p in parses))",
        "coverage: $(length(used)) of $(length(table.productions)) productions used",listed(
            "unused:",
            [p.number for p in unused]
        ))
    for p in unused
        prefix,suffix = contexts[p.lhs]
        sentence = vcat(prefix,expand_sequence(p.rhs,sentences),suffix)
        parsed = parse_tokens([(word,i) for (i,word) in enumerate(sentence)],g,sets,table)
        errors = length(parsed.events)
        push!(lines,"  $(p.number): $(p.notation)",listed("    example:",sentence),errors==0 ? "    result: accepted" : "    result: rejected (errors: $errors)",
            "    used: "*(p.number in parsed.left_parse ? "yes" : "no"))
    end
    lines
end
function main()
    source = parse_grammar()
    cleaned,clean_diags = clean_grammar(source.grammar)
    recursion_diags = left_recursion_diagnostics(cleaned)
    recursion,recursion_log = eliminate_left_recursion(cleaned)
    factored,factor_log = left_factor(recursion)
    reached = reachable(factored)
    removed = [lhs for lhs in factored.order if !(lhs in reached)]
    final = retain_grammar(factored,[lhs for lhs in factored.order if lhs in reached])
    final_log = ["remove unreachable $lhs" for lhs in removed]
    diagnostics = copy(source.diagnostics)
    if source.has_declaration
        append!(
            diagnostics,
            ["undeclared terminal $t at line $(source.words[t])" for t in sort(collect(keys(source.words))) if !(t in source.declared)]
        )
    end
    append!(diagnostics,clean_diags)
    append!(diagnostics,recursion_diags)
    append!(diagnostics,["unreachable after transformation $lhs" for lhs in removed])
    if source.has_declaration
        append!(
            diagnostics,
            ["unused token $t" for t in sort(collect(setdiff(source.declared,terminals_of(final))))]
        )
    end
    before = build_table(cleaned,analyze_sets(cleaned))
    sets = analyze_sets(final)
    table = build_table(final,sets)
    scores,sentences = shortest_sentences(final)
    contexts = shortest_contexts(final,scores,sentences)
    inputs = [isempty(line) ? String[] : String.(split(line,' ')) for line in readlines("input/inputs.txt")]
    parses = [parse_input(tokens,final,sets,table,cleaned) for tokens in inputs]
    push!(
        diagnostics,
        isempty(table.conflicts) ? "result: LL(1)" : "result: not LL(1) (conflicts: $(length(table.conflicts)))"
    )
    reports = [("grammar.txt",grammar_report(cleaned,recursion,factored,final,recursion_log,factor_log,final_log)),
        ("sets.txt",sets_report(final,sets,sentences)),(
            "table.txt",
            table_report(final,sets,table,length(before.conflicts))
        ),
        (
            "parses.txt",
            parses_report(parses,final,sets,table,sentences,contexts)
        ),("diagnostics.txt",diagnostics)]
    for (name,lines) in reports
        open(joinpath("output",name),"w") do io
            for line in lines
                println(io,line)
            end
        end
    end
end
main()
