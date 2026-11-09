struct LogicError <: Exception
    reason::String
end
b_fail(reason) = throw(LogicError(reason))

mutable struct Formula
    operation::String
    children::Vector{Formula}
end
b_leaf(text) = Formula(string(text), Formula[])
b_node(operation, children...) = Formula(operation, collect(children))
b_constant(value) = b_leaf(value ? "1" : "0")
b_isconstant(f, value) = isempty(f.children) && f.operation == (value ? "1" : "0")
b_variable(f) = isempty(f.children) && f.operation != "0" && f.operation != "1"
const B_PRECEDENCE = Dict("<->"=>1, "->"=>2, "|"=>3, "^"=>4, "&"=>5, "~"=>6)
b_precedence(f) = get(B_PRECEDENCE, f.operation, 7)
function b_equal(a, b)
    a === b || (a.operation == b.operation && length(a.children) == length(b.children) && all(b_equal(x,y) for (x,y) in zip(a.children,b.children)))
end
function b_text(f)
    isempty(f.children) && return f.operation
    if f.operation == "~"
        child = f.children[1]
        text = b_text(child)
        return "~" * (length(child.children) == 2 ? "(" * text * ")" : text)
    end
    a, b = f.children
    left, right = b_text(a), b_text(b)
    if b_precedence(a) < b_precedence(f) || a.operation == f.operation == "->"
        left = "(" * left * ")"
    end
    if b_precedence(b) < b_precedence(f) || (b.operation == f.operation && f.operation != "->")
        right = "(" * right * ")"
    end
    left * " " * f.operation * " " * right
end
function b_variables(formulas...)
    result = Set{Char}()
    function visit(f)
        if b_variable(f)
            push!(result, only(f.operation))
        else
            foreach(visit, f.children)
        end
    end
    foreach(visit, formulas)
    sort!(collect(result))
end
b_size(f) = 1 + sum(b_size(child) for child in f.children; init=0)
b_depth(f) = 1 + maximum((b_depth(child) for child in f.children); init=0)

struct LogicToken
    text::String
    position::Int
end
mutable struct LogicParser
    tokens::Vector{LogicToken}
    position::Int
    finish::Int
    definitions::Dict{String,Formula}
end
function b_lex(text, start)
    tokens = LogicToken[]
    i = 1
    while i <= length(text)
        c = text[i]
        if c == ' '
            i += 1
            continue
        end
        first = i
        if i + 2 <= length(text) && text[i:i+2] == "<->"
            i += 3
        elseif i + 1 <= length(text) && text[i:i+1] == "->"
            i += 2
        elseif 'a' <= c <= 'z'
            i += 1
            while i <= length(text) && ('a' <= text[i] <= 'z' || '0' <= text[i] <= '9')
                i += 1
            end
        elseif 'A' <= c <= 'Z' || c in "01~&^|()"
            i += 1
        else
            b_fail("invalid character '$c' at $(start+i-1)")
        end
        push!(tokens, LogicToken(text[first:i-1], start + first - 1))
    end
    tokens
end
b_peek(p) = p.position <= length(p.tokens) ? p.tokens[p.position].text : ""
function b_unexpected(p)
    p.position > length(p.tokens) && b_fail("unexpected end of formula at $(p.finish)")
    token = p.tokens[p.position]
    b_fail("unexpected '$(token.text)' at $(token.position)")
end
function b_unary!(p)
    text = b_peek(p)
    if text == "~"
        p.position += 1
        return b_node("~", b_unary!(p))
    elseif text == "("
        p.position += 1
        result = b_binary!(p, 1)
        b_peek(p) == ")" || b_unexpected(p)
        p.position += 1
        return result
    elseif length(text) == 1 && ('A' <= text[1] <= 'Z' || text in ("0", "1"))
        p.position += 1
        return b_leaf(text)
    elseif !isempty(text) && 'a' <= text[1] <= 'z'
        token = p.tokens[p.position]
        haskey(p.definitions, text) || b_fail("undefined name '$text' at $(token.position)")
        p.position += 1
        return p.definitions[text]
    end
    b_unexpected(p)
