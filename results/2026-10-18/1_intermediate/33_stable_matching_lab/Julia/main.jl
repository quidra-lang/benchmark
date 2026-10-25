using Printf

@enum MarketKind TWO_SIDED ROOMMATE HOUSING
@enum Side ANY_AGENT PROPOSER RECEIVER
@enum Source GS GSR BOSTON EGALITARIAN MINREGRET

struct CommandError <: Exception
    message::String
end
fail(message::AbstractString) = throw(CommandError(String(message)))

struct Saved
    source::Source
    matching::Vector{Int}
end

mutable struct Market
    name::String
    kind::MarketKind
    names::Vector{String}
    proposers::Int
    houses::Vector{String}
    preferences::Vector{Vector{Int}}
    capacities::Vector{Int}
    current::Union{Nothing,Saved}
end
Market(name, kind, names, proposers = 0, houses = String[]) =
    Market(String(name), kind, names, proposers, houses, [Int[] for _ in names], ones(Int, length(names)), nothing)

struct Run
    matching::Vector{Int}
    count::Int
    history::Vector{String}
end
struct Candidate
    matching::Vector{Int}
    origin::Int
    via::Int
    cost::Int
    regret::Int
end
struct Lattice
    matchings::Vector{Candidate}
    rotations::Vector{String}
end

rank_in(preference::Vector{Int}, partner::Int) = something(findfirst(==(partner), preference), length(preference) + 1)
list_text(values) = isempty(values) ? "-" : join(values, " ")
receivers(market::Market) = (market.proposers + 1):length(market.names)
partner_name(market::Market, partner::Int) = partner == 0 ? "*" : market.names[partner]
pair_text(market::Market, matching::Vector{Int}) =
    join((market.names[p] * "-" * partner_name(market, matching[p]) for p in 1:market.proposers), " ")
rotation_text(market::Market, matching::Vector{Int}, rotation::Vector{Int}) =
    join((market.names[p] * "-" * market.names[matching[p]] for p in rotation), " ")
allocation_text(market::Market, allocation::Vector{Int}) =
    join((market.names[a] * "-" * (allocation[a] == 0 ? "*" : market.houses[allocation[a]]) for a in eachindex(market.names)), " ")

function require_kind(market::Market, expected::MarketKind)
    market.kind == expected || fail("WRONG TYPE $(market.name)")
end
function agent_index(market::Market, name::AbstractString, side::Side = ANY_AGENT)
    index = findfirst(==(name), market.names)
    isnothing(index) && fail("UNKNOWN AGENT $name")
    side == PROPOSER && index > market.proposers && fail("NOT PROPOSER $name")
    side == RECEIVER && index <= market.proposers && fail("NOT RECEIVER $name")
    index
end

function deferred(market::Market; reverse::Bool = false, verbose::Bool = false)
    n = length(market.names)
    next_position = ones(Int, n)
    counts = zeros(Int, n)
    holding = [Int[] for _ in 1:n]
    queued = falses(n)
    queue = Int[]
    able(agent) = counts[agent] < market.capacities[agent] && next_position[agent] <= length(market.preferences[agent])
    function enqueue!(agent)
        if able(agent) && !queued[agent]
            push!(queue, agent)
            queued[agent] = true
        end
    end
    for agent in (reverse ? receivers(market) : (1:market.proposers))
        enqueue!(agent)
    end
    history = String[]
    head = 1
    while head <= length(queue)
        proposer = queue[head]
        head += 1
        queued[proposer] = false
        receiver = market.preferences[proposer][next_position[proposer]]
        next_position[proposer] += 1
        action = "REJECT"
        preference = market.preferences[receiver]
        held = holding[receiver]
        if proposer in preference
            if length(held) < market.capacities[receiver]
                push!(held, proposer)
                counts[proposer] += 1
                action = "HOLD"
            else
                worst = argmax([rank_in(preference, partner) for partner in held])
                rejected = held[worst]
                if rank_in(preference, proposer) < rank_in(preference, rejected)
                    held[worst] = proposer
                    counts[rejected] -= 1
                    counts[proposer] += 1
                    action = "HOLD REJECT $(market.names[rejected])"
                    enqueue!(rejected)
                end
            end
        end
        verbose && push!(history, "PROPOSE $(market.names[proposer]) $(market.names[receiver]) $action")
        enqueue!(proposer)
    end
    matching = zeros(Int, market.proposers)
    for receiver in (reverse ? (1:market.proposers) : receivers(market))
        for proposer in holding[receiver]
            if reverse
                matching[receiver] = proposer
            else
                matching[proposer] = receiver
            end
        end
    end
    Run(matching, head - 1, history)
