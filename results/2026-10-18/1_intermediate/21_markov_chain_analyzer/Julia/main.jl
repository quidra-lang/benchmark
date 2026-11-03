const Rat = Rational{BigInt}
const ZERO = big(0) // big(1)
const ONE = big(1) // big(1)
const MAX_STATES = 10
const MAX_GAMBLER_SIZE = 9
const MODULUS = 2147483647
const MULTIPLIER = 48271

struct CommandError <: Exception
    reason::String
end
Base.showerror(io::IO, error::CommandError) = print(io, error.reason)
fail(message::String) = throw(CommandError(message))

delta(i::Int, j::Int) = i == j ? ONE : ZERO
answer(flag::Bool) = flag ? "yes" : "no"
fraction_text(value::Rational) = "$(numerator(value))/$(denominator(value))"
function value_text(value::Rational)
    whole, remainder = fldmod(numerator(value), denominator(value))
    digits = div(remainder * 1000000, denominator(value))
    return "$(fraction_text(value))($whole.$(lpad(string(digits), 6, '0')))"
end
time_text(value) = value === nothing ? "inf" : value_text(value)

function parse_probability(text::AbstractString)
    parts = split(text, '/')
    numerator_ = parse(BigInt, parts[1])
    denominator_ = length(parts) == 2 ? parse(BigInt, parts[2]) : big(1)
    if denominator_ == 0 || numerator_ > denominator_
        fail("BAD PROBABILITY")
    end
    return numerator_ // denominator_
end

function membership(n::Int, states)
    result = fill(false, n)
    for state in states
        result[state] = true
    end
    return result
end

unit_matrix(n::Int) = [delta(i, j) for i in 1:n, j in 1:n]

function eliminate!(matrix::Vector{Vector{Rat}}, n::Int)
    for column in 1:n
        pivot_row = column
        while matrix[pivot_row][column] == ZERO
            pivot_row += 1
        end
        matrix[column], matrix[pivot_row] = matrix[pivot_row], matrix[column]
        pivot = matrix[column][column]
        matrix[column] = [value / pivot for value in matrix[column]]
        for row in 1:n
            row == column && continue
            factor = matrix[row][column]
            if factor != ZERO
                matrix[row] = [value - factor * base
                               for (value, base) in zip(matrix[row], matrix[column])]
            end
        end
    end
    return [row[n+1:end] for row in matrix]
end

mutable struct Chain
    names::Vector{String}
    positions::Dict{String, Int}
    matrix::Matrix{Rat}
end

function Chain(names::Vector{String})
    positions = Dict(name => i for (i, name) in enumerate(names))
    return Chain(names, positions, fill(ZERO, length(names), length(names)))
end

nstates(c::Chain) = length(c.names)
function state_index(c::Chain, text::String)
    index = get(c.positions, text, 0)
    index != 0 || fail("UNKNOWN STATE $text")
    return index
end
function distinct_states(c::Chain, texts::Vector{String})
    states = Int[]
    for text in texts
        index = state_index(c, text)
        index in states && fail("DUPLICATE STATE $text")
        push!(states, index)
    end
    return states
end
labels(c::Chain, indices) = [c.names[i] for i in indices]
row_sum(c::Chain, i::Int) = sum(c.matrix[i, :]; init=ZERO)
block_sum(c::Chain, i::Int, block) = sum((c.matrix[i, j] for j in block); init=ZERO)
edge(c::Chain, i::Int, j::Int) = c.matrix[i, j] > ZERO
absorbing(c::Chain, i::Int) = c.matrix[i, i] == ONE

function advance(c::Chain, distribution::Vector{Rat})
    n = nstates(c)
    return Rat[sum((distribution[i] * c.matrix[i, j] for i in 1:n); init=ZERO)
               for j in 1:n]
end

function reachable(c::Chain, start::Int)
    seen = fill(false, nstates(c))
    seen[start] = true
    stack = [start]
    while !isempty(stack)
        i = pop!(stack)
        for j in 1:nstates(c)
            if edge(c, i, j) && !seen[j]
                seen[j] = true
                push!(stack, j)
            end
        end
    end
    return seen
end

