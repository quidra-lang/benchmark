struct AutomatonError <: Exception
    reason::String
end
a_fail(reason) = throw(AutomatonError(reason))

mutable struct FiniteAutomaton
    deterministic::Bool
    names::Vector{String}
    alphabet::Vector{Char}
    start::Int
    accepting::Set{Int}
    transitions::Dict{Tuple{Int,Char},Set{Int}}
end
FiniteAutomaton(alphabet; deterministic=false) = FiniteAutomaton(deterministic,String[],sort!(collect(alphabet)),1,Set{Int}(),Dict{Tuple{Int,Char},Set{Int}}())
function a_state!(a,name)
    push!(a.names,name)
    length(a.names)
end
function a_edge!(a,p,c,q)
    push!(get!(a.transitions,(p,c),Set{Int}()),q)
end
a_destinations(a,p,c) = get(a.transitions,(p,c),Set{Int}())
a_delta(a,p,c) = only(a_destinations(a,p,c))
a_set_key(states) = Tuple(sort!(collect(states)))
a_list(a,states) = isempty(states) ? "none" : join((a.names[i] for i in sort!(collect(states))),",")
a_set_text(a,states) = "{" * (isempty(states) ? "" : a_list(a,states)) * "}"
a_accepts(a,states) = !isdisjoint(a.accepting,states)
a_transition_count(a) = sum(length(destinations) for destinations in values(a.transitions);init=0)
a_epsilon_count(a) = sum(length(destinations) for ((p,c),destinations) in a.transitions if c == 'e';init=0)
a_summary(a,name) = "$(a.deterministic ? "DFA" : "NFA") $name: alphabet=$(join(a.alphabet)) states=$(length(a.names)) accepting=$(length(a.accepting)) transitions=$(a_transition_count(a))"
a_printed_word(word) = isempty(word) ? "e" : word
function a_closure(a,states)
    result = Set(states)
    pending = collect(states)
    while !isempty(pending)
        p = pop!(pending)
        for q in a_destinations(a,p,'e')
            if !(q in result)
                push!(result,q)
                push!(pending,q)
            end
        end
    end
    result
end
function a_move(a,states,c)
    destination = Set{Int}()
    for p in states
        union!(destination,a_destinations(a,p,c))
    end
    a_closure(a,destination)
end
a_initial(a) = a_closure(a,Set([a.start]))
function a_reach(a; reverse=false)
    adjacency = [Set{Int}() for _ in a.names]
    for ((p,c),destinations) in a.transitions, q in destinations
        push!(adjacency[reverse ? q : p],reverse ? p : q)
    end
    seen = reverse ? copy(a.accepting) : Set([a.start])
    pending = collect(seen)
    while !isempty(pending)
        p = pop!(pending)
        for q in adjacency[p]
            if !(q in seen)
                push!(seen,q)
                push!(pending,q)
            end
        end
    end
    seen
end
function a_determinize(source)
    result = FiniteAutomaton(source.alphabet;deterministic=true)
    subsets = [a_initial(source)]
    indices = Dict{Tuple,Int}(a_set_key(subsets[1])=>1)
    a_state!(result,"D0")
    i = 1
    while i <= length(subsets)
        states = subsets[i]
        a_accepts(source,states) && push!(result.accepting,i)
        for c in result.alphabet
            destination = a_move(source,states,c)
            key = a_set_key(destination)
            if !haskey(indices,key)
                push!(subsets,destination)
                indices[key] = length(subsets)
                a_state!(result,"D$(length(subsets)-1)")
            end
            a_edge!(result,i,c,indices[key])
        end
        i += 1
    end
    result, subsets
