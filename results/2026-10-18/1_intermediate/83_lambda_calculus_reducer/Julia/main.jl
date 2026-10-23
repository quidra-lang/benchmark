struct LambdaError <: Exception
    reason::String
end
lambda_error(reason) = throw(LambdaError(reason))

struct LambdaTerm
    kind::Symbol
    name::String
    number::Int
    children::Vector{LambdaTerm}
    free::Set{String}
    size::Int
    depth::Int
end

function make_term(kind, name="", number=0, children=LambdaTerm[])
    free = if kind == :variable
        Set([name])
    elseif kind == :abstraction
        setdiff(children[1].free, [name])
    elseif kind == :application
        union(children[1].free, children[2].free)
    else
        Set{String}()
    end
    size = 1 + sum((child.size for child in children); init=0)
    depth = 1 + maximum((child.depth for child in children); init=0)
    LambdaTerm(kind, name, number, children, free, size, depth)
end
varterm(name) = make_term(:variable, name)
absterm(name, body) = make_term(:abstraction, name, 0, [body])
appterm(left, right) = make_term(:application, "", 0, [left, right])

function print_term(term, at_end=true; db=false)
    kind = term.kind
    kind in (:variable, :macro, :constant) && return term.name
    kind == :number && return "#$(term.number)"
    kind == :index && return string(term.number)
    if kind == :abstraction
        names = String[]
        body = term
        while body.kind == :abstraction
            push!(names, body.name)
            body = body.children[1]
        end
        text = db ? repeat("\\", length(names)) * print_term(body; db=true) :
            "\\" * join(names, " ") * ". " * print_term(body)
        return at_end ? text : "(" * text * ")"
    end
    left, right = term.children
    a = left.kind == :abstraction ? "(" * print_term(left; db=db) * ")" :
        print_term(left, false; db=db)
    b = right.kind == :application ? "(" * print_term(right; db=db) * ")" :
        print_term(right, at_end; db=db)
    a * " " * b
end

struct LambdaToken
    kind::Symbol
    text::String
    column::Int
end
mutable struct LambdaParser
    tokens::Vector{LambdaToken}
    position::Int
end

function lambda_parser(argument, offset, end_column)
    tokens = LambdaToken[]
    i = 1
    while i <= length(argument)
        c = argument[i]
        if c == ' '
            i += 1
            continue
        end
        start = i
        if c in "\\.()=;"
            kind = :symbol
            i += 1
        elseif 'a' <= c <= 'z'
            kind = :variable
            i += 1
            while i <= length(argument) && ('a' <= argument[i] <= 'z' || isdigit(argument[i]))
                i += 1
            end
        elseif 'A' <= c <= 'Z'
            kind = :macro
            i += 1
            while i <= length(argument) &&
                    ('A' <= argument[i] <= 'Z' || isdigit(argument[i]) || argument[i] == '_')
                i += 1
            end
        elseif c == '#' && i < length(argument) && isdigit(argument[i + 1])
            kind = :number
            i += 2
            while i <= length(argument) && isdigit(argument[i])
                i += 1
            end
        else
            lambda_error("column $(offset + i - 1): unexpected character '$c'")
        end
        push!(tokens, LambdaToken(kind, argument[start:i - 1], offset + start - 1))
    end
    push!(tokens, LambdaToken(:eof, "", end_column))
    LambdaParser(tokens, 1)
end
peek_token(p) = p.tokens[p.position]
function read_token!(p::LambdaParser)
    token = peek_token(p)
    p.position += 1
    token
end
function expect_token!(p, expected)
    token = peek_token(p)
    accepted = expected == "variable" ? token.kind == :variable :
        expected == "macro name" ? token.kind == :macro : token.text == expected
    if !accepted
        notation = expected in ("variable", "macro name") ? expected : "'$expected'"
        lambda_error("column $(token.column): expected $notation")
    end
    read_token!(p).text
end
function read_term!(p)
    elements = LambdaTerm[]
    while peek_token(p).kind in (:variable, :macro, :number) || peek_token(p).text == "("
        token = read_token!(p)
        if token.text == "("
            push!(elements, read_term!(p))
            expect_token!(p, ")")
        elseif token.kind == :number
            push!(elements, make_term(:number, "", parse(Int, token.text[2:end])))
        else
            push!(elements, make_term(token.kind, token.text))
        end
    end
    if peek_token(p).text == "\\"
        read_token!(p)
        names = [expect_token!(p, "variable")]
        while peek_token(p).kind == :variable
            push!(names, read_token!(p).text)
        end
        expect_token!(p, ".")
        body = read_term!(p)
        for name in Iterators.reverse(names)
            body = absterm(name, body)
        end
        push!(elements, body)
    end
    isempty(elements) && lambda_error("column $(peek_token(p).column): expected term")
    foldl(appterm, elements)