end
function b_binary!(p, minimum)
    left = b_unary!(p)
    while true
        operation = b_peek(p)
        precedence = get(B_PRECEDENCE, operation, 0)
        (operation == "~" || precedence < minimum) && break
        p.position += 1
        right = b_binary!(p, precedence + Int(operation != "->"))
        left = b_node(operation, left, right)
    end
    left
end
function b_parse(text, start, definitions)
    p = LogicParser(b_lex(text, start), 1, start + length(text), definitions)
    result = b_binary!(p, 1)
    isempty(b_peek(p)) || b_unexpected(p)
    result
end

function b_nnf(formula)
    positive, negative = IdDict{Formula,Formula}(), IdDict{Formula,Formula}()
    function visit(f, sign)
        memo = sign ? positive : negative
        haskey(memo, f) && return memo[f]
        operation = f.operation
        if b_variable(f)
            result = sign ? f : b_node("~", f)
        elseif isempty(f.children)
            result = b_constant((operation == "1") == sign)
        elseif operation == "~"
            result = visit(f.children[1], !sign)
        else
            a, b = f.children
            if operation in ("&", "|")
                result = b_node(sign ? operation : (operation == "&" ? "|" : "&"), visit(a,sign), visit(b,sign))
            elseif operation == "->"
                result = b_node(sign ? "|" : "&", visit(a,!sign), visit(b,sign))
            else
                equal = operation == "<->" ? sign : !sign
                result = b_node("|", b_node("&",visit(a,true),visit(b,equal)), b_node("&",visit(a,false),visit(b,!equal)))
            end
        end
        memo[f] = result
    end
    visit(formula, true)
end
function b_dual(f)
    b_variable(f) && return f
    isempty(f.children) && return b_constant(f.operation == "0")
    children = b_dual.(f.children)
    f.operation == "~" && return b_node("~", children[1])
    f.operation == "->" && return b_node("&", b_node("~",children[1]), children[2])
    operation = Dict("&"=>"|", "|"=>"&", "^"=>"<->", "<->"=>"^")[f.operation]
    b_node(operation, children...)
end
function b_negate(f)
    b_isconstant(f,false) && return b_leaf("1")
    b_isconstant(f,true) && return b_leaf("0")
    f.operation == "~" ? f.children[1] : b_node("~",f)
end
function b_simplify_binary(operation, a, b)
    zeroa, zerob = b_isconstant(a,false), b_isconstant(b,false)
    onea, oneb = b_isconstant(a,true), b_isconstant(b,true)
    equal = b_equal(a,b)
    complementary = (a.operation == "~" && b_equal(a.children[1],b)) || (b.operation == "~" && b_equal(b.children[1],a))
    if operation == "&"
        (zeroa || zerob) && return b_leaf("0")
        onea && return b
        oneb && return a
        equal && return a
        complementary && return b_leaf("0")
    elseif operation == "|"
        (onea || oneb) && return b_leaf("1")
        zeroa && return b
        zerob && return a
        equal && return a
        complementary && return b_leaf("1")
    elseif operation == "^"
        zeroa && return b
        zerob && return a
        onea && return b_negate(b)
        oneb && return b_negate(a)
        equal && return b_leaf("0")
        complementary && return b_leaf("1")
    elseif operation == "->"
        (zeroa || oneb) && return b_leaf("1")
        onea && return b
        zerob && return b_negate(a)
        equal && return b_leaf("1")
        complementary && return b
    else
        onea && return b
        oneb && return a
        zeroa && return b_negate(b)
        zerob && return b_negate(a)
        equal && return b_leaf("1")
        complementary && return b_leaf("0")
    end
    b_node(operation,a,b)
end
function b_simplify(f, assignments=Dict{Char,Bool}())
    if isempty(f.children)
        return b_variable(f) && haskey(assignments,only(f.operation)) ? b_constant(assignments[only(f.operation)]) : f
    elseif f.operation == "~"
        return b_negate(b_simplify(f.children[1],assignments))
    end
    b_simplify_binary(f.operation,b_simplify(f.children[1],assignments),b_simplify(f.children[2],assignments))
