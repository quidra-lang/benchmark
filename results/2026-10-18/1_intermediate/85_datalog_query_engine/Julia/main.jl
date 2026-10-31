const DValue = Union{Int,String}
const D_RESERVED = Set(split("not mod count sum min max retract dump why forget listing strata stats check predicates undo halt"))
const D_COMPARISONS = Set(["=", "!=", "<", "<=", ">", ">="])
const D_OPERATORS = Set(["+", "-", "*", "/", "mod"])

struct DatalogError <: Exception
    reason::String
end
d_fail(reason) = throw(DatalogError(reason))
d_word(c) = 'a' <= c <= 'z' || 'A' <= c <= 'Z' || '0' <= c <= '9' || c == '_'

struct DToken
    kind::String
    text::String
    value::Union{Nothing,DValue}
end

struct DTerm
    kind::Symbol
    value::Union{Nothing,DValue}
end

struct DExpression
    kind::Symbol
    value::Union{Nothing,String,DTerm}
    operands::Vector{DExpression}
end

struct DAtom
    name::String
    terms::Vector{DTerm}
end

struct DLiteral
    kind::Symbol
    atom::Union{Nothing,DAtom}
    operation::String
    expressions::Vector{DExpression}
end

Base.@kwdef mutable struct DStatement
    kind::Symbol
    head::Union{Nothing,DAtom} = nothing
    body::Vector{DLiteral} = DLiteral[]
    aggregate::String = ""
    variable::String = ""
    name::String = ""
    number::Int = 0
end

struct DRule
    number::Int
    head::Union{Nothing,DAtom}
    body::Vector{DLiteral}
end

function d_lex(line)
    tokens = DToken[]
    i = 1
    while i <= length(line)
        c = line[i]
        if c == ' '
            i += 1
        elseif c == '%'
            break
        elseif c == '"'
            finish = findnext('"', line, i + 1)
            finish === nothing && d_fail("unterminated string")
            push!(tokens, DToken("STRING", line[i:finish], line[i+1:finish-1]))
            i = finish + 1
        elseif i < length(line) && line[i:i+1] in (":-", "?-", "!=", "<=", ">=")
            text = line[i:i+1]
            push!(tokens, DToken(text, text, nothing))
            i += 2
        elseif c in "(),.:=<>+-*/"
            push!(tokens, DToken(string(c), string(c), nothing))
            i += 1
        elseif d_word(c)
            start = i
            while i <= length(line) && d_word(line[i])
                i += 1
            end
            text = line[start:i-1]
            if 'a' <= c <= 'z'
                kind = text in D_RESERVED ? text : "NAME"
                push!(tokens, DToken(kind, text, text))
            elseif 'A' <= c <= 'Z'
                push!(tokens, DToken("VARIABLE", text, text))
            elseif text == "_"
                push!(tokens, DToken("ANONYMOUS", text, nothing))
            elseif all(ch -> '0' <= ch <= '9', text)
                value = parse(Int, text)
                value > 1_000_000_000 && d_fail("integer out of range '$text'")
                push!(tokens, DToken("INTEGER", text, value))
            else
                d_fail("bad token '$text'")
            end
        else
            d_fail("bad character '$c'")
        end
    end
    push!(tokens, DToken("EOF", "", nothing))
    tokens
end

mutable struct DParser
    tokens::Vector{DToken}
    position::Int
end
d_peek(p) = p.tokens[p.position]
function d_advance!(p)
    token = d_peek(p)
    p.position += 1
    token
end
function d_syntax(p)
    token = d_peek(p)
    d_fail(token.kind == "EOF" ? "syntax error at end of line" : "syntax error at '$(token.text)'")
end
function d_expect!(p, kind)
    d_peek(p).kind == kind || d_syntax(p)
    d_advance!(p)