struct CommunicatingClass
    number::Int
    members::Vector{Int}
    closed::Bool
    levels::Vector{Int}
    period::Int
end

function CommunicatingClass(c::Chain, number::Int, members::Vector{Int})
    inside = membership(nstates(c), members)
    closed = !any(edge(c, i, j) && !inside[j]
                  for i in members for j in 1:nstates(c))
    levels = fill(-1, nstates(c))
    levels[first(members)] = 0
    queue = [first(members)]
    while !isempty(queue)
        u = popfirst!(queue)
        for v in members
            if edge(c, u, v) && levels[v] < 0
                levels[v] = levels[u] + 1
                push!(queue, v)
            end
        end
    end
    period = 0
    for u in members, v in members
        if edge(c, u, v)
            period = gcd(period, levels[u] + 1 - levels[v])
        end
    end
    return CommunicatingClass(number, members, closed, levels, period)
end

struct Decomposition
    reach::Vector{Vector{Bool}}
    classes::Vector{CommunicatingClass}
    class_of::Vector{Int}
end

function Decomposition(c::Chain)
    n = nstates(c)
    reach = [reachable(c, i) for i in 1:n]
    classes = CommunicatingClass[]
    class_of = fill(0, n)
    for i in 1:n
        class_of[i] != 0 && continue
        members = [j for j in 1:n if reach[i][j] && reach[j][i]]
        for j in members
            class_of[j] = length(classes) + 1
        end
        push!(classes, CommunicatingClass(c, length(classes) + 1, members))
    end
    return Decomposition(reach, classes, class_of)
end

closed_classes(d::Decomposition) = [item for item in d.classes if item.closed]
containing(d::Decomposition, i::Int) = d.classes[d.class_of[i]]
reaches(d::Decomposition, i::Int, targets::Vector{Bool}) =
    any(d.reach[i][j] && targets[j] for j in eachindex(targets))

struct Absorption
    transient::Vector{Int}
    absorbing::Vector{Int}
    fundamental::Vector{Vector{Rat}}
    steps::Vector{Rat}
    probabilities::Vector{Vector{Rat}}
end

function Absorption(c::Chain)
    transient = [i for i in 1:nstates(c) if !absorbing(c, i)]
    absorbing_states = [i for i in 1:nstates(c) if absorbing(c, i)]
    count = length(transient)
    matrix = Vector{Rat}[]
    for (row, i) in enumerate(transient)
        left = Rat[delta(i, j) - c.matrix[i, j] for j in transient]
        right = Rat[delta(row, col) for col in 1:count]
        push!(matrix, vcat(left, right))
    end
    fundamental = eliminate!(matrix, count)
    steps = Rat[sum(row; init=ZERO) for row in fundamental]
    probabilities = Vector{Rat}[]
    for row in fundamental
        push!(probabilities, Rat[
            sum((row[k] * c.matrix[transient[k], a] for k in 1:count); init=ZERO)
            for a in absorbing_states
        ])
    end
    return Absorption(transient, absorbing_states, fundamental, steps, probabilities)
end

function variance(a::Absorption, i::Int)
    count = length(a.transient)
    total = sum(((2 * a.fundamental[i][j] - delta(i, j)) * a.steps[j]
                 for j in 1:count); init=ZERO)
    return total - a.steps[i]^2
end

function stationary_distribution(c::Chain, members::Vector{Int})
    n = length(members)
    matrix = Vector{Rat}[]
    for r in 1:(n-1)
        row = Rat[c.matrix[members[k], members[r]] - delta(k, r) for k in 1:n]
        push!(matrix, vcat(row, Rat[ZERO]))
    end
    push!(matrix, fill(ONE, n + 1))
    return Rat[row[1] for row in eliminate!(matrix, n)]
end

function irreducible_distribution(c::Chain, d::Decomposition)
    length(d.classes) == 1 || fail("NOT IRREDUCIBLE")
    return stationary_distribution(c, first(d.classes).members)
end

function solve_restricted(c::Chain, states::Vector{Int}, constants::Vector{Rat})
    matrix = Vector{Rat}[]
    for (row, i) in enumerate(states)
        coefficients = Rat[delta(i, j) - c.matrix[i, j] for j in states]
        push!(matrix, vcat(coefficients, Rat[constants[row]]))
    end
    return Rat[row[1] for row in eliminate!(matrix, length(states))]