end
function b_evaluate(f, variables, row)
    operation = f.operation
    operation == "0" && return false
    operation == "1" && return true
    if b_variable(f)
        index = findfirst(==(only(operation)),variables)
        return (row & (1 << (length(variables)-index))) != 0
    end
    a = b_evaluate(f.children[1],variables,row)
    operation == "~" && return !a
    b = b_evaluate(f.children[2],variables,row)
    operation == "&" ? a && b : operation == "|" ? a || b : operation == "^" ? xor(a,b) : operation == "->" ? !a || b : a == b
end
b_truth(f, variables) = [b_evaluate(f,variables,row) for row in 0:(1<<length(variables))-1]
b_pattern(row, n) = join(((row >> i) & 1 for i in n-1:-1:0))
b_pattern_key(pattern) = replace(pattern,'1'=>'0','0'=>'1','-'=>'2')
b_sorted(patterns) = sort!(collect(patterns); by=b_pattern_key)
b_literals(pattern) = count(!=('-'),pattern)
b_flip(pattern) = replace(pattern,'1'=>'0','0'=>'1')
function b_term(pattern, variables; clause=false)
    literals = [string(c == '0' ? "~" : "",variables[i]) for (i,c) in enumerate(pattern) if c != '-']
    isempty(literals) ? (clause ? "0" : "1") : join(literals,clause ? " | " : " & ")
end
function b_normal_text(patterns, variables; clause=false)
    isempty(patterns) && return clause ? "1" : "0"
    texts = [b_term(p,variables;clause=clause) for p in patterns]
    if clause && length(patterns) >= 2
        texts = [b_literals(p) >= 2 ? "(" * text * ")" : text for (p,text) in zip(patterns,texts)]
    end
    join(texts,clause ? " & " : " | ")
end
b_assignment(row,variables) = "{" * join((string(v,"=",(row >> (length(variables)-i)) & 1) for (i,v) in enumerate(variables))," ") * "}"
function b_anf(values, n)
    coefficients = copy(values)
    for bit in 0:n-1, mask in 0:length(values)-1
        mask & (1<<bit) != 0 && (coefficients[mask+1] = xor(coefficients[mask+1],coefficients[(mask ⊻ (1<<bit))+1]))
    end
    coefficients
end
function b_anf_text(values, variables)
    coefficients = b_anf(values,length(variables))
    patterns = [replace(b_pattern(row,length(variables)),'0'=>'-') for row in 0:length(values)-1 if coefficients[row+1]]
    sort!(patterns; by=p -> (b_literals(p),b_pattern_key(p)))
    isempty(patterns) ? "0" : join((b_term(p,variables) for p in patterns)," ^ ")
end
function b_covers(pattern, row, n)
    all(c == '-' || Int(c-'0') == ((row >> (n-i)) & 1) for (i,c) in enumerate(pattern))