end
function finish_parse(p)
    token = peek_token(p)
    token.kind == :eof || lambda_error("column $(token.column): unexpected '$(token.text)'")
end

function macro_references(term)
    result = String[]
    function visit(node)
        node.kind == :macro && push!(result, node.name)
        for child in node.children
            visit(child)
        end
    end
    visit(term)
    result
end
name_at(index) = string(Char(97 + index % 26)) * (index >= 26 ? string(index ÷ 26) : "")

function canonical_term(term)
    counter = 0
    function visit(node, bindings)
        if node.kind == :variable
            return varterm(get(bindings, node.name, node.name))
        elseif node.kind == :abstraction
            while name_at(counter) in term.free
                counter += 1
            end
            name = name_at(counter)
            counter += 1
            inner = copy(bindings)
            inner[node.name] = name
            return absterm(name, visit(node.children[1], inner))
        elseif node.kind == :application
            left = visit(node.children[1], bindings)
            right = visit(node.children[2], bindings)
            return appterm(left, right)
        end
        node
    end
    visit(term, Dict{String,String}())
end
function to_debruijn(term, bindings=String[])
    if term.kind == :variable
        index = findfirst(==(term.name), bindings)
        return index === nothing ? term : make_term(:index, "", index - 1)
    elseif term.kind == :abstraction
        return absterm("", to_debruijn(term.children[1], [term.name; bindings]))
    end
    appterm(to_debruijn(term.children[1], bindings), to_debruijn(term.children[2], bindings))
end
function from_debruijn(term)
    counter = 0
    function visit(node, bindings)
        if node.kind == :index
            return varterm(bindings[node.number + 1])
        elseif node.kind == :variable
            return node
        elseif node.kind == :abstraction
            while name_at(counter) in term.free
                counter += 1
            end
            name = name_at(counter)
            counter += 1
            return absterm(name, visit(node.children[1], [name; bindings]))
        end
        left = visit(node.children[1], bindings)
        right = visit(node.children[2], bindings)
        appterm(left, right)
    end
    visit(term, String[])
end

function substitute(term, name, replacement)
    if term.kind == :variable
        return term.name == name ? replacement : term
    elseif term.kind == :application
        return appterm(substitute(term.children[1], name, replacement),
            substitute(term.children[2], name, replacement))
    end
    bound = term.name
    body = term.children[1]
    (bound == name || !(name in body.free)) && return term
    if bound in replacement.free
        stem = replace(bound, r"[0-9]+$" => "")
        suffix = 1
        while stem * string(suffix) in replacement.free || stem * string(suffix) in body.free
            suffix += 1
        end
        fresh = stem * string(suffix)
        body = substitute(body, bound, varterm(fresh))
        bound = fresh
    end
    absterm(bound, substitute(body, name, replacement))
end
function eta_target(term)
    body = term.children[1]
    if body.kind == :application
        left, right = body.children
        if right.kind == :variable && right.name == term.name && !(term.name in left.free)
            return left
        end
    end
    nothing
end
function lambda_step(term, strategy, eta)
    if term.kind == :application
        left, right = term.children
        if strategy in ("NORMAL", "CBN") && left.kind == :abstraction
            return substitute(left.children[1], left.name, right), "beta"
        end
        step = lambda_step(left, strategy, eta)
        step !== nothing && return (appterm(step[1], right), step[2])
        if strategy != "CBN"
            step = lambda_step(right, strategy, eta)
            step !== nothing && return (appterm(left, step[1]), step[2])
        end
        if strategy in ("APPLICATIVE", "CBV") && left.kind == :abstraction &&
                (strategy != "CBV" || right.kind in (:variable, :abstraction))
            return substitute(left.children[1], left.name, right), "beta"
        end
    elseif term.kind == :abstraction && strategy in ("NORMAL", "APPLICATIVE")
        target = eta ? eta_target(term) : nothing
        target !== nothing && strategy == "NORMAL" && return (target, "eta")
        step = lambda_step(term.children[1], strategy, eta)
        step !== nothing && return (absterm(term.name, step[1]), step[2])
        target !== nothing && return (target, "eta")
    end
    nothing