end

function hitting_probabilities(c::Chain, d::Decomposition, targets::Vector{Bool})
    n = nstates(c)
    probabilities = Rat[targets[i] ? ONE : ZERO for i in 1:n]
    remaining = [i for i in 1:n if !targets[i] && reaches(d, i, targets)]
    if !isempty(remaining)
        constants = Rat[
            sum((c.matrix[i, j] for j in 1:n if targets[j]); init=ZERO)
            for i in remaining
        ]
        for (i, value) in zip(remaining, solve_restricted(c, remaining, constants))
            probabilities[i] = value
        end
    end
    return probabilities
end

function hitting_times(c::Chain, targets::Vector{Bool}, probabilities::Vector{Rat})
    n = nstates(c)
    times = Union{Nothing,Rat}[targets[i] ? ZERO : nothing for i in 1:n]
    certain = [i for i in 1:n if !targets[i] && probabilities[i] == ONE]
    if !isempty(certain)
        constants = fill(ONE, length(certain))
        for (i, value) in zip(certain, solve_restricted(c, certain, constants))
            times[i] = value
        end
    end
    return times
end

function regular_exponent(c::Chain)
    n = nstates(c)
    edges = [edge(c, i, j) for i in 1:n, j in 1:n]
    power = edges
    for exponent in 1:((n-1)^2+1)
        all(power) && return exponent
        power = [any(power[i, k] && edges[k, j] for k in 1:n)
                 for i in 1:n, j in 1:n]
    end
    return nothing
end

mutable struct MarkovAnalyzer
    chains::Dict{String,Chain}
    output::Vector{String}
end
MarkovAnalyzer() = MarkovAnalyzer(Dict{String,Chain}(), String[])
emit!(m::MarkovAnalyzer, args...) = push!(m.output, join(string.(args), " "))

function display!(m::MarkovAnalyzer, names::Vector{String}, matrix::Matrix{Rat},
                  label::String="ROW")
    emit!(m, "STATES", join(names, " "))
    for (i, name) in enumerate(names)
        emit!(m, label, name, join((fraction_text(v) for v in matrix[i, :]), " "))
    end
end

function require_chain(m::MarkovAnalyzer, name::String)
    haskey(m.chains, name) || fail("UNKNOWN CHAIN $name")
    return m.chains[name]
end

function stochastic(m::MarkovAnalyzer, name::String)
    c = require_chain(m, name)
    for i in 1:nstates(c)
        row_sum(c, i) == ONE || fail("NOT STOCHASTIC $(c.names[i])")
    end
    return c
end

function create_chain!(m::MarkovAnalyzer, a::Vector{String})
    name, names = a[1], a[2:end]
    length(names) <= MAX_STATES || fail("TOO MANY STATES")
    for (position, state) in enumerate(names)
        if state in names[1:position-1]
            fail("DUPLICATE STATE $state")
        end
    end
    m.chains[name] = Chain(names)
    emit!(m, "CHAIN", name, "states=$(length(names))")
end

function set_probability!(m::MarkovAnalyzer, a::Vector{String})
    c = require_chain(m, a[1])
    i, j = state_index(c, a[2]), state_index(c, a[3])
    value = parse_probability(a[4])
    c.matrix[i, j] = value
    emit!(m, "P", a[1], a[2], a[3], fraction_text(value),
          "rowsum=$(fraction_text(row_sum(c, i)))")
end

function set_row!(m::MarkovAnalyzer, a::Vector{String})
    c = require_chain(m, a[1])
    i = state_index(c, a[2])
    length(a) - 2 == nstates(c) || fail("BAD LENGTH")
    c.matrix[i, :] = Rat[parse_probability(value) for value in a[3:end]]
    emit!(m, "ROW", a[1], a[2], "rowsum=$(fraction_text(row_sum(c, i)))")
end

function show_chain!(m::MarkovAnalyzer, a::Vector{String})
    c = require_chain(m, a[1])
    emit!(m, "MATRIX", a[1], "states=$(nstates(c))")
    display!(m, c.names, c.matrix)
end