end
function d_term!(p)
    token = d_peek(p)
    if token.kind in ("NAME", "STRING", "INTEGER")
        d_advance!(p)
        DTerm(:constant, token.value)
    elseif token.kind == "VARIABLE"
        d_advance!(p)
        DTerm(:variable, token.text)
    elseif token.kind == "ANONYMOUS"
        d_advance!(p)
        DTerm(:anonymous, nothing)
    elseif token.kind == "-"
        d_advance!(p)
        DTerm(:constant, -d_expect!(p, "INTEGER").value)
    else
        d_syntax(p)
    end
end
function d_atom!(p)
    name = d_expect!(p, "NAME").text
    terms = DTerm[]
    if d_peek(p).kind == "("
        d_advance!(p)
        push!(terms, d_term!(p))
        while d_peek(p).kind == ","
            d_advance!(p)
            push!(terms, d_term!(p))
        end
        d_expect!(p, ")")
    end
    DAtom(name, terms)
end
function d_factor!(p)
    if d_peek(p).kind == "("
        d_advance!(p)
        result = DExpression(:group, nothing, [d_expression!(p)])
        d_expect!(p, ")")
        result
    else
        DExpression(:term, d_term!(p), DExpression[])
    end
end
function d_product!(p)
    result = d_factor!(p)
    while d_peek(p).kind in ("*", "/", "mod")
        operation = d_advance!(p).kind
        result = DExpression(:binary, operation, [result, d_factor!(p)])
    end
    result
end
function d_expression!(p)
    result = d_product!(p)
    while d_peek(p).kind in ("+", "-")
        operation = d_advance!(p).kind
        result = DExpression(:binary, operation, [result, d_product!(p)])
    end
    result
end
function d_literal!(p)
    token = d_peek(p)
    if token.kind == "not"
        d_advance!(p)
        DLiteral(:negative, d_atom!(p), "", DExpression[])
    elseif token.kind == "NAME" && !(p.tokens[p.position+1].kind in union(D_COMPARISONS, D_OPERATORS))
        DLiteral(:positive, d_atom!(p), "", DExpression[])
    else
        left = d_expression!(p)
        d_peek(p).kind in D_COMPARISONS || d_syntax(p)
        operation = d_advance!(p).kind
        DLiteral(:comparison, nothing, operation, [left, d_expression!(p)])
    end
end
function d_body!(p)
    body = [d_literal!(p)]
    while d_peek(p).kind == ","
        d_advance!(p)
        push!(body, d_literal!(p))
    end
    body
end
function d_parse(line)
    p = DParser(d_lex(line), 1)
    kind = d_peek(p).kind
    kind == "EOF" && return nothing
    if kind == "NAME"
        head = d_atom!(p)
        if d_peek(p).kind == ":-"
            d_advance!(p)
            statement = DStatement(kind=:rule, head=head, body=d_body!(p))
        else
            statement = DStatement(kind=:fact, head=head)
        end
    elseif kind == ":-"
        d_advance!(p)
        statement = DStatement(kind=:constraint, body=d_body!(p))
    elseif kind == "?-"
        d_advance!(p)
        aggregate = ""
        variable = ""
        if d_peek(p).kind in ("count", "sum", "min", "max")
            aggregate = d_advance!(p).kind
            if aggregate != "count"
                variable = d_expect!(p, "VARIABLE").text
                d_expect!(p, ":")
            end
        end
        statement = DStatement(kind=:query, body=d_body!(p), aggregate=aggregate, variable=variable)
    elseif kind in ("retract", "why")
        d_advance!(p)
        statement = DStatement(kind=Symbol(kind), head=d_atom!(p))
    elseif kind == "dump"
        d_advance!(p)
        statement = DStatement(kind=:dump, name=d_expect!(p, "NAME").text)
    elseif kind == "forget"
        d_advance!(p)
        statement = DStatement(kind=:forget, number=d_expect!(p, "INTEGER").value)
    elseif kind == "listing"
        d_advance!(p)
        name = d_peek(p).kind == "NAME" ? d_advance!(p).text : ""
        statement = DStatement(kind=:listing, name=name)
    elseif kind in ("strata", "stats", "check", "predicates", "undo", "halt")
        d_advance!(p)
        statement = DStatement(kind=Symbol(kind))
    else
        d_syntax(p)
    end
    d_expect!(p, ".")
    d_expect!(p, "EOF")
    statement