end
function a_minimize(source)
    reachable = a_reach(source)
    unreachable = setdiff(Set(eachindex(source.names)),reachable)
    blocks = [sort!(collect(intersect(reachable,source.accepting))),sort!(collect(setdiff(reachable,source.accepting)))]
    filter!(!isempty,blocks)
    sort!(blocks;by=first)
    partition_text(blocks) = join((a_set_text(source,block) for block in blocks)," ")
    lines = ["  unreachable: " * a_list(source,unreachable),"  round 0: " * partition_text(blocks)]
    round = 0
    while true
        membership = Dict(p=>i for (i,block) in enumerate(blocks) for p in block)
        next = Vector{Int}[]
        for block in blocks
            groups = Dict{Tuple,Vector{Int}}()
            for p in block
                signature = Tuple(membership[a_delta(source,p,c)] for c in source.alphabet)
                push!(get!(groups,signature,Int[]),p)
            end
            append!(next,values(groups))
        end
        length(next) == length(blocks) && break
        blocks = sort!(next;by=first)
        round += 1
        push!(lines,"  round $round: " * partition_text(blocks))
    end
    membership = Dict(p=>i for (i,block) in enumerate(blocks) for p in block)
    sequence = [membership[source.start]]
    indices = Dict(sequence[1]=>1)
    result = FiniteAutomaton(source.alphabet;deterministic=true)
    a_state!(result,"M0")
    i = 1
    while i <= length(sequence)
        block = blocks[sequence[i]]
        p = first(block)
        p in source.accepting && push!(result.accepting,i)
        for c in source.alphabet
            destination = membership[a_delta(source,p,c)]
            if !haskey(indices,destination)
                push!(sequence,destination)
                indices[destination] = length(sequence)
                a_state!(result,"M$(length(sequence)-1)")
            end
            a_edge!(result,i,c,indices[destination])
        end
        push!(lines,"  M$(i-1) = " * a_set_text(source,block))
        i += 1
    end
    result, lines
end
function a_language(source; count_words=false)
    a = a_determinize(source)[1]
    pending = [(a.start,"")]
    seen = Set([a.start])
    smallest = nothing
    i = 1
    while i <= length(pending)
        p, word = pending[i]
        smallest === nothing && p in a.accepting && (smallest=word)
        for c in a.alphabet
            q = a_delta(a,p,c)
            if !(q in seen)
                push!(seen,q)
                push!(pending,(q,word*c))
            end
        end
        i += 1
    end
    smallest === nothing && return (false,0,nothing)
    live = a_reach(a;reverse=true)
    color = zeros(Int,length(a.names))
    counts = zeros(Int,length(a.names))
    infinite = false
    function visit(p)
        p in live || return 0
        if color[p] == 1
            infinite = true
            return 0
        elseif color[p] == 2
            return counts[p]
        end
        color[p] = 1
        total = count_words ? Int(p in a.accepting) : 0
        for c in a.alphabet
            suffixes = visit(a_delta(a,p,c))
            count_words && !infinite && (total += suffixes)
        end
        color[p] = 2
        counts[p] = total
    end
    amount = visit(a.start)
    infinite, amount, smallest
end

struct RegexTree
    operation::Char
    children::Vector{RegexTree}
end
mutable struct RegexParser
    text::String
    position::Int
end
a_regex_next(p) = p.position <= length(p.text) ? p.text[p.position] : '\0'
a_regex_start(c) = 'a' <= c <= 'z' || '0' <= c <= '9' || c == '('
a_regex_error(p) = a_fail("syntax error at $(p.position)")
function a_regex_atom!(p)
    c = a_regex_next(p)
    if c == '('
        p.position += 1
        result = a_regex_alternation!(p)
        a_regex_next(p) == ')' || a_regex_error(p)
        p.position += 1
        return result
    elseif a_regex_start(c)
        p.position += 1
        return RegexTree(c,RegexTree[])
    end
    a_regex_error(p)
end
function a_regex_factor!(p)
    result = a_regex_atom!(p)
    while a_regex_next(p) in ('*','+','?')
        operation = a_regex_next(p)
        p.position += 1
        result = RegexTree(operation,[result])
    end
    result