function check_chain!(m::MarkovAnalyzer, a::Vector{String})
    c = require_chain(m, a[1])
    bad = [i for i in 1:nstates(c) if row_sum(c, i) != ONE]
    if isempty(bad)
        emit!(m, "CHECK", a[1], "ok")
    else
        emit!(m, "CHECK", a[1], "bad=$(length(bad))")
        for i in bad
            emit!(m, "BADROW", c.names[i], "sum=$(fraction_text(row_sum(c, i)))")
        end
    end
end

function build_chain!(m::MarkovAnalyzer, a::Vector{String})
    name = a[1]
    order = parse(Int, a[2])
    order in (1, 2) || fail("BAD ORDER")
    tokens = a[3:end]
    length(tokens) > order || fail("TOO FEW TOKENS")
    observations = if order == 1
        tokens
    else
        ["$(tokens[i]).$(tokens[i+1])" for i in 1:length(tokens)-1]
    end
    names = unique(observations)
    length(names) <= MAX_STATES || fail("TOO MANY STATES")
    c = Chain(names)
    counts = zeros(Int, nstates(c), nstates(c))
    for i in 1:length(observations)-1
        counts[c.positions[observations[i]], c.positions[observations[i+1]]] += 1
    end
    emit!(m, "BUILD", name, "order=$order", "states=$(nstates(c))",
          "transitions=$(length(observations)-1)")
    for i in 1:nstates(c)
        total = sum(counts[i, :])
        if total == 0
            c.matrix[i, i] = ONE
            emit!(m, "FROM", names[i], "total=0", "absorbing")
            continue
        end
        parts = String[]
        for j in 1:nstates(c)
            if counts[i, j] > 0
                c.matrix[i, j] = big(counts[i, j]) // big(total)
                push!(parts, "$(names[j]):$(counts[i,j])")
            end
        end
        emit!(m, "FROM", names[i], "total=$total", join(parts, " "))
    end
    m.chains[name] = c
end

function gambler!(m::MarkovAnalyzer, a::Vector{String})
    name = a[1]
    goal, initial = parse(Int, a[2]), parse(Int, a[3])
    (goal > 0 && goal <= MAX_GAMBLER_SIZE) || fail("BAD SIZE")
    initial <= goal || fail("BAD START")
    p = parse_probability(a[4])
    p != ZERO && p != ONE || fail("BAD PROBABILITY")
    c = Chain(["s$i" for i in 0:goal])
    c.matrix[1, 1] = ONE
    c.matrix[goal+1, goal+1] = ONE
    for i in 1:goal-1
        c.matrix[i+1, i+2] = p
        c.matrix[i+1, i] = ONE - p
    end
    m.chains[name] = c
    absorption = Absorption(c)
    ruin = vcat(Rat[ONE], Rat[row[1] for row in absorption.probabilities], Rat[ZERO])
    duration = vcat(Rat[ZERO], absorption.steps, Rat[ZERO])
    emit!(m, "GAMBLER", name, "g=$goal", "p=$(fraction_text(p))",
          "start=s$initial", "ruin=$(value_text(ruin[initial+1]))",
          "duration=$(value_text(duration[initial+1]))")
    for i in 0:goal
        emit!(m, "CAPITAL", "s$i",
              "ruin=$(value_text(ruin[i+1]))",
              "win=$(value_text(ONE - ruin[i+1]))",
              "duration=$(value_text(duration[i+1]))")
    end
end

function classes!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    d = Decomposition(c)
    emit!(m, "CLASSES", a[1], "count=$(length(d.classes))")
    for item in d.classes
        kind = item.closed ? "RECURRENT" : "TRANSIENT"
        emit!(m, "CLASS", item.number, kind, "period=$(item.period)",
              "size=$(length(item.members))", join(labels(c, item.members), " "))
        item.period < 2 && continue
        for remainder in 0:item.period-1
            states = [i for i in item.members if mod(item.levels[i], item.period) == remainder]
            emit!(m, "CYCLIC", remainder, join(labels(c, states), " "))
        end
    end
end