end

function d_value_text(value)
    value isa Int && return string(value)
    occursin(r"^[a-z][A-Za-z0-9_]*$", value) && !(value in D_RESERVED) ? value : "\"" * value * "\""
end
function d_term_text(term, environment=nothing)
    term.kind == :anonymous && return "_"
    term.kind == :constant && return d_value_text(term.value)
    environment === nothing ? term.value : d_value_text(environment[term.value])
end
function d_atom_text(atom, environment=nothing)
    isempty(atom.terms) && return atom.name
    atom.name * "(" * join((d_term_text(t, environment) for t in atom.terms), ", ") * ")"
end
d_tuple_text(name, tuple) = d_atom_text(DAtom(name, [DTerm(:constant, v) for v in tuple]))
function d_expression_text(expression, environment=nothing)
    expression.kind == :term && return d_term_text(expression.value, environment)
    expression.kind == :group && return "(" * d_expression_text(expression.operands[1], environment) * ")"
    d_expression_text(expression.operands[1], environment) * " " * expression.value * " " * d_expression_text(expression.operands[2], environment)
end
function d_literal_text(literal, environment=nothing)
    literal.kind == :positive && return d_atom_text(literal.atom, environment)
    literal.kind == :negative && return "not " * d_atom_text(literal.atom, environment)
    d_expression_text(literal.expressions[1], environment) * " " * literal.operation * " " * d_expression_text(literal.expressions[2], environment)
end
d_rule_text(rule) = (rule.head === nothing ? ":- " : d_atom_text(rule.head) * " :- ") * join(d_literal_text.(rule.body), ", ") * "."
function d_expression_terms(expression)
    expression.kind == :term && return [expression.value]
    reduce(vcat, d_expression_terms.(expression.operands); init=DTerm[])
end
d_literal_terms(literal) = literal.kind == :comparison ? reduce(vcat, d_expression_terms.(literal.expressions); init=DTerm[]) : literal.atom.terms
function d_occurrences(head, body)
    terms = head === nothing ? DTerm[] : copy(head.terms)
    for literal in body
        append!(terms, d_literal_terms(literal))
    end
    String[t.value for t in terms if t.kind == :variable]
end
d_variables(head, body) = unique(d_occurrences(head, body))
d_value_less(a, b) = a isa Int ? (b isa String || a < b) : (b isa String && isless(a, b))
function d_tuple_less(a, b)
    for (x, y) in zip(a, b)
        x == y || return d_value_less(x, y)
    end
    false
end
d_sorted(tuples) = sort!(collect(tuples); lt=d_tuple_less)

struct DModel
    tuples::Dict{String,Set{Tuple}}
    derivations::Dict{String,Dict{Tuple,Tuple{Int,Int}}}
    levels::Dict{String,Int}
    rounds::Dict{Int,Int}
    added::Dict{Int,Int}
end
const DSnapshot = Tuple{Dict{String,Int},Dict{String,Set{Tuple}},Vector{DRule},Int}
mutable struct DDatabase
    arities::Dict{String,Int}
    facts::Dict{String,Set{Tuple}}
    rules::Vector{DRule}
    next_rule::Int
    history::Vector{DSnapshot}
    cache::Union{Nothing,DModel}
end
DDatabase() = DDatabase(Dict{String,Int}(), Dict{String,Set{Tuple}}(), DRule[], 1, DSnapshot[], nothing)

function d_atoms(head, body)
    result = head === nothing ? DAtom[] : [head]
    append!(result, (literal.atom for literal in body if literal.kind != :comparison))
    result
end
function d_predicate_check(database, atoms; clause=false)
    prospective = copy(database.arities)
    for atom in atoms
        if haskey(prospective, atom.name)
            expected = prospective[atom.name]
            expected == length(atom.terms) || d_fail("arity mismatch for $(atom.name): expected $expected, got $(length(atom.terms))")
        elseif clause
            prospective[atom.name] = length(atom.terms)
        else
            d_fail("unknown predicate $(atom.name)")
        end
    end
    prospective