end

function boston(market::Market)
    matching = zeros(Int, market.proposers)
    remaining = copy(market.capacities)
    rounds = maximum(length, market.preferences[1:market.proposers])
    applications = 0
    for round in 1:rounds
        applied = zeros(Int, market.proposers)
        for proposer in 1:market.proposers
            if matching[proposer] == 0 && length(market.preferences[proposer]) >= round
                applied[proposer] = market.preferences[proposer][round]
                applications += 1
            end
        end
        for receiver in receivers(market), proposer in market.preferences[receiver]
            if remaining[receiver] > 0 && applied[proposer] == receiver
                matching[proposer] = receiver
                remaining[receiver] -= 1
            end
        end
    end
    Run(matching, applications, String[])
end

function exposed_rotations(market::Market, matching::Vector{Int})
    owner = zeros(Int, length(market.names))
    successor = zeros(Int, market.proposers)
    for proposer in findall(>(0), matching)
        owner[matching[proposer]] = proposer
    end
    for proposer in findall(>(0), matching)
        preference = market.preferences[proposer]
        for receiver in preference[(rank_in(preference, matching[proposer]) + 1):end]
            ranking = market.preferences[receiver]
            if proposer in ranking && (owner[receiver] == 0 || rank_in(ranking, proposer) < rank_in(ranking, owner[receiver]))
                successor[proposer] = owner[receiver]
                break
            end
        end
    end
    covered = falses(market.proposers)
    rotations = Vector{Int}[]
    for start in 1:market.proposers
        covered[start] && continue
        path = Int[]
        point = start
        while point > 0 && !(point in path)
            push!(path, point)
            point = successor[point]
        end
        if point == start
            push!(rotations, path)
            covered[path] .= true
        end
    end
    rotations
end

function candidate(market::Market, matching::Vector{Int}, origin::Int = 0, via::Int = 0)
    ranks = Int[]
    for proposer in findall(>(0), matching)
        receiver = matching[proposer]
        push!(ranks, rank_in(market.preferences[proposer], receiver), rank_in(market.preferences[receiver], proposer))
    end
    Candidate(matching, origin, via, sum(ranks), maximum(ranks; init = 0))
end

function enumerate_matchings(market::Market)
    all(==(1), market.capacities[receivers(market)]) || fail("NOT ONE TO ONE")
    matchings = [candidate(market, deferred(market).matching)]
    rotations = String[]
    index = 1
    while index <= length(matchings)
        matching = matchings[index].matching
        for rotation in exposed_rotations(market, matching)
            notation = rotation_text(market, matching, rotation)
            identifier = findfirst(==(notation), rotations)
            if isnothing(identifier)
                push!(rotations, notation)
                identifier = length(rotations)
            end
            following = copy(matching)
            for i in eachindex(rotation)
                following[rotation[i]] = matching[rotation[mod1(i + 1, length(rotation))]]
            end
            any(old -> old.matching == following, matchings) && continue
            length(matchings) == 50 && fail("TOO MANY MATCHINGS")
            push!(matchings, candidate(market, following, index, identifier))
        end
        index += 1
    end
    Lattice(matchings, rotations)
end