function classify!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    d = Decomposition(c)
    absorbing_states = Bool[absorbing(c, i) for i in 1:nstates(c)]
    count = sum(absorbing_states)
    absorbing_chain = count > 0 && all(reaches(d, i, absorbing_states) for i in 1:nstates(c))
    exponent = regular_exponent(c)
    emit!(m, "CLASSIFY", a[1], "absorbing_states=$count",
          "absorbing=$(answer(absorbing_chain))",
          "ergodic=$(answer(length(d.classes)==1))",
          "regular=$(answer(exponent !== nothing))",
          "exponent=$(exponent === nothing ? "-" : exponent)")
end

function step!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    initial, steps = a[2], parse(Int, a[3])
    distribution = if isdigit(initial[1])
        texts = split(initial, ',')
        length(texts) == nstates(c) || fail("BAD LENGTH")
        values = Rat[parse_probability(text) for text in texts]
        sum(values; init=ZERO) == ONE || fail("BAD DISTRIBUTION")
        values
    else
        start = state_index(c, initial)
        Rat[delta(start, j) for j in 1:nstates(c)]
    end
    for _ in 1:steps
        distribution = advance(c, distribution)
    end
    emit!(m, "STEP", a[1], "k=$steps")
    for (name, value) in zip(c.names, distribution)
        emit!(m, "PROB", name, value_text(value))
    end
end

function power!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    steps = parse(Int, a[2])
    matrix = unit_matrix(nstates(c))
    for _ in 1:steps
        updated = fill(ZERO, nstates(c), nstates(c))
        for i in 1:nstates(c)
            updated[i, :] = advance(c, collect(matrix[i, :]))
        end
        matrix = updated
    end
    emit!(m, "POWER", a[1], "k=$steps")
    display!(m, c.names, matrix)
end

function stationary!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    closed = closed_classes(Decomposition(c))
    emit!(m, "STATIONARY", a[1], "count=$(length(closed))")
    for (number, item) in enumerate(closed)
        emit!(m, "DIST", number, "class=$(item.number)", "size=$(length(item.members))")
        distribution = stationary_distribution(c, item.members)
        for (i, value) in zip(item.members, distribution)
            emit!(m, "PI", c.names[i], value_text(value))
        end
    end
end

function recurrence!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    state = state_index(c, a[2])
    item = containing(Decomposition(c), state)
    item.closed || fail("TRANSIENT STATE $(a[2])")
    distribution = stationary_distribution(c, item.members)
    rho = distribution[findfirst(==(state), item.members)]
    emit!(m, "RECURRENCE", a[1], a[2],
          "pi=$(value_text(rho))", "mean=$(value_text(ONE/rho))",
          "period=$(item.period)")
end

function absorb!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    absorbing_states = Bool[absorbing(c, i) for i in 1:nstates(c)]
    any(absorbing_states) || fail("NO ABSORBING STATE")
    d = Decomposition(c)
    for i in 1:nstates(c)
        if !absorbing_states[i] && !reaches(d, i, absorbing_states)
            fail("NOT ABSORBING $(c.names[i])")
        end
    end
    result = Absorption(c)
    emit!(m, "ABSORB", a[1],
          "transient=$(length(result.transient))",
          "absorbing=$(length(result.absorbing))")
    isempty(result.transient) && return
    names = labels(c, result.transient)
    emit!(m, "TRANSIENT", join(names, " "))
    emit!(m, "ABSORBING", join(labels(c, result.absorbing), " "))
    for (name, row) in zip(names, result.fundamental)
        emit!(m, "N", name, join((fraction_text(v) for v in row), " "))
    end
    for (i, name) in enumerate(names)
        emit!(m, "STEPS", name, "mean=$(value_text(result.steps[i]))",
              "var=$(value_text(variance(result, i)))")
    end
    for (name, row) in zip(names, result.probabilities)
        emit!(m, "B", name, join((fraction_text(v) for v in row), " "))
    end
end

function hitting!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    targets = membership(nstates(c), distinct_states(c, a[2:end]))
    probabilities = hitting_probabilities(c, Decomposition(c), targets)
    times = hitting_times(c, targets, probabilities)
    names = [c.names[i] for i in 1:nstates(c) if targets[i]]
    emit!(m, "HITTING", a[1], "targets=$(join(names, ","))")
    for i in 1:nstates(c)
        emit!(m, "HIT", c.names[i],
              "prob=$(value_text(probabilities[i]))",
              "time=$(time_text(times[i]))")
    end