end
function a_regex_concatenation!(p)
    parts = [a_regex_factor!(p)]
    while a_regex_start(a_regex_next(p))
        push!(parts,a_regex_factor!(p))
    end
    length(parts) == 1 ? only(parts) : RegexTree('.',parts)
end
function a_regex_alternation!(p)
    parts = [a_regex_concatenation!(p)]
    while a_regex_next(p) == '|'
        p.position += 1
        push!(parts,a_regex_concatenation!(p))
    end
    length(parts) == 1 ? only(parts) : RegexTree('|',parts)
end
function a_thompson(text,alphabet)
    parser = RegexParser(text,1)
    tree = a_regex_alternation!(parser)
    a_regex_next(parser) == '\0' || a_regex_error(parser)
    result = FiniteAutomaton(alphabet)
    state() = a_state!(result,"N$(length(result.names))")
    function build(node)
        operation = node.operation
        if isempty(node.children)
            start, finish = state(),state()
            a_edge!(result,start,operation,finish)
            return start,finish
        elseif operation == '.'
            parts = [build(child) for child in node.children]
            for i in 1:length(parts)-1
                a_edge!(result,parts[i][2],'e',parts[i+1][1])
            end
            return parts[1][1],parts[end][2]
        end
        start = state()
        parts = [build(child) for child in node.children]
        finish = state()
        for (entry,exit) in parts
            a_edge!(result,start,'e',entry)
            a_edge!(result,exit,'e',finish)
            operation in ('*','+') && a_edge!(result,exit,'e',entry)
        end
        operation in ('*','?') && a_edge!(result,start,'e',finish)
        start,finish
    end
    entry_exit = build(tree)
    result.start = entry_exit[1]
    push!(result.accepting,entry_exit[2])
    result
end
function a_state_index(a,name)
    index = findfirst(==(name),a.names)
    index === nothing && a_fail("unknown state $name")
    index
end
a_lookup(table,name) = findfirst(pair -> first(pair) == name,table)
function a_register!(table,name,automaton,details=String[])
    lines = vcat([a_summary(automaton,name)],details)
    push!(table,name=>automaton)
    lines
end
function a_definition!(table,command,args)
    length(args) >= 5 || a_fail("wrong number of arguments")
    name, states_text, alphabet, start, accepting = args[1:5]
    a_lookup(table,name) !== nothing && a_fail("$name already exists")
    a = FiniteAutomaton(alphabet;deterministic=command == "DFA")
    for state in split(states_text,',')
        state in a.names && a_fail("duplicate state $state")
        a_state!(a,String(state))
    end
    a.start = a_state_index(a,start)
    if accepting != "-"
        for state in split(accepting,',')
            index = a_state_index(a,state)
            index in a.accepting && a_fail("duplicate state $state")
            push!(a.accepting,index)
        end
    end
    for transition in args[6:end]
        p_text,c_text,q_text = split(transition,':')
        p = a_state_index(a,p_text)
        c = only(c_text)
        c == 'e' && a.deterministic && a_fail("epsilon transition in DFA")
        c != 'e' && !(c in a.alphabet) && a_fail("unknown symbol $c")
        q = a_state_index(a,q_text)
        q in a_destinations(a,p,c) && a_fail("duplicate transition $transition")
        a.deterministic && !isempty(a_destinations(a,p,c)) && a_fail("conflicting transition $transition")
        a_edge!(a,p,c,q)
    end
    if a.deterministic
        for p in eachindex(a.names), c in a.alphabet
            isempty(a_destinations(a,p,c)) && a_fail("missing transition $(a.names[p]):$c")
        end
    end
    a_register!(table,name,a)