end
function d_safety(statement)
    head, body = statement.head, statement.body
    head !== nothing && any(t -> t.kind == :anonymous, head.terms) && d_fail("anonymous variable in head")
    for literal in body
        literal.kind == :comparison && any(t -> t.kind == :anonymous, d_literal_terms(literal)) && d_fail("anonymous variable in comparison")
    end
    bound = Set{String}()
    for literal in body
        if literal.kind == :positive
            union!(bound, (t.value for t in literal.atom.terms if t.kind == :variable))
        end
    end
    required = head === nothing ? DTerm[] : copy(head.terms)
    !isempty(statement.variable) && push!(required, DTerm(:variable, statement.variable))
    for literal in body
        literal.kind != :positive && append!(required, d_literal_terms(literal))
    end
    for term in required
        term.kind == :variable && !(term.value in bound) && d_fail("unsafe variable $(term.value)")
    end
end
function d_levels(arities, rules)
    levels = Dict(name => 0 for name in keys(arities))
    for iteration in 1:length(arities)
        changed = false
        for rule in rules
            rule.head === nothing && continue
            for literal in rule.body
                literal.kind == :comparison && continue
                level = levels[literal.atom.name] + Int(literal.kind == :negative)
                if level > levels[rule.head.name]
                    levels[rule.head.name] = level
                    changed = true
                end
            end
        end
        !changed && return levels
    end
    isempty(arities) ? levels : nothing
end
function d_snapshot!(database, line)
    facts = Dict(name => copy(tuples) for (name, tuples) in database.facts)
    push!(database.history, (copy(database.arities), facts, copy(database.rules), line))
    database.cache = nothing
end
function d_match(atom, tuple, environment)
    result = copy(environment)
    for (term, value) in zip(atom.terms, tuple)
        if term.kind == :constant
            term.value == value || return nothing
        elseif term.kind == :variable
            haskey(result, term.value) && result[term.value] != value && return nothing
            result[term.value] = value
        end
    end
    result
end
function d_evaluate(expression, environment)
    if expression.kind == :term
        term = expression.value
        return term.kind == :constant ? term.value : environment[term.value]
    elseif expression.kind == :group
        return d_evaluate(expression.operands[1], environment)
    end
    a = d_evaluate(expression.operands[1], environment)
    b = d_evaluate(expression.operands[2], environment)
    a isa Int && b isa Int || return nothing
    operation = expression.value
    operation == "+" && return a + b
    operation == "-" && return a - b
    operation == "*" && return a * b
    b == 0 && return nothing
    quotient = fld(a, b)
    operation == "/" ? quotient : a - b * quotient
end
function d_comparison(literal, environment)
    a = d_evaluate(literal.expressions[1], environment)
    b = d_evaluate(literal.expressions[2], environment)
    (a === nothing || b === nothing) && return false
    literal.operation == "=" && return a == b
    literal.operation == "!=" && return a != b
    a isa Int && b isa Int || return false
    literal.operation == "<" ? a < b : literal.operation == "<=" ? a <= b : literal.operation == ">" ? a > b : a >= b