end

function passage!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    d = Decomposition(c)
    pi = irreducible_distribution(c, d)
    times = fill(ZERO, nstates(c), nstates(c))
    for j in 1:nstates(c)
        targets = membership(nstates(c), [j])
        probabilities = hitting_probabilities(c, d, targets)
        column = hitting_times(c, targets, probabilities)
        for i in 1:nstates(c)
            times[i, j] = i == j ? ONE/pi[j] : column[i]
        end
    end
    kemeny = sum((pi[j] * times[1, j] for j in 2:nstates(c)); init=ZERO)
    emit!(m, "PASSAGE", a[1], "kemeny=$(value_text(kemeny))")
    display!(m, c.names, times, "M")
end

function first_passage!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    x, y = state_index(c, a[2]), state_index(c, a[3])
    steps = parse(Int, a[4])
    steps != 0 || fail("BAD STEPS")
    current = Rat[c.matrix[i, y] for i in 1:nstates(c)]
    firsts = Rat[current[x]]
    for _ in 2:steps
        current = Rat[
            sum((c.matrix[i, j] * current[j] for j in 1:nstates(c) if j != y); init=ZERO)
            for i in 1:nstates(c)
        ]
        push!(firsts, current[x])
    end
    emit!(m, "FIRSTPASSAGE", a[1], a[2], a[3], "k=$steps",
          "total=$(value_text(sum(firsts; init=ZERO)))")
    cumulative = ZERO
    for (t, value) in enumerate(firsts)
        cumulative += value
        emit!(m, "FP", t, value_text(value), "cum=$(value_text(cumulative))")
    end
end

function path_probability!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    path = [state_index(c, text) for text in a[2:end]]
    probability, zero_at = ONE, nothing
    for t in 2:length(path)
        probability *= c.matrix[path[t-1], path[t]]
        if probability == ZERO && zero_at === nothing
            zero_at = t - 1
        end
    end
    parts = String["PATHPROB", a[1], "steps=$(length(path)-1)",
                   "prob=$(value_text(probability))"]
    zero_at !== nothing && push!(parts, "zero_at=$zero_at")
    emit!(m, join(parts, " "))
end

function most_likely!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    start = state_index(c, a[2])
    steps = parse(Int, a[3])
    steps > 0 || fail("BAD STEPS")
    best = fill(ONE, steps + 1, nstates(c))
    for t in steps:-1:1
        for i in 1:nstates(c)
            best[t, i] = maximum(c.matrix[i, j] * best[t+1, j]
                                 for j in 1:nstates(c))
        end
    end
    path = [start]
    for t in 1:steps
        current = last(path)
        j = findfirst(j -> c.matrix[current, j] * best[t+1, j] == best[t, current],
                      1:nstates(c))
        push!(path, j)
    end
    emit!(m, "MOSTLIKELY", a[1], a[2], "k=$steps",
          "prob=$(value_text(best[1, start]))")
    emit!(m, "PATH", join(labels(c, path), " "))
end

function reversible!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    pi = irreducible_distribution(c, Decomposition(c))
    violations = Tuple{Int, Int, Rat, Rat}[]
    for i in 1:nstates(c)
        for j in i+1:nstates(c)
            forward = pi[i] * c.matrix[i, j]
            backward = pi[j] * c.matrix[j, i]
            forward != backward && push!(violations, (i, j, forward, backward))
        end
    end
    if isempty(violations)
        emit!(m, "REVERSIBLE", a[1], "yes")
    else
        emit!(m, "REVERSIBLE", a[1], "no", "violations=$(length(violations))")
        for (i, j, forward, backward) in violations
            emit!(m, "VIOLATION", c.names[i], c.names[j],
                  value_text(forward), value_text(backward))
        end
    end
end

function reverse_chain!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    pi = irreducible_distribution(c, Decomposition(c))
    reversed = Chain(copy(c.names))
    for i in 1:nstates(c), j in 1:nstates(c)
        reversed.matrix[i, j] = pi[j] * c.matrix[j, i] / pi[i]
    end
    m.chains[a[2]] = reversed
    emit!(m, "REVERSE", a[1], a[2],
          "reversible=$(answer(reversed.matrix == c.matrix))")
    display!(m, reversed.names, reversed.matrix)