function check_pairs(market::Market, words)
    market.kind == HOUSING && fail("WRONG TYPE $(market.name)")
    matching = zeros(Int, length(market.names))
    counts = zeros(Int, length(market.names))
    two = market.kind == TWO_SIDED
    for word in words[3:end]
        left, right = split(word, '-')
        first = agent_index(market, left, two ? PROPOSER : ANY_AGENT)
        second = agent_index(market, right, two ? RECEIVER : ANY_AGENT)
        matching[first] > 0 && fail("DUPLICATE AGENT $left")
        if two
            counts[second] += 1
            counts[second] > market.capacities[second] && fail("OVER CAPACITY $right")
        else
            (first == second || matching[second] > 0) && fail("DUPLICATE AGENT $right")
            matching[second] = first
        end
        matching[first] = second
    end
    unacceptable = String[]
    blocking = String[]
    if two
        for proposer in 1:market.proposers
            receiver = matching[proposer]
            if receiver > 0 && (!(receiver in market.preferences[proposer]) || !(proposer in market.preferences[receiver]))
                push!(unacceptable, "UNACCEPTABLE $(market.names[proposer]) $(market.names[receiver])")
            end
            for other in receivers(market)
                (receiver == other || !(other in market.preferences[proposer]) || !(proposer in market.preferences[other])) && continue
                rank_in(market.preferences[proposer], other) >= rank_in(market.preferences[proposer], receiver) && continue
                partners = findall(==(other), matching[1:market.proposers])
                worst = maximum((rank_in(market.preferences[other], p) for p in partners); init = 0)
                if length(partners) < market.capacities[other] || rank_in(market.preferences[other], proposer) < worst
                    push!(blocking, "BLOCKING $(market.names[proposer]) $(market.names[other])")
                end
            end
        end
    else
        for first in eachindex(market.names), second in (first + 1):length(market.names)
            mutual = second in market.preferences[first] && first in market.preferences[second]
            if matching[first] == second
                !mutual && push!(unacceptable, "UNACCEPTABLE $(market.names[first]) $(market.names[second])")
            elseif mutual && rank_in(market.preferences[first], second) < rank_in(market.preferences[first], matching[first]) &&
                   rank_in(market.preferences[second], first) < rank_in(market.preferences[second], matching[second])
                push!(blocking, "BLOCKING $(market.names[first]) $(market.names[second])")
            end
        end
    end
    isempty(unacceptable) && isempty(blocking) && return ["CHECK $(market.name) STABLE"]
    vcat(["CHECK $(market.name) UNSTABLE unacceptable=$(length(unacceptable)) blocking=$(length(blocking))"], unacceptable, blocking)
end

function remove_pair!(lists::Vector{Vector{Int}}, first::Int, second::Int)
    filter!(!=(second), lists[first])
    filter!(!=(first), lists[second])
end
table_lines(market::Market, lists::Vector{Vector{Int}}) =
    ["TABLE $(market.names[a]) $(list_text(market.names[lists[a]]))" for a in eachindex(market.names)]

function roommates(market::Market, verbose::Bool)
    require_kind(market, ROOMMATE)
    incomplete = findfirst(list -> length(list) < length(market.names) - 1, market.preferences)
    isnothing(incomplete) || fail("INCOMPLETE $(market.names[incomplete])")
    lists = copy.(market.preferences)
    held = zeros(Int, length(market.names))
    queue = collect(eachindex(market.names))
    proposals = 0
    failure = nothing
    while proposals < length(queue)
        proposer = queue[proposals + 1]
        proposals += 1
        receiver = first(lists[proposer])
        held[receiver] > 0 && push!(queue, held[receiver])
        held[receiver] = proposer
        position = something(findfirst(==(proposer), lists[receiver]))
        removed = lists[receiver][(position + 1):end]
        for other in removed
            remove_pair!(lists, receiver, other)
        end
        failure = findfirst(isempty, lists)
        isnothing(failure) || break
    end
    history = isnothing(failure) && verbose ? table_lines(market, lists) : String[]
    rotations = 0
    while isnothing(failure)
        point = findfirst(list -> length(list) >= 2, lists)
        isnothing(point) && break
        path = Int[]
        while !(point in path)
            push!(path, point)
            second = lists[point][2]
            point = last(lists[second])
        end
        rotation = path[something(findfirst(==(point), path)):end]
        front = [first(lists[a]) for a in rotation]
        notation = join((market.names[rotation[i]] * "-" * market.names[front[i]] for i in eachindex(rotation)), " ")
        rotations += 1
        push!(history, "ROTATION $rotations $notation")
        removals = Tuple{Int,Int}[]
        for i in eachindex(rotation)
            receiver = front[mod1(i + 1, length(front))]
            position = something(findfirst(==(rotation[i]), lists[receiver]))
            for other in lists[receiver][(position + 1):end]
                push!(removals, (receiver, other))
            end
        end
        for (left, right) in removals
            remove_pair!(lists, left, right)
        end
        verbose && append!(history, table_lines(market, lists))
        failure = findfirst(isempty, lists)
    end
    rows = vcat(["ROOMMATES $(market.name) proposals=$proposals"], history)
    if !isnothing(failure)
        push!(rows, "NO STABLE MATCHING $(market.names[failure])")
    else
        pairs = [market.names[a] * "-" * market.names[first(lists[a])] for a in eachindex(market.names) if a < first(lists[a])]
        push!(rows, "MATCHING " * join(pairs, " "))
    end
    rows