end
function d_solutions(body, tuples; derivations=nothing, before=nothing)
    variables = d_variables(nothing, body)
    positive = [literal.atom for literal in body if literal.kind == :positive]
    filters = [(literal, unique(String[term.value for term in d_literal_terms(literal) if term.kind == :variable]))
        for literal in body if literal.kind != :positive]
    environments = Dict{String,DValue}[]
    final_seen = Set{Tuple}()
    used = falses(length(positive))
    function visit(environment, depth)
        for (literal, required) in filters
            all(name -> haskey(environment, name), required) || continue
            if literal.kind == :comparison
                d_comparison(literal, environment) || return
            elseif any(tuple -> d_match(literal.atom, tuple, environment) !== nothing, tuples[literal.atom.name])
                return
            end
        end
        if depth == length(positive)
            key = Tuple(environment[name] for name in variables)
            if !(key in final_seen)
                push!(final_seen, key)
                push!(environments, environment)
            end
            return
        end
        choice, best_bound, best_size = 0, -1, typemax(Int)
        for (i, atom) in enumerate(positive)
            used[i] && continue
            bound = count(term -> term.kind == :constant || (term.kind == :variable && haskey(environment, term.value)), atom.terms)
            size = length(tuples[atom.name])
            if bound > best_bound || (bound == best_bound && size < best_size)
                choice, best_bound, best_size = i, bound, size
            end
        end
        atom = positive[choice]
        used[choice] = true
        seen = Set{Tuple}()
        for tuple in tuples[atom.name]
            before !== nothing && derivations[atom.name][tuple][1] >= before && continue
            matched = d_match(atom, tuple, environment)
            matched === nothing && continue
            key = Tuple(matched[name] for name in variables if haskey(matched, name))
            if !(key in seen)
                push!(seen, key)
                visit(matched, depth+1)
            end
        end
        used[choice] = false
    end
    visit(Dict{String,DValue}(), 0)
    sort!(environments; lt=(a,b) -> d_tuple_less(Tuple(a[v] for v in variables), Tuple(b[v] for v in variables)))
end
d_head_tuple(atom, environment) = Tuple(t.kind == :constant ? t.value : environment[t.value] for t in atom.terms)
function d_model(database)
    database.cache !== nothing && return database.cache
    levels = d_levels(database.arities, database.rules)
    tuples = Dict(name => copy(get(database.facts, name, Set{Tuple}())) for name in keys(database.arities))
    derivations = Dict(name => Dict{Tuple,Tuple{Int,Int}}(tuple => (0,0) for tuple in rows) for (name,rows) in tuples)
    rounds, added = Dict{Int,Int}(), Dict{Int,Int}()
    serial = 0
    for stratum in 0:maximum(values(levels); init=-1)
        rounds[stratum] = added[stratum] = 0
        while true
            new = Dict(name => Dict{Tuple,Int}() for name in keys(database.arities))
            for rule in database.rules
                (rule.head === nothing || levels[rule.head.name] != stratum) && continue
                for environment in d_solutions(rule.body, tuples)
                    tuple = d_head_tuple(rule.head, environment)
                    if !(tuple in tuples[rule.head.name])
                        target = new[rule.head.name]
                        target[tuple] = min(get(target, tuple, rule.number), rule.number)
                    end
                end
            end
            amount = sum(length(rows) for rows in values(new); init=0)
            amount == 0 && break
            serial += 1
            rounds[stratum] += 1
            added[stratum] += amount
            for (name, rows) in new, (tuple, number) in rows
                push!(tuples[name], tuple)
                derivations[name][tuple] = (serial, number)
            end
        end
    end
    database.cache = DModel(tuples, derivations, levels, rounds, added)
end
function d_answer_lines(variables, environments; indent="")
    [indent * join((name * " = " * d_value_text(environment[name]) for name in variables), ", ") for environment in environments]
end
d_plural(n, singular, plural=singular * "s") = string(n) * " " * (n == 1 ? singular : plural)
function d_query(database, statement)
    d_predicate_check(database, d_atoms(nothing, statement.body))
    d_safety(statement)
    model = d_model(database)
    variables = d_variables(nothing, statement.body)
    answers = d_solutions(statement.body, model.tuples)
    aggregate = statement.aggregate
    if aggregate == "count"
        return [string(length(answers))]
    elseif aggregate == "sum"
        values = [environment[statement.variable] for environment in answers]
        all(v -> v isa Int, values) || d_fail("non-integer value in sum")
        return [string(sum(values; init=0))]
    elseif aggregate in ("min", "max")
        isempty(answers) && return ["no answers"]
        values = sort!([environment[statement.variable] for environment in answers]; lt=d_value_less)
        return [d_value_text(aggregate == "min" ? first(values) : last(values))]
    elseif isempty(variables)
        return [isempty(answers) ? "false." : "true."]
    end
    vcat(d_answer_lines(variables, answers), [d_plural(length(answers), "answer")])