end
function a_product(a,b,operation)
    result = FiniteAutomaton(a.alphabet;deterministic=true)
    sequence = [(a.start,b.start)]
    indices = Dict(sequence[1]=>1)
    lines = String[]
    a_state!(result,"P0")
    i = 1
    while i <= length(sequence)
        p,q = sequence[i]
        left,right = p in a.accepting,q in b.accepting
        accepted = operation == "UNION" ? left || right : operation == "INTERSECT" ? left && right : left && !right
        accepted && push!(result.accepting,i)
        for c in a.alphabet
            destination = (a_delta(a,p,c),a_delta(b,q,c))
            if !haskey(indices,destination)
                push!(sequence,destination)
                indices[destination] = length(sequence)
                a_state!(result,"P$(length(sequence)-1)")
            end
            a_edge!(result,i,c,indices[destination])
        end
        push!(lines,"  P$(i-1) = ($(a.names[p]),$(b.names[q]))")
        i += 1
    end
    result,lines
end
const A_ROLES = Dict("ACCEPT"=>"ro","CLOSURE"=>"ro","ENUM"=>"ro","COUNT"=>"ro",
    "TODFA"=>"rn","EPSFREE"=>"rn","REVERSE"=>"rn","STAR"=>"rn","MINIMIZE"=>"dn","COMPLEMENT"=>"dn",
    "EQUIV"=>"rr","UNION"=>"ddn","INTERSECT"=>"ddn","DIFF"=>"ddn","CONCAT"=>"rrn",
    "EMPTY"=>"r","FINITE"=>"r","INFO"=>"r","TABLE"=>"r","SHOW"=>"r","DELETE"=>"r","SYNC"=>"d","LIST"=>"")