end

function effective_list(market::Market, agent::Int)
    preference = market.preferences[agent]
    position = findfirst(==(agent), preference)
    isnothing(position) ? vcat(preference, agent) : preference[1:position]
end

function ttc(market::Market)
    remaining = trues(length(market.names))
    allocation = zeros(Int, length(market.names))
    effective = [effective_list(market, agent) for agent in eachindex(market.names)]
    cycles = String[]
    while any(remaining)
        pointing = zeros(Int, length(market.names))
        for agent in findall(remaining)
            pointing[agent] = first(house for house in effective[agent] if remaining[house])
        end
        point = something(findfirst(remaining))
        path = Int[]
        while !(point in path)
            push!(path, point)
            point = pointing[point]
        end
        cycle = path[something(findfirst(==(point), path)):end]
        allocation[cycle] = pointing[cycle]
        remaining[cycle] .= false
        notation = join((market.names[a] * ":" * market.houses[pointing[a]] for a in cycle), " ")
        push!(cycles, "CYCLE $(length(cycles) + 1) $notation")
    end
    vcat(["TTC $(market.name) cycles=$(length(cycles))"], cycles, ["ALLOCATION " * allocation_text(market, allocation)])
end

function serial(market::Market, words)
    order = Int[]
    for word in words[3:end]
        agent = agent_index(market, word)
        agent in order && fail("DUPLICATE AGENT $word")
        push!(order, agent)
    end
    length(order) == length(market.names) || fail("BAD ORDER")
    remaining = trues(length(market.names))
    allocation = zeros(Int, length(market.names))
    for agent in order
        for house in market.preferences[agent]
            if remaining[house]
                allocation[agent] = house
                remaining[house] = false
                break
            end
        end
    end
    worse = [market.names[a] for a in eachindex(market.names) if !(allocation[a] in effective_list(market, a))]
    ["SERIAL $(market.name) assigned=$(count(>(0), allocation))", "ALLOCATION " * allocation_text(market, allocation), "WORSE " * list_text(worse)]
end

function hospital_report(market::Market)
    resident = deferred(market).matching
    hospital = deferred(market; reverse = true).matching
    unmatched = market.names[findall(==(0), resident)]
    rows = ["HR $(market.name) residents=$(market.proposers) hospitals=$(length(market.names) - market.proposers)",
            "RESIDENT-OPTIMAL " * pair_text(market, resident), "HOSPITAL-OPTIMAL " * pair_text(market, hospital),
            "UNMATCHED " * list_text(unmatched)]
    rural = (resident .> 0) == (hospital .> 0)
    for receiver in receivers(market)
        first = findall(==(receiver), resident)
        second = findall(==(receiver), hospital)
        same = first == second
        capacity = market.capacities[receiver]
        label = same ? "YES" : "NO"
        push!(rows, "HOSPITAL $(market.names[receiver]) cap=$capacity resident=$(length(first)) hospital=$(length(second)) same=$label")
        rural &= length(first) == length(second) && (length(first) == capacity || same)
    end
    push!(rows, rural ? "RURAL HOLDS" : "RURAL FAILS")
end

function manipulate(market::Market, proposer::Int)
    truth = market.preferences[proposer]
    baseline_b = boston(market).matching[proposer]
    baseline_g = deferred(market).matching[proposer]
    swaps = max(0, length(truth) - 1)
    rows = ["MANIPULATE $(market.name) $(market.names[proposer]) boston=$(partner_name(market, baseline_b)) gs=$(partner_name(market, baseline_g)) swaps=$swaps"]
    for index in 1:swaps
        preferences = copy(market.preferences)
        preferences[proposer] = copy(truth)
        preferences[proposer][index], preferences[proposer][index + 1] = truth[index + 1], truth[index]
        trial = Market(market.name, market.kind, market.names, market.proposers, market.houses, preferences, market.capacities, market.current)
        results = (boston(trial).matching[proposer], deferred(trial).matching[proposer])
        baselines = (baseline_b, baseline_g)
        for (kind, label) in enumerate(("BOSTON", "GS"))
            if rank_in(truth, results[kind]) < rank_in(truth, baselines[kind])
                push!(rows, "IMPROVE $label $index $(market.names[truth[index]]) $(market.names[truth[index + 1]]) result=$(partner_name(market, results[kind]))")
            end
        end
    end
    length(rows) == 1 && push!(rows, "NO IMPROVEMENT")
    rows