end
function ski_abstract(name, term)
    !(name in term.free) && return appterm(make_term(:constant, "K"), term)
    term.kind == :variable && term.name == name && return make_term(:constant, "I")
    left, right = term.children
    if right.kind == :variable && right.name == name && !(name in left.free)
        return left
    end
    appterm(appterm(make_term(:constant, "S"), ski_abstract(name, left)), ski_abstract(name, right))
end
function to_ski(term)
    term.kind == :variable && return term
    term.kind == :abstraction && return ski_abstract(term.name, to_ski(term.children[1]))
    appterm(to_ski(term.children[1]), to_ski(term.children[2]))
end
function ski_step(term)
    head = term
    args = LambdaTerm[]
    while head.kind == :application
        pushfirst!(args, head.children[2])
        head = head.children[1]
    end
    arity = head.kind == :constant ? (head.name == "I" ? 1 : head.name == "K" ? 2 : 3) : 0
    if arity > 0 && length(args) >= arity
        result = head.name == "S" ? appterm(appterm(args[1], args[3]), appterm(args[2], args[3])) : args[1]
        for arg in args[arity + 1:end]
            result = appterm(result, arg)
        end
        return result, head.name
    end
    for i in eachindex(args)
        step = ski_step(args[i])
        if step !== nothing
            args[i] = step[1]
            return foldl(appterm, args; init=head), step[2]
        end
    end
    nothing
end

mutable struct SimpleType
    id::Int
    left::Union{Nothing,SimpleType}
    right::Union{Nothing,SimpleType}
    link::Union{Nothing,SimpleType}
end
struct NotTypable <: Exception end
function prune_type(type)
    path = SimpleType[]
    while type.link !== nothing
        push!(path, type)
        type = type.link
    end
    for node in path
        node.link = type
    end
    type
end
function occurs_in(id, type)
    type = prune_type(type)
    type.id >= 0 ? type.id == id : occurs_in(id, type.left) || occurs_in(id, type.right)
end
function unify_types(left, right)
    left, right = prune_type(left), prune_type(right)
    left === right && return
    if left.id >= 0
        occurs_in(left.id, right) && throw(NotTypable())
        left.link = right
    elseif right.id >= 0
        unify_types(right, left)
    else
        unify_types(left.left, right.left)
        unify_types(left.right, right.right)
    end
end
function principal_type(term)
    next_id = 0
    free = Dict{String,SimpleType}()
    function fresh()
        type = SimpleType(next_id, nothing, nothing, nothing)
        next_id += 1
        type
    end
    function infer(node, environment)
        if node.kind == :variable
            haskey(environment, node.name) && return environment[node.name]
            if !haskey(free, node.name)
                free[node.name] = fresh()
            end
            return free[node.name]
        elseif node.kind == :abstraction
            parameter = fresh()
            inner = copy(environment)
            inner[node.name] = parameter
            return SimpleType(-1, parameter, infer(node.children[1], inner), nothing)
        end
        function_type = infer(node.children[1], environment)
        argument_type = infer(node.children[2], environment)
        result = fresh()
        unify_types(function_type, SimpleType(-1, argument_type, result, nothing))
        result
    end
    try
        type = infer(term, Dict{String,SimpleType}())
        names = Dict{Int,String}()
        function visit(node)
            node = prune_type(node)
            if node.id >= 0
                if !haskey(names, node.id)
                    names[node.id] = name_at(length(names))
                end
                return names[node.id]
            end
            left = visit(node.left)
            prune_type(node.left).id < 0 && (left = "(" * left * ")")
            left * " -> " * visit(node.right)
        end
        visit(type)
    catch error
        error isa NotTypable || rethrow()
        "not typable"
    end
end

function church_value(term)
    if term.kind == :abstraction && term.children[1].kind == :abstraction
        f = term.name
        x = term.children[1].name
        body = term.children[1].children[1]
        count = 0
        while body.kind == :application && body.children[1].kind == :variable &&
                body.children[1].name == f
            count += 1
            body = body.children[2]
        end
        body.kind == :variable && body.name == x && return string(count)
        original = term.children[1].children[1]
        original.kind == :variable && original.name == f && return "true"
    end
    if term.kind == :abstraction
        body = term.children[1]
        if body.kind == :application && body.children[1].kind == :application
            head, p = body.children[1].children
            q = body.children[2]
            if head.kind == :variable && head.name == term.name &&
                    !(term.name in p.free) && !(term.name in q.free)
                return "(" * church_value(p) * ", " * church_value(q) * ")"
            end
        end
    end
    print_term(canonical_term(term))
end

struct LambdaClosure
    code::LambdaTerm
    environment::Vector{LambdaClosure}