end
function b_minimize(on, dc, variables; product=false)
    n = length(variables)
    stage = Set(b_pattern(row,n) for row in union(on,dc))
    primes = Set{String}()
    lines = String[]
    number = 0
    while true
        patterns = collect(stage)
        combined = Set{String}()
        next = Set{String}()
        for i in eachindex(patterns), j in i+1:length(patterns)
            a, b = patterns[i], patterns[j]
            positions = [k for k in 1:n if a[k] != b[k]]
            if length(positions) == 1
                k = only(positions)
                if a[k] != '-' && b[k] != '-'
                    chars = collect(a)
                    chars[k] = '-'
                    push!(next,String(chars))
                    push!(combined,a,b)
                end
            end
        end
        uncombined = setdiff(stage,combined)
        union!(primes,uncombined)
        !product && push!(lines,"stage $number: implicants $(length(stage)) primes $(length(uncombined))")
        isempty(next) && break
        stage = next
        number += 1
    end
    target = b_sorted(p for p in primes if any(row -> b_covers(p,row,n),on))
    essential = Set{Int}()
    coverage = Dict(row => [i for i in eachindex(target) if b_covers(target[i],row,n)] for row in on)
    for indices in values(coverage)
        length(indices) == 1 && push!(essential,only(indices))
    end
    optional = [i for i in eachindex(target) if !(i in essential)]
    best = Int[]
    best_score = nothing
    for mask in 0:(1<<length(optional))-1
        chosen = vcat(collect(essential),[optional[i] for i in eachindex(optional) if mask & (1<<(i-1)) != 0])
        all(any(i -> i in chosen,coverage[row]) for row in on) || continue
        patterns = b_sorted(product ? b_flip(target[i]) : target[i] for i in chosen)
        score = (length(chosen),sum(b_literals(p) for p in patterns;init=0),Tuple(b_pattern_key.(patterns)))
        if best_score === nothing || isless(score,best_score)
            best, best_score = chosen, score
        end
    end
    cover = b_sorted(product ? b_flip(target[i]) : target[i] for i in best)
    if product
        push!(lines,"minimal: " * b_normal_text(cover,variables;clause=true))
        push!(lines,"clauses $(length(cover)) literals $(sum(b_literals(p) for p in cover;init=0))")
    else
        essentials = b_sorted(target[i] for i in essential)
        push!(lines,"primes: " * (isempty(target) ? "none" : join((b_term(p,variables) for p in target),", ")))
        push!(lines,"essential: " * (isempty(essentials) ? "none" : join((b_term(p,variables) for p in essentials),", ")))
        push!(lines,"minimal: " * b_normal_text(cover,variables))
        push!(lines,"terms $(length(cover)) literals $(sum(b_literals(p) for p in cover;init=0))")
    end
    lines
end
function b_merge_clause(a,b)
    result = collect(a)
    for i in eachindex(result)
        b[i] == '-' && continue
        result[i] != '-' && result[i] != b[i] && return nothing
        result[i] = b[i]
    end
    String(result)
end
function b_tidy(patterns)
    unique_patterns = unique(patterns)
    [p for p in unique_patterns if !any(q -> q != p && all(q[i] == '-' || q[i] == p[i] for i in 1:length(p)),unique_patterns)]
end
function b_clauses(formula,variables)
    memo = IdDict{Formula,Vector{String}}()
    function visit(f)
        haskey(memo,f) && return memo[f]
        if f.operation == "1"
            result = String[]
        elseif f.operation == "0"
            result = [repeat("-",length(variables))]
        elseif b_variable(f) || f.operation == "~"
            variable = only(f.operation == "~" ? f.children[1].operation : f.operation)
            result = [join((v == variable ? (f.operation == "~" ? '0' : '1') : '-' for v in variables))]
        else
            left, right = visit(f.children[1]), visit(f.children[2])
            if f.operation == "&"
                result = b_tidy(vcat(left,right))
            else
                result = String[]
                for a in left, b in right
                    merged = b_merge_clause(a,b)
                    merged !== nothing && push!(result,merged)
                end
                result = b_tidy(result)
            end
        end
        memo[f] = result
    end
    visit(b_nnf(formula))
end
function b_dp(formula,variables)
    clauses = b_clauses(formula,variables)
    empty_clause = repeat("-",length(variables))
    lines = ["start: clauses $(length(clauses))"]
    for (i,variable) in enumerate(variables)
        (isempty(clauses) || empty_clause in clauses) && break
        positive = [p for p in clauses if p[i] == '1']
        negative = [p for p in clauses if p[i] == '0']
        resolvents = Set{String}()
        for p in positive, q in negative
            a, b = collect(p), collect(q)
            a[i] = b[i] = '-'
            merged = b_merge_clause(String(a),String(b))
            merged !== nothing && push!(resolvents,merged)
        end
        clauses = b_tidy(vcat([p for p in clauses if p[i] == '-'],collect(resolvents)))
        push!(lines,"eliminate $variable: resolvents $(length(resolvents)) clauses $(length(clauses))")
    end
    push!(lines,"result: " * (empty_clause in clauses ? "unsatisfiable" : "satisfiable"))
    lines