end

function statistics(market::Market)
    saved = market.current
    isnothing(saved) && fail("NO MATCHING")
    matched = findall(>(0), saved.matching)
    pairs = length(matched)
    proposer_ranks = [rank_in(market.preferences[p], saved.matching[p]) for p in matched]
    receiver_ranks = [rank_in(market.preferences[saved.matching[p]], p) for p in matched]
    ranks = (proposer_ranks, receiver_ranks)
    unmatched = (market.proposers - pairs, length(market.names) - market.proposers - length(unique(saved.matching[matched])))
    rows = ["STATS $(market.name) source=$(saved.source) pairs=$pairs"]
    for (side, label) in enumerate(("PROPOSERS", "RECEIVERS"))
        total = sum(ranks[side])
        average = truncated = "-"
        if pairs > 0
            divisor = gcd(total, pairs)
            average = "$(div(total, divisor))/$(div(pairs, divisor))"
            cents = div(100 * total, pairs)
            truncated = @sprintf("%d.%02d", div(cents, 100), mod(cents, 100))
        end
        push!(rows, "$label sum=$total average=$average truncated=$truncated first=$(count(==(1), ranks[side])) unmatched=$(unmatched[side])")
    end
    rows
end

function show_market(market::Market)
    rows = if market.kind == TWO_SIDED
        ["SHOW $(market.name) MARKET proposers=$(market.proposers) receivers=$(length(market.names) - market.proposers)"]
    else
        kind = market.kind == ROOMMATE ? "ROOMS" : "HOUSES"
        ["SHOW $(market.name) $kind agents=$(length(market.names))"]
    end
    for agent in eachindex(market.names)
        prefix = if market.kind == TWO_SIDED
            agent <= market.proposers ? "PROPOSER $(market.names[agent])" : "RECEIVER $(market.names[agent]) cap=$(market.capacities[agent])"
        else
            "AGENT $(market.names[agent])" * (market.kind == HOUSING ? " house=$(market.houses[agent])" : "")
        end
        names = market.kind == HOUSING ? market.houses : market.names
        push!(rows, prefix * " " * list_text(names[market.preferences[agent]]))
    end
    if market.kind == TWO_SIDED
        source = isnothing(market.current) ? "-" : string(market.current.source)
        push!(rows, "CURRENT $source")
    end
    rows
end

function new_market(words)
    command, name = words[1:2]
    kind = command == "ROOMS" ? ROOMMATE : command == "HOUSES" ? HOUSING : TWO_SIDED
    if command == "RANDOM"
        n = parse(Int, words[3])
        state = parse(Int64, words[4])
        names = vcat(["P$i" for i in 1:n], ["R$i" for i in 1:n])
        market = Market(name, TWO_SIDED, names, n)
        for agent in eachindex(names)
            preference = collect(agent <= n ? ((n + 1):(2 * n)) : (1:n))
            for size in n:-1:2
                state = mod(48271 * state, 2147483647)
                index = Int(mod(state, size)) + 1
                preference[size], preference[index] = preference[index], preference[size]
            end
            market.preferences[agent] = preference
        end
        return market
    end
    names = String[]
    houses = String[]
    proposers = 0
    for word in words[3:end]
        if word == "|"
            proposers = length(names)
            continue
        end
        pair = split(word, ':')
        pair[1] in names && fail("DUPLICATE AGENT $(pair[1])")
        if kind == HOUSING
            pair[2] in houses && fail("DUPLICATE HOUSE $(pair[2])")
            push!(houses, String(pair[2]))
        end
        push!(names, String(pair[1]))
    end
    Market(name, kind, names, proposers, houses)
end

function save!(market::Market, command::AbstractString, matching::Vector{Int})
    source = command == "GS" ? GS : command == "GSR" ? GSR : command == "BOSTON" ? BOSTON : command == "EGALITARIAN" ? EGALITARIAN : MINREGRET
    market.current = Saved(source, copy(matching))