end

function mixing!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    steps = parse(Int, a[2])
    steps != 0 || fail("BAD STEPS")
    epsilon = parse_probability(a[3])
    pi = irreducible_distribution(c, Decomposition(c))
    matrix = unit_matrix(nstates(c))
    mixing_time = nothing
    lines = Tuple{Int, Rat, String}[]
    for t in 1:steps
        updated = fill(ZERO, nstates(c), nstates(c))
        for i in 1:nstates(c)
            updated[i, :] = advance(c, collect(matrix[i, :]))
        end
        matrix = updated
        distances = Rat[
            sum((abs(matrix[i, j] - pi[j]) for j in 1:nstates(c)); init=ZERO) / 2
            for i in 1:nstates(c)
        ]
        largest = maximum(distances)
        worst = findfirst(==(largest), distances)
        if mixing_time === nothing && largest <= epsilon
            mixing_time = t
        end
        push!(lines, (t, largest, c.names[worst]))
    end
    emit!(m, "MIXING", a[1], "k=$steps", "eps=$(fraction_text(epsilon))",
          "time=$(mixing_time === nothing ? "none" : mixing_time)")
    for (t, largest, worst) in lines
        emit!(m, "TV", t, value_text(largest), "from=$worst")
    end
end

function lump!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    seen = fill(false, nstates(c))
    blocks = Vector{Int}[]
    for group in split(a[3], '|')
        block = Int[]
        for text in split(group, ',')
            index = state_index(c, String(text))
            seen[index] && fail("BAD PARTITION")
            seen[index] = true
            push!(block, index)
        end
        push!(blocks, sort(block))
    end
    all(seen) || fail("BAD PARTITION")
    sort!(blocks; by=first)
    for block in blocks
        representative = first(block)
        for target in blocks
            expected = block_sum(c, representative, target)
            for i in block
                actual = block_sum(c, i, target)
                if actual != expected
                    emit!(m, "LUMP", a[1], "not", "lumpable",
                          "block=$(c.names[representative])",
                          "target=$(c.names[first(target)])",
                          "$(c.names[representative])=$(value_text(expected))",
                          "$(c.names[i])=$(value_text(actual))")
                    return
                end
            end
        end
    end
    lumped = Chain([c.names[first(block)] for block in blocks])
    for (i, block) in enumerate(blocks), (j, target) in enumerate(blocks)
        lumped.matrix[i, j] = block_sum(c, first(block), target)
    end
    m.chains[a[2]] = lumped
    emit!(m, "LUMP", a[1], a[2], "blocks=$(length(blocks))")
    display!(m, lumped.names, lumped.matrix)
end