end
function b_bdd(values,variables)
    nodes = Tuple{Int,Int,Int}[]
    unique_nodes = Dict{Tuple{Int,Int,Int},Int}()
    function build(level, first, amount)
        amount == 1 && return Int(values[first])
        half = div(amount,2)
        low = build(level+1,first,half)
        high = build(level+1,first+half,half)
        low == high && return low
        key = (level,low,high)
        if !haskey(unique_nodes,key)
            push!(nodes,key)
            unique_nodes[key] = length(nodes)+1
        end
        unique_nodes[key]
    end
    root = build(1,1,length(values))
    lines = ["nodes: $(length(nodes))"]
    paths = [0,1]
    for (i,(level,low,high)) in enumerate(nodes)
        push!(lines,"$(i+1) = ite($(variables[level]), $high, $low)")
        push!(paths,paths[low+1]+paths[high+1])
    end
    push!(lines,"root: $root","paths: $(paths[root+1])")
    lines
end
function b_properties(values,variables)
    n = length(variables)
    depends = Char[]
    monotone = true
    for (i,variable) in enumerate(variables)
        bit = 1 << (n-i)
        any(values[row+1] != values[(row ⊻ bit)+1] for row in 0:length(values)-1) && push!(depends,variable)
        for row in 0:length(values)-1
            row & bit == 0 && values[row+1] && !values[(row|bit)+1] && (monotone=false)
        end
    end
    coefficients = b_anf(values,n)
    linear = all(!coefficients[row+1] || count_ones(row) <= 1 for row in 0:length(values)-1)
    symmetric = all(length(unique(values[row+1] for row in 0:length(values)-1 if count_ones(row) == k)) <= 1 for k in 0:n)
    yesno(value) = value ? "yes" : "no"
    ["depends: " * (isempty(depends) ? "none" : join(depends," ")),
     "zero-preserving: " * yesno(!first(values)),
     "one-preserving: " * yesno(last(values)),
     "self-dual: " * yesno(all(values[i] != values[end-i+1] for i in eachindex(values))),
     "monotone: " * yesno(monotone),
     "linear: " * yesno(linear),
     "symmetric: " * yesno(symmetric)]
end
const B_SINGLE = Set(split("PRINT TABLE MINTERMS MAXTERMS DNF CNF NNF DUAL ANF SIMPLIFY MINIMIZE MINPOS KMAP SAT TAUT COUNT PROPS BDD CLAUSES DP"))
const B_SPLIT = Set(split("RESTRICT COFACTOR MINDC EQUIV IMPLIES"))
const B_TRUTH = Set(split("TABLE MINTERMS MAXTERMS DNF CNF ANF SAT TAUT COUNT EQUIV IMPLIES PROPS KMAP BDD MINIMIZE MINDC MINPOS"))
b_name(name) = occursin(r"^[a-z][a-z0-9]{0,7}$",name)
b_words(text) = String.(split(text,' ';keepempty=false))
function b_define!(definitions,name,formula)
    prefix = haskey(definitions,name) ? "redefined " : "defined "
    result = prefix * name * " = " * b_text(formula)
    definitions[name] = formula
    [result]
end
function b_sum_formula(rows,variables)
    terms = Formula[]
    for row in rows
        literals = [((row >> (length(variables)-i)) & 1) == 1 ? b_leaf(variable) : b_node("~",b_leaf(variable)) for (i,variable) in enumerate(variables)]
        push!(terms,reduce((a,b)->b_node("&",a,b),literals))
    end
    isempty(terms) ? b_leaf("0") : reduce((a,b)->b_node("|",a,b),terms)