end

function execute!(markets::Dict{String,Market}, line::AbstractString)
    words = split(line, ' ')
    command, name = words[1:2]
    if command in ("MARKET", "ROOMS", "HOUSES", "RANDOM")
        haskey(markets, name) && fail("DUPLICATE MARKET $name")
        market = new_market(words)
        response = if command == "RANDOM"
            "RANDOM $name n=$(market.proposers) seed=$(words[4])"
        elseif market.kind == TWO_SIDED
            "MARKET $name proposers=$(market.proposers) receivers=$(length(market.names) - market.proposers)"
        else
            "$command $name agents=$(length(market.names))"
        end
        markets[String(name)] = market
        return [response]
    end
    haskey(markets, name) || fail("UNKNOWN MARKET $name")
    market = markets[name]
    if command == "SHOW"
        return show_market(market)
    elseif command == "PREF"
        agent = agent_index(market, words[3])
        names = market.kind == HOUSING ? market.houses : market.names
        preference = Int[]
        for word in words[4:end]
            choice = findfirst(==(word), names)
            if isnothing(choice) || (market.kind == ROOMMATE && choice == agent) ||
               (market.kind == TWO_SIDED && (agent <= market.proposers) == (choice <= market.proposers))
                fail("BAD CHOICE $word")
            end
            choice in preference && fail("DUPLICATE CHOICE $word")
            push!(preference, choice)
        end
        market.preferences[agent] = preference
        market.kind == TWO_SIDED && (market.current = nothing)
        return ["PREF $name $(words[3]) length=$(length(preference))"]
    elseif command == "CHECK"
        return check_pairs(market, words)
    elseif command == "ROOMMATES"
        return roommates(market, length(words) == 3)
    elseif command in ("TTC", "SERIAL")
        require_kind(market, HOUSING)
        return command == "TTC" ? ttc(market) : serial(market, words)
    end
    require_kind(market, TWO_SIDED)
    if command == "CAPACITY"
        receiver = agent_index(market, words[3], RECEIVER)
        capacity = parse(Int, words[4])
        market.capacities[receiver] = capacity
        market.current = nothing
        return ["CAPACITY $name $(words[3]) $capacity"]
    elseif command in ("GS", "GSR", "BOSTON")
        run = command == "BOSTON" ? boston(market) : deferred(market; reverse = command == "GSR", verbose = length(words) == 3)
        save!(market, command, run.matching)
        label = command == "BOSTON" ? "applications" : "proposals"
        return vcat(["$command $name $label=$(run.count)"], run.history, ["MATCHING " * pair_text(market, run.matching)])
    elseif command == "HR"
        return hospital_report(market)
    elseif command == "MANIPULATE"
        return manipulate(market, agent_index(market, words[3], PROPOSER))
    elseif command == "STATS"
        return statistics(market)
    end
    lattice = enumerate_matchings(market)
    if command == "LATTICE"
        rows = ["LATTICE $name matchings=$(length(lattice.matchings)) rotations=$(length(lattice.rotations))"]
        for (index, result) in enumerate(lattice.matchings)
            origin = result.origin == 0 ? "-" : string(result.origin)
            via = result.via == 0 ? "-" : string(result.via)
            push!(rows, "MATCHING $index from=$origin via=$via cost=$(result.cost) regret=$(result.regret) " * pair_text(market, result.matching))
        end
        for (index, notation) in enumerate(lattice.rotations)
            push!(rows, "ROTATION $index $notation")
        end
        return rows
    end
    values = [command == "EGALITARIAN" ? result.cost : result.regret for result in lattice.matchings]
    best = argmin(values)
    selected = lattice.matchings[best].matching
    save!(market, command, selected)
    label = command == "EGALITARIAN" ? "cost" : "regret"
    ["$command $name matching=$best $label=$(values[best])", "MATCHING " * pair_text(market, selected)]
end

function main()
    command_count = parse(Int, readline())
    markets = Dict{String,Market}()
    for _ in 1:command_count
        line = readline()
        try
            for row in execute!(markets, line)
                println(row)
            end
        catch problem
            problem isa CommandError || rethrow()
            println("ERROR ", problem.message)
        end
    end
end
main()