end
function d_proof!(lines, database, model, name, tuple, depth)
    indent = repeat(" ", 2depth)
    serial = model.derivations[name][tuple][1]
    if serial == 0
        push!(lines, indent * d_tuple_text(name, tuple) * " [fact]")
        return
    end
    for rule in database.rules
        (rule.head === nothing || rule.head.name != name) && continue
        solutions = d_solutions(rule.body, model.tuples; derivations=model.derivations, before=serial)
        filter!(environment -> d_head_tuple(rule.head, environment) == tuple, solutions)
        isempty(solutions) && continue
        variables = d_variables(rule.head, rule.body)
        sort!(solutions; lt=(a,b) -> d_tuple_less(Tuple(a[v] for v in variables), Tuple(b[v] for v in variables)))
        environment = first(solutions)
        push!(lines, indent * d_tuple_text(name, tuple) * " [rule $(rule.number)]")
        for literal in rule.body
            if literal.kind == :positive
                atom = literal.atom
                matches = [row for row in model.tuples[atom.name] if model.derivations[atom.name][row][1] < serial && d_match(atom, row, environment) !== nothing]
                chosen = first(d_sorted(matches))
                d_proof!(lines, database, model, atom.name, chosen, depth + 1)
            else
                push!(lines, indent * "  " * d_literal_text(literal, environment))
            end
        end
        return
    end
end
function d_recursive(database, name)
    pending = String[]
    for rule in database.rules
        rule.head !== nothing && rule.head.name == name || continue
        append!(pending, (literal.atom.name for literal in rule.body if literal.kind != :comparison))
    end
    seen = Set{String}()
    while !isempty(pending)
        current = pop!(pending)
        current == name && return true
        current in seen && continue
        push!(seen, current)
        for rule in database.rules
            rule.head !== nothing && rule.head.name == current || continue
            append!(pending, (literal.atom.name for literal in rule.body if literal.kind != :comparison))
        end
    end
    false
end
function d_register!(database, statement, line)
    prospective = d_predicate_check(database, d_atoms(statement.head, statement.body); clause=true)
    d_safety(statement)
    if statement.kind == :fact
        tuple = d_head_tuple(statement.head, Dict{String,DValue}())
        tuple in get(database.facts, statement.head.name, Set{Tuple}()) && return String[]
        d_snapshot!(database, line)
        database.arities = prospective
        push!(get!(database.facts, statement.head.name, Set{Tuple}()), tuple)
        return String[]
    end
    rule = DRule(database.next_rule, statement.head, statement.body)
    notation = d_rule_text(rule)
    for previous in database.rules
        d_rule_text(previous) == notation && d_fail("duplicate of rule $(previous.number)")
    end
    statement.kind == :rule && d_levels(prospective, vcat(database.rules, [rule])) === nothing && d_fail("negative cycle through $(statement.head.name)")
    d_snapshot!(database, line)
    database.arities = prospective
    push!(database.rules, rule)
    database.next_rule += 1
    occurrences = d_occurrences(statement.head, statement.body)
    ["WARNING line $line: singleton variable $name" for name in unique(occurrences) if count(==(name), occurrences) == 1]