end
function b_command!(definitions,line)
    at = findfirst(' ',line)
    command = at === nothing ? line : line[1:at-1]
    argument = at === nothing ? "" : line[at+1:end]
    command in union(B_SINGLE,B_SPLIT,Set(["DEF","DEFSUM","DEL","LIST"])) || b_fail("unknown command $command")
    command == "LIST" && at !== nothing && b_fail("unexpected argument")
    command != "LIST" && at === nothing && b_fail("missing argument")
    if command == "LIST"
        return vcat(["names: $(length(definitions))"],[name * " = " * b_text(definitions[name]) for name in sort!(collect(keys(definitions)))])
    elseif command == "DEL"
        b_name(argument) || b_fail("invalid name '$argument'")
        haskey(definitions,argument) || b_fail("undefined name '$argument'")
        delete!(definitions,argument)
        return ["deleted $argument"]
    elseif command == "DEF"
        split_at = findfirst(' ',argument)
        split_at === nothing && b_fail("missing argument")
        name = argument[1:split_at-1]
        b_name(name) || b_fail("invalid name '$name'")
        formula = b_parse(argument[split_at+1:end],length(name)+6,definitions)
        return b_define!(definitions,name,formula)
    elseif command == "DEFSUM"
        semicolon = findfirst(';',argument)
        semicolon === nothing && b_fail("missing ';'")
        words = b_words(argument[1:semicolon-1])
        isempty(words) && b_fail("missing argument")
        name = first(words)
        b_name(name) || b_fail("invalid name '$name'")
        variables = words[2:end]
        valid = !isempty(variables) && all(word -> length(word) == 1 && 'A' <= word[1] <= 'Z',variables)
        valid = valid && all(variables[i] < variables[i+1] for i in 1:length(variables)-1)
        valid || b_fail("bad variable list")
        length(variables) >= 9 && b_fail("too many variables: $(length(variables))")
        rows = Int[]
        for word in b_words(argument[semicolon+1:end])
            occursin(r"^(0|[1-9][0-9]*)$",word) || b_fail("bad minterm '$word'")
            value = parse(Int,word)
            (value >= (1<<length(variables)) || (!isempty(rows) && value <= last(rows))) && b_fail("bad minterm '$word'")
            push!(rows,value)
        end
        return b_define!(definitions,name,b_sum_formula(rows,only.(variables)))
    end
    front, back = argument, ""
    second_start = 0
    if command in B_SPLIT
        semicolon = findfirst(';',argument)
        semicolon === nothing && b_fail("missing ';'")
        front, back = argument[1:semicolon-1],argument[semicolon+1:end]
        second_start = length(command)+2+semicolon
    end
    formula = b_parse(front,length(command)+2,definitions)
    second = command in ("MINDC","EQUIV","IMPLIES") ? b_parse(back,second_start,definitions) : nothing
    if command == "RESTRICT"
        words = b_words(back)
        isempty(words) && b_fail("missing assignment")
        assignments = Dict{Char,Bool}()
        for word in words
            occursin(r"^[A-Z]=[01]$",word) || b_fail("bad assignment '$word'")
            variable = word[1]
            haskey(assignments,variable) && b_fail("duplicate variable $variable")
            assignments[variable] = word[3] == '1'
        end
        return ["restricted: " * b_text(b_simplify(formula,assignments))]
    elseif command == "COFACTOR"
        words = b_words(back)
        (length(words) == 1 && length(words[1]) == 1 && 'A' <= words[1][1] <= 'Z') || b_fail("bad variable")
        variable = only(words[1])
        high = b_simplify(formula,Dict(variable=>true))
        low = b_simplify(formula,Dict(variable=>false))
        return ["cofactor $variable=1: " * b_text(high),"cofactor $variable=0: " * b_text(low),"difference: " * b_text(b_simplify_binary("^",high,low))]
    end
    variables = second === nothing ? b_variables(formula) : b_variables(formula,second)
    command in B_TRUTH && length(variables) >= 9 && b_fail("too many variables: $(length(variables))")
    if command == "PRINT"
        return ["formula: " * b_text(formula),"variables: " * (isempty(variables) ? "none" : join(variables," ")),"size $(b_size(formula)) depth $(b_depth(formula))"]
    elseif command == "NNF"
        return ["nnf: " * b_text(b_nnf(formula))]
    elseif command == "DUAL"
        return ["dual: " * b_text(b_dual(formula))]
    elseif command == "SIMPLIFY"
        return ["simplified: " * b_text(b_simplify(formula))]
    elseif command == "CLAUSES"
        return ["clauses: " * b_normal_text(b_sorted(b_clauses(formula,variables)),variables;clause=true)]
    elseif command == "DP"
        return b_dp(formula,variables)
    end
    values = b_truth(formula,variables)
    n = length(variables)
    rows = collect(0:length(values)-1)
    on = [row for row in rows if values[row+1]]
    off = [row for row in rows if !values[row+1]]
    if command == "TABLE"
        lines = [join(vcat(string.(variables),["|","F"])," ")]
        append!(lines,[join(vcat(string.(collect(b_pattern(row,n))),["|",string(Int(values[row+1]))])," ") for row in rows])
        return lines
    elseif command in ("MINTERMS","MAXTERMS")
        selected = command == "MINTERMS" ? on : off
        return [lowercase(command) * ": " * (isempty(selected) ? "none" : join(selected," "))]
    elseif command == "DNF"
        return ["dnf: " * b_normal_text([b_pattern(row,n) for row in on],variables)]
    elseif command == "CNF"
        return ["cnf: " * b_normal_text([b_flip(b_pattern(row,n)) for row in off],variables;clause=true)]
    elseif command == "ANF"
        return ["anf: " * b_anf_text(values,variables)]
    elseif command == "SAT"
        return [isempty(on) ? "unsatisfiable" : "satisfiable: " * b_assignment(first(on),variables)]
    elseif command == "TAUT"
        return [isempty(off) ? "tautology" : "not a tautology: " * b_assignment(first(off),variables)]
    elseif command == "COUNT"
        return ["models: $(length(on)) of $(length(values))"]
    elseif command in ("EQUIV","IMPLIES")
        other = b_truth(second,variables)
        mismatch = findfirst(row -> command == "EQUIV" ? values[row+1] != other[row+1] : values[row+1] && !other[row+1],rows)
        mismatch === nothing && return [command == "EQUIV" ? "equivalent" : "implies"]
        row = rows[mismatch]
        return [command == "EQUIV" ? "not equivalent: " * b_assignment(row,variables) * " f=$(Int(values[row+1])) g=$(Int(other[row+1]))" : "does not imply: " * b_assignment(row,variables)]
    elseif command == "PROPS"
        return b_properties(values,variables)
    elseif command == "BDD"
        return b_bdd(values,variables)
    elseif command in ("MINIMIZE","MINDC","MINPOS")
        dc = second === nothing ? Int[] : [row for row in rows if b_evaluate(second,variables,row)]
        return b_minimize(command == "MINPOS" ? off : setdiff(on,dc),dc,variables;product=command == "MINPOS")
    elseif command == "KMAP"
        2 <= n <= 4 || b_fail("kmap needs 2 to 4 variables")
        p, q = div(n,2),n-div(n,2)
        row_codes = [xor(i,div(i,2)) for i in 0:(1<<p)-1]
        column_codes = [xor(i,div(i,2)) for i in 0:(1<<q)-1]
        label = join(variables[1:p]) * "\\" * join(variables[p+1:end])
        lines = [label * " " * join((b_pattern(c,q) for c in column_codes)," ")]
        for row in row_codes
            text = b_pattern(row,p) * repeat(" ",length(label)-p)
            for column in column_codes
                text *= repeat(" ",q) * string(Int(values[(row<<q)+column+1]))
            end
            push!(lines,text)
        end
        return lines
    end
    String[]
end
function main()
    count = parse(Int,readline())
    definitions = Dict{String,Formula}()
    for _ in 1:count
        line = readline()
        try
            foreach(println,b_command!(definitions,line))
        catch error
            error isa LogicError || rethrow()
            println("error: $(error.reason)")
        end
    end
end
main()