function reward!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    length(a) - 2 == nstates(c) || fail("BAD LENGTH")
    gamma = parse_probability(a[2])
    gamma != ONE || fail("BAD DISCOUNT")
    rewards = Rat[parse(BigInt, text) // big(1) for text in a[3:end]]
    matrix = Vector{Rat}[]
    for i in 1:nstates(c)
        coefficients = Rat[delta(i, j) - gamma * c.matrix[i, j] for j in 1:nstates(c)]
        push!(matrix, vcat(coefficients, Rat[rewards[i]]))
    end
    values = Rat[row[1] for row in eliminate!(matrix, nstates(c))]
    d = Decomposition(c)
    gains = fill(ZERO, nstates(c))
    for item in closed_classes(d)
        distribution = stationary_distribution(c, item.members)
        gain = sum((rho * rewards[i] for (i, rho) in zip(item.members, distribution));
                   init=ZERO)
        targets = membership(nstates(c), item.members)
        probabilities = hitting_probabilities(c, d, targets)
        for i in 1:nstates(c)
            gains[i] += probabilities[i] * gain
        end
    end
    emit!(m, "REWARD", a[1], "gamma=$(fraction_text(gamma))")
    for i in 1:nstates(c)
        emit!(m, "VALUE", c.names[i],
              "discounted=$(value_text(values[i]))",
              "gain=$(value_text(gains[i]))")
    end
end

function restrict_chain!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    inside = membership(nstates(c), distinct_states(c, a[3:end]))
    for i in 1:nstates(c)
        if inside[i] && any(edge(c, i, j) && !inside[j] for j in 1:nstates(c))
            fail("NOT CLOSED $(c.names[i])")
        end
    end
    members = [i for i in 1:nstates(c) if inside[i]]
    restricted = Chain(labels(c, members))
    for (i, original_i) in enumerate(members), (j, original_j) in enumerate(members)
        restricted.matrix[i, j] = c.matrix[original_i, original_j]
    end
    m.chains[a[2]] = restricted
    emit!(m, "RESTRICT", a[1], a[2], "states=$(length(members))")
    display!(m, restricted.names, restricted.matrix)
end

function simulate!(m::MarkovAnalyzer, a::Vector{String})
    c = stochastic(m, a[1])
    start = state_index(c, a[2])
    steps, seed = parse(Int, a[3]), parse(Int, a[4])
    steps > 0 || fail("BAD STEPS")
    seed > 0 && seed < MODULUS || fail("BAD SEED")
    random_value = seed
    path = [start]
    for _ in 1:steps
        row = collect(c.matrix[last(path), :])
        common = foldl(lcm, (denominator(v) for v in row); init=big(1))
        random_value = mod(MULTIPLIER * random_value, MODULUS)
        threshold = mod(random_value, common)
        cumulative = ZERO
        for (j, value) in enumerate(row)
            cumulative += value
            if cumulative * common > threshold
                push!(path, j)
                break
            end
        end
    end
    emit!(m, "SIMULATE", a[1], a[2], "steps=$steps", "seed=$seed",
          "end=$(c.names[last(path)])")
    emit!(m, "PATH", join(labels(c, path), " "))
    for i in 1:nstates(c)
        emit!(m, "VISIT", c.names[i], count(==(i), path))
    end
end

function execute!(m::MarkovAnalyzer, line::String)
    parts = String.(split(line, ' '))
    command, arguments = parts[1], parts[2:end]
    try
        if command == "CHAIN"
            create_chain!(m, arguments)
        elseif command == "P"
            set_probability!(m, arguments)
        elseif command == "ROW"
            set_row!(m, arguments)
        elseif command == "SHOW"
            show_chain!(m, arguments)
        elseif command == "CHECK"
            check_chain!(m, arguments)
        elseif command == "BUILD"
            build_chain!(m, arguments)
        elseif command == "GAMBLER"
            gambler!(m, arguments)
        elseif command == "CLASSES"
            classes!(m, arguments)
        elseif command == "CLASSIFY"
            classify!(m, arguments)
        elseif command == "STEP"
            step!(m, arguments)
        elseif command == "POWER"
            power!(m, arguments)
        elseif command == "STATIONARY"
            stationary!(m, arguments)
        elseif command == "RECURRENCE"
            recurrence!(m, arguments)
        elseif command == "ABSORB"
            absorb!(m, arguments)
        elseif command == "HITTING"
            hitting!(m, arguments)
        elseif command == "PASSAGE"
            passage!(m, arguments)
        elseif command == "FIRSTPASSAGE"
            first_passage!(m, arguments)
        elseif command == "PATHPROB"
            path_probability!(m, arguments)
        elseif command == "MOSTLIKELY"
            most_likely!(m, arguments)
        elseif command == "REVERSIBLE"
            reversible!(m, arguments)
        elseif command == "REVERSE"
            reverse_chain!(m, arguments)
        elseif command == "MIXING"
            mixing!(m, arguments)
        elseif command == "LUMP"
            lump!(m, arguments)
        elseif command == "REWARD"
            reward!(m, arguments)
        elseif command == "RESTRICT"
            restrict_chain!(m, arguments)
        elseif command == "SIMULATE"
            simulate!(m, arguments)
        end
    catch error
        if error isa CommandError
            emit!(m, "ERROR", error.reason)
        else
            rethrow()
        end
    end
end

function main()
    count = parse(Int, readline(stdin))
    analyzer = MarkovAnalyzer()
    for _ in 1:count
        execute!(analyzer, readline(stdin))
    end
    println(join(analyzer.output, "\n"))
end

main()