end
function materialize_closure(code, environment, level=0)
    while code.kind == :index && code.number >= level
        closure = environment[code.number - level + 1]
        code, environment = closure.code, closure.environment
        level = 0
    end
    code.kind == :abstraction && return absterm("", materialize_closure(code.children[1], environment, level + 1))
    if code.kind == :application
        return appterm(materialize_closure(code.children[1], environment, level),
            materialize_closure(code.children[2], environment, level))
    end
    code
end

const RESERVED_MACROS = Set(["S", "K", "I", "NORMAL", "APPLICATIVE", "CBN", "CBV"])
const STRATEGIES = ("NORMAL", "APPLICATIVE", "CBN", "CBV")
const COMMANDS = Set(["let", "unlet", "macros", "steps", "eta", "limit", "expand", "subst",
    "reduce", "equal", "alpha", "debruijn", "fv", "size", "depth", "type", "church", "ski", "skireduce", "kam"])
mutable struct LambdaWorkbench
    macros::Dict{String,LambdaTerm}
    steps::Bool
    eta::Bool
    limit::Int
end
function LambdaWorkbench()
    macros = Dict(
        "S" => absterm("x", absterm("y", absterm("z",
            appterm(appterm(varterm("x"), varterm("z")), appterm(varterm("y"), varterm("z")))))),
        "K" => absterm("x", absterm("y", varterm("x"))),
        "I" => absterm("x", varterm("x")))
    LambdaWorkbench(macros, false, false, 10000)
end
function macro_depends(w, name, target, visited=Set{String}())
    name in visited && return false
    push!(visited, name)
    (!haskey(w.macros, name) || name in ("S", "K", "I")) && return false
    any(ref -> ref == target || macro_depends(w, ref, target, visited), macro_references(w.macros[name]))
end
function expand_term(w, term)
    if term.kind == :macro
        haskey(w.macros, term.name) || lambda_error("unbound macro $(term.name)")
        return expand_term(w, w.macros[term.name])
    elseif term.kind == :number
        body = varterm("x")
        for _ in 1:term.number
            body = appterm(varterm("f"), body)
        end
        return absterm("f", absterm("x", body))
    elseif term.kind == :abstraction
        return absterm(term.name, expand_term(w, term.children[1]))
    elseif term.kind == :application
        left = expand_term(w, term.children[1])
        right = expand_term(w, term.children[2])
        return appterm(left, right)
    end
    term
end
function reduce_term(w, term; strategy="NORMAL", eta=w.eta, display=false, combinators=false)
    count = 0
    while true
        step = combinators ? ski_step(term) : lambda_step(term, strategy, eta)
        step === nothing && return (term, count)
        count == w.limit && return nothing
        term = step[1]
        count += 1
        display && w.steps && println("step $count ($(step[2])): ", print_term(term))
    end
end
function run_krivine(w, term)
    code = to_debruijn(term)
    environment = LambdaClosure[]
    stack = LambdaClosure[]
    count = 0
    while true
        kind = code.kind == :application ? "push" :
            code.kind == :abstraction && !isempty(stack) ? "grab" :
            code.kind == :index ? "access" : ""
        isempty(kind) && break
        if count == w.limit
            println("no result within $(w.limit) transitions")
            return
        end
        if kind == "push"
            push!(stack, LambdaClosure(code.children[2], environment))
            code = code.children[1]
        elseif kind == "grab"
            environment = [pop!(stack); environment]
            code = code.children[1]
        else
            closure = environment[code.number + 1]
            code, environment = closure.code, closure.environment
        end
        count += 1
        if w.steps
            println("step $count ($kind): ", print_term(code; db=true),
                " [env $(length(environment)), stack $(length(stack))]")
        end
    end
    result = materialize_closure(code, environment)
    for closure in Iterators.reverse(stack)
        result = appterm(result, materialize_closure(closure.code, closure.environment))
    end
    println("result: ", print_term(from_debruijn(result)), " (transitions: $count)")
end