function a_command!(table,line)
    startswith(line,'#') && return String[]
    words = String.(split(line,' '))
    command,args = first(words),words[2:end]
    command in ("DFA","NFA") && return a_definition!(table,command,args)
    if command == "REGEX"
        length(args) == 3 || a_fail("wrong number of arguments")
        a_lookup(table,args[1]) !== nothing && a_fail("$(args[1]) already exists")
        for c in args[3]
            (('a' <= c <= 'z' || '0' <= c <= '9') && c != 'e' && !(c in args[2])) && a_fail("unknown symbol $c")
        end
        return a_register!(table,args[1],a_thompson(args[3],args[2]))
    end
    haskey(A_ROLES,command) || a_fail("unknown command $command")
    roles = A_ROLES[command]
    length(args) == length(roles) || a_fail("wrong number of arguments")
    for (argument,role) in zip(args,roles)
        role in ('r','d') && a_lookup(table,argument) === nothing && a_fail("unknown automaton $argument")
    end
    for (argument,role) in zip(args,roles)
        role == 'n' && a_lookup(table,argument) !== nothing && a_fail("$argument already exists")
    end
    for (argument,role) in zip(args,roles)
        role == 'd' && !table[a_lookup(table,argument)].second.deterministic && a_fail("$argument is not a DFA")
    end
    if command == "LIST"
        return isempty(table) ? ["(none)"] : [a_summary(pair.second,pair.first) for pair in table]
    end
    a = table[a_lookup(table,args[1])].second
    b = nothing
    if command in ("EQUIV","UNION","INTERSECT","DIFF","CONCAT")
        b = table[a_lookup(table,args[2])].second
        a.alphabet == b.alphabet || a_fail("alphabets differ")
    end
    if command == "ACCEPT"
        word = args[2] == "e" ? "" : args[2]
        for c in word
            c in a.alphabet || a_fail("unknown symbol $c")
        end
        states = a_initial(a)
        state_text(states) = a.deterministic ? a.names[only(states)] : a_set_text(a,states)
        trace = state_text(states)
        for c in word
            states = a_move(a,states,c)
            trace *= " -$c-> " * state_text(states)
        end
        return [(a_accepts(a,states) ? "ACCEPT " : "REJECT ") * trace]
    elseif command == "CLOSURE"
        states = Set(a_state_index(a,name) for name in split(args[2],','))
        return [a_set_text(a,a_closure(a,states))]
    elseif command == "TODFA"
        result, subsets = a_determinize(a)
        return a_register!(table,args[2],result,["  D$(i-1) = " * a_set_text(a,states) for (i,states) in enumerate(subsets)])
    elseif command == "MINIMIZE"
        result,details = a_minimize(a)
        return a_register!(table,args[2],result,details)
    elseif command == "EPSFREE"
        result = FiniteAutomaton(a.alphabet)
        result.names = copy(a.names)
        result.start = a.start
        for p in eachindex(a.names)
            closed = a_closure(a,Set([p]))
            a_accepts(a,closed) && push!(result.accepting,p)
            for c in a.alphabet, q in a_move(a,closed,c)
                a_edge!(result,p,c,q)
            end
        end
        return a_register!(table,args[2],result)
    elseif command == "COMPLEMENT"
        result = deepcopy(a)
        result.accepting = setdiff(Set(eachindex(a.names)),a.accepting)
        return a_register!(table,args[2],result)
    elseif command in ("UNION","INTERSECT","DIFF")
        result,details = a_product(a,b,command)
        return a_register!(table,args[3],result,details)
    elseif command == "EQUIV"
        left,right = a_determinize(a)[1],a_determinize(b)[1]
        pending = [(left.start,right.start,"")]
        seen = Set([(left.start,right.start)])
        i = 1
        while i <= length(pending)
            p,q,word = pending[i]
            if (p in left.accepting) != (q in right.accepting)
                owner = p in left.accepting ? args[1] : args[2]
                return ["NOT EQUIVALENT: $(a_printed_word(word)) is accepted only by $owner"]
            end
            for c in a.alphabet
                destination = (a_delta(left,p,c),a_delta(right,q,c))
                if !(destination in seen)
                    push!(seen,destination)
                    push!(pending,(destination[1],destination[2],word*c))
                end
            end
            i += 1
        end
        return ["EQUIVALENT"]
    elseif command in ("REVERSE","CONCAT","STAR")
        result = FiniteAutomaton(a.alphabet)
        amount = command == "CONCAT" ? length(a.names)+length(b.names) : length(a.names)+1
        for i in 0:amount-1
            a_state!(result,"N$i")
        end
        offset = command == "CONCAT" ? 0 : 1
        for ((p,c),destinations) in a.transitions, q in destinations
            command == "REVERSE" ? a_edge!(result,q+1,c,p+1) : a_edge!(result,p+offset,c,q+offset)
        end
        if command == "REVERSE"
            push!(result.accepting,a.start+1)
            for p in a.accepting
                a_edge!(result,1,'e',p+1)
            end
        elseif command == "STAR"
            union!(result.accepting,Set([1]),Set(p+1 for p in a.accepting))
            a_edge!(result,1,'e',a.start+1)
            for p in a.accepting
                a_edge!(result,p+1,'e',a.start+1)
            end
        else
            offset = length(a.names)
            result.start = a.start
            result.accepting = Set(p+offset for p in b.accepting)
            for ((p,c),destinations) in b.transitions, q in destinations
                a_edge!(result,p+offset,c,q+offset)
            end
            for p in a.accepting
                a_edge!(result,p,'e',b.start+offset)
            end
        end
        return a_register!(table,command == "CONCAT" ? args[3] : args[2],result)
    elseif command in ("COUNT","ENUM")
        dfa = a_determinize(a)[1]
        limit = parse(Int,args[2])
        if command == "COUNT"
            counts = zeros(Int,length(dfa.names))
            counts[dfa.start] = 1
            for _ in 1:limit
                next = zeros(Int,length(dfa.names))
                for p in eachindex(dfa.names), c in dfa.alphabet
                    next[a_delta(dfa,p,c)] += counts[p]
                end
                counts = next
            end
            return [string(sum(counts[p] for p in dfa.accepting;init=0))]
        end
        pending = [(dfa.start,"")]
        total = 0
        first_words = String[]
        i = 1
        while i <= length(pending)
            p,word = pending[i]
            if p in dfa.accepting
                total += 1
                length(first_words) < 50 && push!(first_words,a_printed_word(word))
            end
            if length(word) < limit
                for c in dfa.alphabet
                    push!(pending,(a_delta(dfa,p,c),word*c))
                end
            end
            i += 1
        end
        return [join(vcat([string(total)],first_words,total > 50 ? ["..."] : String[])," ")]
    elseif command in ("EMPTY","FINITE")
        infinite,amount,smallest = a_language(a;count_words=command == "FINITE")
        command == "EMPTY" && return [smallest === nothing ? "EMPTY" : "NOT EMPTY " * a_printed_word(smallest)]
        return [infinite ? "INFINITE" : "FINITE $amount"]
    elseif command == "SYNC"
        initial = Set(eachindex(a.names))
        pending = [(initial,"")]
        seen = Set{Tuple}([a_set_key(initial)])
        i = 1
        while i <= length(pending)
            states,word = pending[i]
            length(states) == 1 && return ["SYNCHRONIZING $(a_printed_word(word)) -> $(a.names[only(states)])"]
            for c in a.alphabet
                destination = Set(a_delta(a,p,c) for p in states)
                key = a_set_key(destination)
                if !(key in seen)
                    push!(seen,key)
                    push!(pending,(destination,word*c))
                end
            end
            i += 1
        end
        return ["NOT SYNCHRONIZING"]
    elseif command == "INFO"
        infinite,amount,smallest = a_language(a)
        deterministic = a_epsilon_count(a) == 0 && all(length(a_destinations(a,p,c)) <= 1 for p in eachindex(a.names) for c in a.alphabet)
        complete = all(!isempty(a_destinations(a,p,c)) for p in eachindex(a.names) for c in a.alphabet)
        minimal = a_minimize(a_determinize(a)[1])[1]
        return [a_summary(a,args[1]),"  epsilon transitions: $(a_epsilon_count(a))",
            "  reachable: " * a_list(a,a_reach(a)),"  live: " * a_list(a,a_reach(a;reverse=true)),
            "  deterministic: $(deterministic ? "yes" : "no")","  complete: $(complete ? "yes" : "no")",
            "  language: $(smallest === nothing ? "empty" : infinite ? "infinite" : "finite")","  minimal DFA states: $(length(minimal.names))"]
    elseif command == "SHOW"
        words = [a.deterministic ? "DFA" : "NFA",args[1],join(a.names,","),join(a.alphabet),a.names[a.start],isempty(a.accepting) ? "-" : a_list(a,a.accepting)]
        for p in eachindex(a.names), c in vcat(a.alphabet,['e']), q in sort!(collect(a_destinations(a,p,c)))
            push!(words,"$(a.names[p]):$c:$(a.names[q])")
        end
        return [join(words," ")]
    elseif command == "TABLE"
        symbols = a_epsilon_count(a) == 0 ? a.alphabet : vcat(a.alphabet,['e'])
        rows = [vcat([""],string.(symbols))]
        for p in eachindex(a.names)
            row = [(p == a.start ? "->" : "  ") * (p in a.accepting ? "*" : " ") * a.names[p]]
            for c in symbols
                destinations = a_destinations(a,p,c)
                push!(row,a.deterministic ? a.names[only(destinations)] : isempty(destinations) ? "-" : a_set_text(a,destinations))
            end
            push!(rows,row)
        end
        widths = [maximum(length(row[i]) for row in rows) for i in eachindex(rows[1])]
        return [rstrip(join((rpad(cell,widths[i]) for (i,cell) in enumerate(row)),"  "),' ') for row in rows]
    elseif command == "DELETE"
        deleteat!(table,a_lookup(table,args[1]))
        return ["deleted $(args[1])"]
    end
    String[]
end
function main()
    count = parse(Int,readline())
    table = Pair{String,FiniteAutomaton}[]
    for _ in 1:count
        line = readline()
        try
            foreach(println,a_command!(table,line))
        catch error
            error isa AutomatonError || rethrow()
            println("error: $(error.reason)")
        end
    end
end
main()