end
function d_process!(database, statement, line)
    kind = statement.kind
    kind in (:fact, :rule, :constraint) && return d_register!(database, statement, line)
    kind == :query && return d_query(database, statement)
    if kind == :undo
        isempty(database.history) && d_fail("nothing to undo")
        arities, facts, rules, original = pop!(database.history)
        database.arities, database.facts, database.rules = arities, facts, rules
        database.cache = nothing
        return ["undid line $original"]
    elseif kind == :forget
        at = findfirst(rule -> rule.number == statement.number, database.rules)
        at === nothing && d_fail("no rule $(statement.number)")
        d_snapshot!(database, line)
        deleteat!(database.rules, at)
        return String[]
    elseif kind in (:retract, :why)
        atom = statement.head
        d_predicate_check(database, [atom])
        if kind == :retract
            rows = get(database.facts, atom.name, Set{Tuple}())
            targets = [tuple for tuple in rows if d_match(atom, tuple, Dict{String,DValue}()) !== nothing]
            isempty(targets) && d_fail("no matching facts")
            d_snapshot!(database, line)
            for tuple in targets
                delete!(rows, tuple)
            end
            return [d_plural(length(targets), "fact") * " retracted"]
        end
        any(t -> t.kind != :constant, atom.terms) && d_fail("why needs a ground atom")
        tuple = d_head_tuple(atom, Dict{String,DValue}())
        model = d_model(database)
        tuple in model.tuples[atom.name] || return ["false."]
        lines = String[]
        d_proof!(lines, database, model, atom.name, tuple, 0)
        return lines
    elseif kind in (:dump, :listing)
        !isempty(statement.name) && !haskey(database.arities, statement.name) && d_fail("unknown predicate $(statement.name)")
        if kind == :listing
            rules = [rule for rule in database.rules if isempty(statement.name) || (rule.head !== nothing && rule.head.name == statement.name)]
            return isempty(rules) ? ["no rules"] : ["$(rule.number): $(d_rule_text(rule))" for rule in rules]
        end
        rows = d_sorted(d_model(database).tuples[statement.name])
        return vcat([d_tuple_text(statement.name, tuple) * "." for tuple in rows], [d_plural(length(rows), "tuple")])
    end
    model = d_model(database)
    names = sort!(collect(keys(database.arities)))
    if kind == :strata
        isempty(names) && return ["no predicates"]
        return ["stratum $k: " * join((name * (d_recursive(database, name) ? "*" : "") for name in names if model.levels[name] == k), ", ") for k in 0:maximum(values(model.levels))]
    elseif kind == :stats
        fact_count = sum(length(rows) for rows in values(database.facts); init=0)
        rule_count = count(rule -> rule.head !== nothing, database.rules)
        tuple_count = sum(length(rows) for rows in values(model.tuples); init=0)
        lines = ["facts $fact_count, rules $rule_count, constraints $(length(database.rules)-rule_count), tuples $tuple_count"]
        for k in 0:maximum(values(model.levels); init=-1)
            push!(lines, "stratum $k: rounds $(model.rounds[k]), new $(model.added[k])")
        end
        for rule in database.rules
            rule.head === nothing && continue
            amount = count(info -> info[2] == rule.number, values(model.derivations[rule.head.name]))
            push!(lines, "rule $(rule.number): new $amount")
        end
        return lines
    elseif kind == :predicates
        isempty(names) && return ["no predicates"]
        return ["$name/$(database.arities[name]): facts $(length(get(database.facts,name,Set{Tuple}()))), rules $(count(rule -> rule.head !== nothing && rule.head.name == name, database.rules)), tuples $(length(model.tuples[name]))" for name in names]
    elseif kind == :check
        constraints = [rule for rule in database.rules if rule.head === nothing]
        isempty(constraints) && return ["no constraints"]
        lines = String[]
        for rule in constraints
            answers = d_solutions(rule.body, model.tuples)
            if isempty(answers)
                push!(lines, "constraint $(rule.number): ok")
            else
                push!(lines, "constraint $(rule.number): " * d_plural(length(answers), "violation"))
                variables = d_variables(nothing, rule.body)
                !isempty(variables) && append!(lines, d_answer_lines(variables, answers; indent="  "))
            end
        end
        return lines
    end
    String[]
end
function main()
    database = DDatabase()
    for (line_number, line) in enumerate(eachline())
        try
            statement = d_parse(line)
            statement === nothing && continue
            statement.kind == :halt && break
            for output in d_process!(database, statement, line_number)
                println(output)
            end
        catch error
            error isa DatalogError || rethrow()
            println("ERROR line $line_number: $(error.reason)")
        end
    end
end
main()