function simple_command!(w, command, argument)
    words = split(argument)
    if command in ("steps", "eta")
        length(words) == 1 && words[1] in ("on", "off") || lambda_error("bad argument")
        if command == "steps"
            w.steps = words[1] == "on"
        else
            w.eta = words[1] == "on"
        end
    elseif command == "limit"
        length(words) == 1 && occursin(r"^[0-9]{1,5}$", words[1]) &&
            1 <= parse(Int, words[1]) <= 10000 || lambda_error("bad argument")
        w.limit = parse(Int, words[1])
    elseif command == "macros"
        isempty(words) || lambda_error("bad argument")
        names = sort([name for name in keys(w.macros) if !(name in ("S", "K", "I"))])
        isempty(names) && println("(none)")
        for name in names
            println(name, " = ", print_term(w.macros[name]))
        end
    else
        length(words) == 1 && occursin(r"^[A-Z][A-Z0-9_]*$", words[1]) || lambda_error("bad argument")
        name = words[1]
        name in RESERVED_MACROS && lambda_error("reserved name $name")
        haskey(w.macros, name) || lambda_error("unbound macro $name")
        for user in sort(collect(keys(w.macros)))
            if !(user in ("S", "K", "I")) && name in macro_references(w.macros[user])
                lambda_error("$name is used by $user")
            end
        end
        delete!(w.macros, name)
        println("removed $name")
    end
end
function lambda_command!(w, line)
    separator = findfirst(==(' '), line)
    command = separator === nothing ? line : line[1:separator - 1]
    argument = separator === nothing ? "" : line[separator + 1:end]
    command in COMMANDS || lambda_error("unknown command $command")
    if command in ("steps", "eta", "limit", "macros", "unlet")
        simple_command!(w, command, argument)
        return
    end
    parser = lambda_parser(argument, length(command) + 2, length(line) + 1)
    strategy = "NORMAL"
    name = ""
    terms = LambdaTerm[]
    if command in ("let", "subst")
        name = expect_token!(parser, command == "let" ? "macro name" : "variable")
        expect_token!(parser, "=")
        push!(terms, read_term!(parser))
        if command == "subst"
            expect_token!(parser, ";")
            push!(terms, read_term!(parser))
        end
    elseif command in ("equal", "alpha")
        push!(terms, read_term!(parser))
        expect_token!(parser, ";")
        push!(terms, read_term!(parser))
    else
        if command == "reduce" && peek_token(parser).kind == :macro && peek_token(parser).text in STRATEGIES
            strategy = read_token!(parser).text
        end
        push!(terms, read_term!(parser))
    end
    finish_parse(parser)
    if command == "let"
        name in RESERVED_MACROS && lambda_error("reserved name $name")
        for ref in macro_references(terms[1])
            (ref == name || macro_depends(w, ref, name)) && lambda_error("recursive definition of $name")
            haskey(w.macros, ref) || lambda_error("unbound macro $ref")
        end
        isempty(terms[1].free) || lambda_error("free variable $(minimum(terms[1].free)) in definition of $name")
        println(haskey(w.macros, name) ? "redefined $name" : "defined $name")
        w.macros[name] = terms[1]
        return
    end
    for i in eachindex(terms)
        terms[i] = expand_term(w, terms[i])
    end
    term = terms[1]
    if command == "expand"
        println(print_term(term))
    elseif command == "subst"
        println(print_term(substitute(terms[2], name, term)))
    elseif command == "alpha"
        println(print_term(to_debruijn(term); db=true) == print_term(to_debruijn(terms[2]); db=true) ? "yes" : "no")
    elseif command == "debruijn"
        println(print_term(to_debruijn(term); db=true))
    elseif command == "fv"
        println(isempty(term.free) ? "(none)" : join(sort(collect(term.free)), " "))
    elseif command == "size"
        println(term.size)
    elseif command == "depth"
        println(term.depth)
    elseif command == "type"
        println(principal_type(term))
    elseif command == "ski"
        println(print_term(to_ski(term)))
    elseif command == "kam"
        run_krivine(w, term)
    elseif command == "equal"
        left = reduce_term(w, term)
        right = reduce_term(w, terms[2])
        println(left === nothing || right === nothing ? "unknown" :
            print_term(canonical_term(left[1])) == print_term(canonical_term(right[1])) ? "yes" : "no")
    else
        result = if command == "church"
            reduce_term(w, term; eta=false)
        elseif command == "skireduce"
            reduce_term(w, to_ski(term); eta=false, display=true, combinators=true)
        else
            reduce_term(w, term; strategy=strategy, display=true)
        end
        if result === nothing
            println("no normal form within $(w.limit) steps")
        elseif command == "church"
            println(church_value(canonical_term(result[1])))
        else
            text = print_term(command == "skireduce" ? result[1] : canonical_term(result[1]))
            println("result: $text (steps: $(result[2]))")
        end
    end
end
function main()
    workbench = LambdaWorkbench()
    for line in eachline()
        line == "quit" && break
        (isempty(line) || startswith(line, "--")) && continue
        try
            lambda_command!(workbench, line)
        catch error
            error isa LambdaError || rethrow()
            println("error: ", error.reason)
        end
    end
end
main()
