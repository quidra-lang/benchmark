using Printf

@enum MethodKind PLURALITY RUNOFF IRV COOMBS BUCKLIN BORDA BALDWIN NANSON BLACK VETO CONDORCET COPELAND MINIMAX SCHULZE RANKEDPAIRS KEMENY APPROVAL STV
@enum MinimaxKind WINNING MARGIN OPPOSITION

struct Method
    kind::MethodKind
    parameter::Int
    minimax::MinimaxKind
end
Method(kind::MethodKind) = Method(kind, 0, WINNING)
const METHOD_KINDS = Dict(string(kind) => kind for kind in instances(MethodKind))
const MINIMAX_KINDS = Dict(string(kind) => kind for kind in instances(MinimaxKind))
const SUMMARY = Method.([PLURALITY, RUNOFF, IRV, COOMBS, BUCKLIN, BORDA, BALDWIN,
                       NANSON, BLACK, VETO, COPELAND, MINIMAX, SCHULZE, RANKEDPAIRS, KEMENY])

function parse_method(words::AbstractVector{<:AbstractString})
    kind = METHOD_KINDS[words[1]]
    kind == MINIMAX && return Method(kind, 0, MINIMAX_KINDS[words[2]])
    kind in (APPROVAL, STV) && return Method(kind, parse(Int, words[2]), WINNING)
    Method(kind)
end
function method_text(method::Method)
    method.kind == MINIMAX && return "$(method.kind) $(method.minimax)"
    method.kind in (APPROVAL, STV) && return "$(method.kind) $(method.parameter)"
    string(method.kind)
end

struct CommandError <: Exception
    message::String
end
fail(message::AbstractString) = throw(CommandError(String(message)))
struct Ballot
    votes::Int
    ranking::Vector{Int}
end
struct Tallies
    first::Vector{Int}
    last::Vector{Int}
    borda::Vector{Int}
    approval::Matrix{Int}
    nonblank::Int
end
struct Outcome
    order::Vector{Int}
    lines::Vector{String}
end
struct Removal
    candidate::Int
    tie::Bool
end

mutable struct Election
    number::Int
    names::Vector{String}
    active::BitVector
    tiebreak::Vector{Int}
    priority::Vector{Int}
    groups::Vector{Ballot}
    entry_ends::Vector{Int}
    total::Int
    cache::Dict{Int,Tallies}
    pairs::Union{Nothing,Matrix{Int}}
end
function Election(number::Int, names::Vector{String})
    priority = sortperm(names)
    Election(number, names, trues(length(names)), priority, invperm(priority),
             Ballot[], Int[], 0, Dict{Int,Tallies}(), nothing)
end
mutable struct Laboratory
    number::Int
    election::Union{Nothing,Election}
end
Laboratory() = Laboratory(0, nothing)

bit(candidate::Int) = 1 << (candidate - 1)
field_key(field::Vector{Int}) = sum(bit, field)
members(mask::Int, count::Int) = [a for a in 1:count if (mask & bit(a)) != 0]
effective(ranking::Vector{Int}, field::Vector{Int}) = filter(in(field), ranking)
name_list(election::Election, candidates::Vector{Int}, separator::String = ", ") =
    join(election.names[candidates], separator)
tie_mark(tie::Bool) = tie ? " (tie)" : ""
money(value::Int) = @sprintf("%d.%02d", div(value, 100), mod(value, 100))
function value_list(election::Election, field::Vector{Int}, scores::Vector{Int}; cents::Bool = false)
    join(("$(election.names[a]) $(cents ? money(scores[a]) : string(scores[a]))" for a in field), ", ")
end
ordered(election::Election, field::Vector{Int}, scores::Vector{Int}; descending::Bool = true) =
    sort(field; by = a -> (descending ? -scores[a] : scores[a], election.priority[a]))
preferred(election::Election, field::Vector{Int}) = sort(field; by = a -> election.priority[a])
function finish(election::Election, order::Vector{Int}, tie::Bool, lines::Vector{String})
    push!(lines, "winner: $(election.names[order[1]])$(tie_mark(tie))")
    Outcome(order, lines)
end
function candidate_index(election::Election, name::AbstractString)
    index = findfirst(==(name), election.names)
    isnothing(index) && fail("unknown candidate $name")
    index
end
function checked_names(election::Election, names::AbstractVector{<:AbstractString})
    result = Int[]
    for name in names
        candidate = candidate_index(election, name)
        candidate in result && fail("duplicate candidate $name")
        push!(result, candidate)
    end
    result
end
function finish_entry!(election::Election)
    push!(election.entry_ends, length(election.groups))
    empty!(election.cache)
    election.pairs = nothing
end

# Cached arrays are read-only after construction and contain no tiebreak decisions.
function tallies(election::Election, field::Vector{Int})
    key = field_key(field)
    haskey(election.cache, key) && return election.cache[key]
    count, size = length(election.names), length(field)
    first_votes, last_votes, borda = zeros(Int, count), zeros(Int, count), zeros(Int, count)
    approval = zeros(Int, size, count)
    nonblank = 0
    for group in election.groups
        ranking = effective(group.ranking, field)
        if !isempty(ranking)
            first_votes[ranking[1]] += group.votes
            nonblank += group.votes
        end
        if length(ranking) == size
            last_votes[ranking[end]] += group.votes
        else
            for candidate in setdiff(field, ranking)
                last_votes[candidate] += group.votes
            end
        end
        for (position, candidate) in enumerate(ranking)
            borda[candidate] += group.votes * (size - position)
            approval[position:size, candidate] .+= group.votes
        end
    end
    result = Tallies(first_votes, last_votes, borda, approval, nonblank)
    election.cache[key] = result
    result
end
function pairwise(election::Election)
    !isnothing(election.pairs) && return election.pairs
    count = length(election.names)
    result = zeros(Int, count, count)
    for group in election.groups
        positions = fill(count + 1, count)
        for (position, candidate) in enumerate(group.ranking)
            positions[candidate] = position
        end
        result .+= group.votes .* (positions .< transpose(positions))
    end
    election.pairs = result
    result
end
function majority(field::Vector{Int}, scores::Vector{Int})
    total = sum(scores[field])
    any(a -> 2 * scores[a] > total, field)
end
function look_back(election::Election, field::Vector{Int}, history::Vector{Vector{Int}})
    choices = copy(field)
    tie = false
    for round in length(history):-1:1
        scores = history[round]
        minimum_score = minimum(scores[choices])
        filter!(a -> scores[a] == minimum_score, choices)
        round == length(history) && (tie = length(choices) > 1)
    end
    Removal(choices[argmax(election.priority[choices])], tie)
end
function condorcet(election::Election, field::Vector{Int}; loser::Bool = false)
    scores = pairwise(election)
    for candidate in field
        others = filter(!=(candidate), field)
        found = loser ? all(b -> scores[candidate, b] < scores[b, candidate], others) :
                        all(b -> scores[candidate, b] > scores[b, candidate], others)
        found && return candidate
    end
    0
end

function elimination(election::Election, field::Vector{Int}; coombs::Bool = false, exhausted::Bool = false)
    remaining, removed = copy(field), Int[]
    history, lines = Vector{Int}[], String[]
    while true
        scores = tallies(election, remaining)
        round = length(lines) + 1
        active = sum(scores.first[remaining])
        line = exhausted ? "round $round: active $active, exhausted $(election.total - active)" :
                           "round $round: $(value_list(election, remaining, scores.first))"
        if length(remaining) == 1 || majority(remaining, scores.first)
            order = vcat(ordered(election, remaining, scores.first), reverse(removed))
            push!(lines, line)
            return exhausted ? Outcome(order, lines) : finish(election, order, false, lines)
        end
        if coombs
            maximum_last = maximum(scores.last[remaining])
            choices = filter(a -> scores.last[a] == maximum_last, remaining)
            sort!(choices; by = a -> (scores.first[a], -election.priority[a]))
            choice = Removal(choices[1], length(choices) > 1)
            line *= "; last $(value_list(election, remaining, scores.last))"
        else
            push!(history, scores.first)
            choice = look_back(election, remaining, history)
        end
        !exhausted && (line *= "; eliminated $(election.names[choice.candidate])$(tie_mark(choice.tie))")
        push!(lines, line)
        push!(removed, choice.candidate)
        filter!(!=(choice.candidate), remaining)
    end
end
function runoff(election::Election, field::Vector{Int})
    first_votes = tallies(election, field).first
    order = ordered(election, field, first_votes)
    lines = ["round 1: $(value_list(election, field, first_votes))"]
    tie = false
    if !majority(field, first_votes)
        finalists = sort(order[1:2])
        advance_tie = length(order) >= 3 && first_votes[order[2]] == first_votes[order[3]]
        second = tallies(election, finalists).first
        tie = second[order[1]] == second[order[2]]
        if second[order[2]] > second[order[1]]
            order[1], order[2] = order[2], order[1]
        end
        push!(lines, "finalists: $(name_list(election, finalists))$(tie_mark(advance_tie))")
        push!(lines, "round 2: $(value_list(election, finalists, second))")
    end
    finish(election, order, tie, lines)
end
function bucklin(election::Election, field::Vector{Int})
    scores = tallies(election, field)
    line = div(scores.nonblank, 2) + 1
    lines = ["majority: $line"]
    final_depth = length(field)
    for depth in eachindex(field)
        push!(lines, "round $depth: $(value_list(election, field, scores.approval[depth, :]))")
        if any(a -> scores.approval[depth, a] >= line, field)
            final_depth = depth
            break
        end
    end
    function before(a, b)
        for depth in final_depth:-1:1
            scores.approval[depth, a] != scores.approval[depth, b] &&
                return scores.approval[depth, a] > scores.approval[depth, b]
        end
        election.priority[a] < election.priority[b]
    end
    order = sort(field; lt = before)
    finish(election, order, scores.approval[final_depth, order[1]] == scores.approval[final_depth, order[2]], lines)
end
function borda_elimination(election::Election, field::Vector{Int}; nanson::Bool = false)
    remaining, tail = copy(field), Int[]
    history, lines = Vector{Int}[], String[]
    while length(remaining) >= 2
        scores = tallies(election, remaining).borda
        line = "round $(length(lines) + 1): $(value_list(election, remaining, scores))"
        if nanson
            total = sum(scores[remaining])
            below = filter(a -> scores[a] * length(remaining) < total, remaining)
            if isempty(below)
                push!(lines, line)
                break
            end
            line *= "; eliminated $(name_list(election, below))"
            removed = ordered(election, below, scores)
        else
            push!(history, scores)
            choice = look_back(election, remaining, history)
            removed = [choice.candidate]
            line *= "; eliminated $(election.names[choice.candidate])$(tie_mark(choice.tie))"
        end
        push!(lines, line)
        remaining = setdiff(remaining, removed)
        tail = vcat(removed, tail)
    end
    order = vcat(preferred(election, remaining), tail)
    finish(election, order, nanson && length(remaining) > 1, lines)
end

function pair_lines(election::Election, field::Vector{Int}, scores::Matrix{Int})
    lines = String[]
    for (index, first_candidate) in enumerate(field), second_candidate in field[(index + 1):end]
        forward, backward = scores[first_candidate, second_candidate], scores[second_candidate, first_candidate]
        result = forward == backward ? "tie" : election.names[forward > backward ? first_candidate : second_candidate]
        push!(lines, "$(election.names[first_candidate]) vs $(election.names[second_candidate]): $forward-$backward ($result)")
    end
    lines
end
function closure!(field::Vector{Int}, relation::AbstractMatrix{Bool})
    for via in field, first_candidate in field, second_candidate in field
        relation[first_candidate, second_candidate] |= relation[first_candidate, via] && relation[via, second_candidate]
    end
    relation
end
function condorcet_report(election::Election, field::Vector{Int})
    scores = pairwise(election)
    winner, loser = condorcet(election, field), condorcet(election, field; loser = true)
    weak = closure!(field, scores .>= transpose(scores))
    strong = closure!(field, scores .> transpose(scores))
    smith = filter(a -> all(b -> weak[a, b], field), field)
    schwartz = filter(a -> all(b -> !strong[b, a] || strong[a, b], field), field)
    Outcome(Int[], ["winner: $(winner == 0 ? "NONE" : election.names[winner])",
                    "loser: $(loser == 0 ? "NONE" : election.names[loser])",
                    "smith: $(name_list(election, smith))", "schwartz: $(name_list(election, schwartz))"])
end
function topological(election::Election, field::Vector{Int}, relation::AbstractMatrix{Bool})
    remaining, order = copy(field), Int[]
    tie = false
    while !isempty(remaining)
        choices = filter(a -> all(b -> a == b || !relation[b, a], remaining), remaining)
        isempty(order) && (tie = length(choices) > 1)
        chosen = choices[argmin(election.priority[choices])]
        push!(order, chosen)
        filter!(!=(chosen), remaining)
    end
    order, tie
end
function schulze(election::Election, field::Vector{Int})
    scores = pairwise(election)
    paths = zeros(Int, length(election.names), length(election.names))
    for a in field, b in field
        scores[a, b] > scores[b, a] && (paths[a, b] = scores[a, b])
    end
    for via in field, a in field, b in field
        if a != via && b != via && a != b
            paths[a, b] = max(paths[a, b], min(paths[a, via], paths[via, b]))
        end
    end
    order, tie = topological(election, field, paths .> transpose(paths))
    lines = pair_lines(election, field, paths)
    push!(lines, "ranking: $(name_list(election, order, " > "))")
    finish(election, order, tie, lines)
end
function ranked_pairs(election::Election, field::Vector{Int})
    scores = pairwise(election)
    pairs = [(a, b) for a in field for b in field if scores[a, b] > scores[b, a]]
    sort!(pairs; by = p -> (-scores[p[1], p[2]], scores[p[2], p[1]], election.priority[p[1]], election.priority[p[2]]))
    locked, reached = falses(size(scores)), falses(size(scores))
    lines = String[]
    for (a, b) in pairs
        accepted = !reached[b, a]
        push!(lines, "$(accepted ? "lock" : "skip") $(election.names[a])>$(election.names[b]) $(scores[a, b])-$(scores[b, a])")
        if accepted
            locked[a, b] = reached[a, b] = true
            closure!(field, reached)
        end
    end
    order, tie = topological(election, field, locked)
    finish(election, order, tie, lines)
end
function kemeny(election::Election, field::Vector{Int})
    scores = pairwise(election)
    count = length(election.names)
    limit = 1 << count
    best, ways, heads = zeros(Int, limit), zeros(Int, limit), zeros(Int, limit)
    ways[1] = 1
    mask = field_key(field)
    for subset in 1:(limit - 1)
        (subset & ~mask) != 0 && continue
        candidates = members(subset, count)
        best[subset + 1] = -1
        for candidate in candidates
            rest = subset - bit(candidate)
            score = best[rest + 1] + sum((scores[candidate, b] for b in candidates if b != candidate); init = 0)
            if score > best[subset + 1]
                best[subset + 1], ways[subset + 1], heads[subset + 1] = score, 0, 0
            end
            if score == best[subset + 1]
                ways[subset + 1] += ways[rest + 1]
                heads[subset + 1] |= bit(candidate)
            end
        end
    end
    remaining, order = mask, Int[]
    while remaining != 0
        chosen = first(a for a in election.tiebreak if (heads[remaining + 1] & bit(a)) != 0)
        push!(order, chosen)
        remaining -= bit(chosen)
    end
    lines = ["score: $(best[mask + 1])", "optimal: $(ways[mask + 1])", "ranking: $(name_list(election, order, " > "))"]
    finish(election, order, count_ones(heads[mask + 1]) > 1, lines)
end
function stv(election::Election, field::Vector{Int}, seats::Int)
    values = [isempty(effective(group.ranking, field)) ? 0 : 100 for group in election.groups]
    quota = div(100 * tallies(election, field).nonblank, seats + 1) + 1
    continuing, elected = copy(field), Int[]
    history, lines = Vector{Int}[], ["quota: $(money(quota))"]
    while true
        scores, owners = zeros(Int, length(election.names)), zeros(Int, length(election.groups))
        exhausted = 0
        for (index, group) in enumerate(election.groups)
            values[index] == 0 && continue
            ranking = effective(group.ranking, continuing)
            amount = group.votes * values[index]
            if isempty(ranking)
                exhausted += amount
            else
                owners[index] = ranking[1]
                scores[ranking[1]] += amount
            end
        end
        push!(history, scores)
        line = "round $(length(history)): $(value_list(election, continuing, scores; cents = true)); exhausted $(money(exhausted))"
        order = ordered(election, continuing, scores)
        if length(continuing) == seats - length(elected)
            append!(elected, order)
            push!(lines, line * "; elected $(name_list(election, order))")
            break
        end
        chosen = order[1]
        if scores[chosen] >= quota
            surplus = scores[chosen] - quota
            push!(elected, chosen)
            filter!(!=(chosen), continuing)
            for index in eachindex(values)
                owners[index] == chosen && (values[index] = div(values[index] * surplus, scores[chosen]))
            end
            push!(lines, line * "; elected $(election.names[chosen]) (surplus $(money(surplus)))")
            length(elected) == seats && break
        else
            choice = look_back(election, continuing, history)
            filter!(!=(choice.candidate), continuing)
            push!(lines, line * "; excluded $(election.names[choice.candidate])$(tie_mark(choice.tie))")
        end
    end
    push!(lines, "elected: $(name_list(election, elected))")
    Outcome(Int[], lines)
end

function tally(election::Election, field::Vector{Int}, method::Method)
    kind = method.kind
    kind == RUNOFF && return runoff(election, field)
    kind in (IRV, COOMBS) && return elimination(election, field; coombs = kind == COOMBS)
    kind == BUCKLIN && return bucklin(election, field)
    kind in (BALDWIN, NANSON) && return borda_elimination(election, field; nanson = kind == NANSON)
    kind == CONDORCET && return condorcet_report(election, field)
    kind == SCHULZE && return schulze(election, field)
    kind == RANKEDPAIRS && return ranked_pairs(election, field)
    kind == KEMENY && return kemeny(election, field)
    kind == STV && return stv(election, field, method.parameter)
    base = tallies(election, field)
    scores, lines = zeros(Int, length(election.names)), String[]
    label, descending, winner = "scores", true, 0
    if kind == PLURALITY
        scores, label = base.first, "votes"
    elseif kind in (BORDA, BLACK)
        scores = base.borda
        if kind == BLACK
            winner = condorcet(election, field)
            push!(lines, "condorcet: $(winner == 0 ? "NONE" : election.names[winner])")
        end
    elseif kind == VETO
        scores, label, descending = base.last, "vetoes", false
    elseif kind == APPROVAL
        scores, label = base.approval[min(method.parameter, length(field)), :], "approvals"
    elseif kind == COPELAND
        matrix = pairwise(election)
        parts = String[]
        for a in field
            others = filter(!=(a), field)
            wins = count(b -> matrix[a, b] > matrix[b, a], others)
            draws = count(b -> matrix[a, b] == matrix[b, a], others)
            losses = count(b -> matrix[a, b] < matrix[b, a], others)
            scores[a] = 2 * wins + draws
            push!(parts, "$(election.names[a]) $(div(scores[a], 2)).$(mod(scores[a], 2) * 5) ($wins-$draws-$losses)")
        end
        push!(lines, "scores: $(join(parts, ", "))")
    elseif kind == MINIMAX
        matrix = pairwise(election)
        descending = false
        for a in field, b in field
            a == b && continue
            opposition, support = matrix[b, a], matrix[a, b]
            value = method.minimax == OPPOSITION ? opposition :
                    opposition <= support ? 0 : method.minimax == MARGIN ? opposition - support : opposition
            scores[a] = max(scores[a], value)
        end
    end
    order = ordered(election, field, scores; descending)
    tie = scores[order[1]] == scores[order[2]]
    if winner != 0
        filter!(!=(winner), order)
        pushfirst!(order, winner)
        tie = false
    end
    kind != COPELAND && push!(lines, "$label: $(value_list(election, field, scores))")
    finish(election, order, tie, lines)
end
function ballots_report(election::Election)
    counts = Dict{String,Int}()
    field = findall(election.active)
    for group in election.groups
        ranking = effective(group.ranking, field)
        notation = isempty(ranking) ? "-" : name_list(election, ranking, ">")
        counts[notation] = get(counts, notation, 0) + group.votes
    end
    order = sort!(collect(keys(counts)); by = text -> (-counts[text], text))
    lines = ["total $(election.total), blank $(get(counts, "-", 0)), distinct $(length(counts))"]
    append!(lines, ["$(counts[text]) $text" for text in order])
end

function execute!(lab::Laboratory, line::String)
    words = split(line)
    command = words[1]
    if command == "CANDIDATES"
        names = String.(words[2:end])
        length(names) == 1 && fail("too few candidates")
        seen = Set{String}()
        for name in names
            name in seen && fail("duplicate candidate $name")
            push!(seen, name)
        end
        election = Election(lab.number + 1, names)
        lab.number += 1
        lab.election = election
        return ["election $(lab.number): $(length(names)) candidates"]
    end
    election = lab.election
    isnothing(election) && fail("no election")
    if command == "BALLOT"
        ranking = words[3] == "-" ? Int[] : checked_names(election, split(words[3], '>'))
        votes = parse(Int, words[2])
        push!(election.groups, Ballot(votes, ranking))
        election.total += votes
        finish_entry!(election)
        return String[]
    elseif command == "RANDOM"
        random_count = parse(Int, words[2])
        state = parse(Int64, words[3])
        for _ in 1:random_count
            ranking = findall(election.active)
            for size in length(ranking):-1:2
                state = mod(48271 * state, 2147483647)
                index = Int(mod(state, size)) + 1
                ranking[size], ranking[index] = ranking[index], ranking[size]
            end
            state = mod(48271 * state, 2147483647)
            ranking = ranking[1:(Int(mod(state, length(ranking))) + 1)]
            push!(election.groups, Ballot(1, ranking))
        end
        election.total += random_count
        finish_entry!(election)
        return String[]
    elseif command == "UNDO"
        isempty(election.entry_ends) && fail("nothing to undo")
        pop!(election.entry_ends)
        stop = isempty(election.entry_ends) ? 0 : election.entry_ends[end]
        for group in @view election.groups[(stop + 1):end]
            election.total -= group.votes
        end
        resize!(election.groups, stop)
        empty!(election.cache)
        election.pairs = nothing
        return String[]
    elseif command in ("WITHDRAW", "RESTORE")
        candidate = candidate_index(election, words[2])
        if command == "WITHDRAW"
            !election.active[candidate] && fail("already withdrawn $(words[2])")
            count(election.active) <= 2 && fail("too few candidates")
            election.active[candidate] = false
        else
            election.active[candidate] && fail("not withdrawn $(words[2])")
            election.active[candidate] = true
        end
        return String[]
    elseif command == "TIEBREAK"
        order = checked_names(election, words[2:end])
        length(order) != length(election.names) && fail("incomplete tiebreak")
        election.tiebreak = order
        election.priority = invperm(order)
        return String[]
    end
    heading = "[$line]"
    field = findall(election.active)
    if command == "STATUS"
        withdrawn = findall(!, election.active)
        return [heading, "election $(election.number)", "active: $(name_list(election, field))",
                "withdrawn: $(isempty(withdrawn) ? "none" : name_list(election, withdrawn))",
                "tiebreak: $(name_list(election, election.tiebreak))",
                "ballots: $(election.total) in $(length(election.entry_ends)) entries"]
    end
    isempty(election.entry_ends) && fail("no ballots")
    if command in ("RANKING", "SPOILERS")
        method = parse_method(words[2:end])
        method.kind in (CONDORCET, STV) && fail("not rankable")
        command == "SPOILERS" && length(field) < 3 && fail("too few candidates")
        result = tally(election, field, method)
        command == "RANKING" && return [heading, name_list(election, result.order, " > ")]
        winner = result.order[1]
        lines = [heading, "winner: $(election.names[winner])"]
        for candidate in field
            candidate == winner && continue
            other = tally(election, filter(!=(candidate), field), method).order[1]
            push!(lines, "without $(election.names[candidate]): $(election.names[other])$(other == winner ? "" : " (changed)")")
        end
        return lines
    end
    compared = Int[]
    if command == "COMPARE"
        for name in words[2:end]
            candidate = candidate_index(election, name)
            !election.active[candidate] && fail("withdrawn candidate $name")
            push!(compared, candidate)
        end
        compared[1] == compared[2] && fail("same candidate")
    end
    command == "STV" && parse(Int, words[2]) >= length(field) && fail("too many seats")
    lines = [heading]
    if command == "BALLOTS"
        append!(lines, ballots_report(election))
    elseif command == "PROFILE"
        scores = tallies(election, field)
        for candidate in field
            cumulative = scores.approval[:, candidate]
            counts = diff(vcat(0, cumulative))
            push!(lines, "$(election.names[candidate]): $(join(counts, " ")) unranked $(election.total - cumulative[end])")
        end
    elseif command == "PAIRWISE"
        append!(lines, pair_lines(election, field, pairwise(election)))
    elseif command == "EXHAUSTED"
        append!(lines, elimination(election, field; exhausted = true).lines)
    elseif command in ("SUMMARY", "COMPARE")
        wins = zeros(Int, length(election.names))
        ahead = [String[], String[]]
        for method in SUMMARY
            result = tally(election, field, method)
            if command == "SUMMARY"
                winner = result.order[1]
                wins[winner] += 1
                push!(lines, "$(method_text(method)): $(election.names[winner])")
            else
                first_position = findfirst(==(compared[1]), result.order)
                second_position = findfirst(==(compared[2]), result.order)
                push!(ahead[first_position < second_position ? 1 : 2], method_text(method))
            end
        end
        if command == "SUMMARY"
            push!(lines, "wins: $(value_list(election, field, wins))")
        else
            matrix = pairwise(election)
            a, b = compared
            push!(lines, "$(election.names[a]) $(matrix[a, b]), $(election.names[b]) $(matrix[b, a]), neither $(election.total - matrix[a, b] - matrix[b, a])")
            for side in 1:2
                text = isempty(ahead[side]) ? "none" : join(ahead[side], ", ")
                push!(lines, "$(election.names[compared[side]]) ahead: $text")
            end
        end
    else
        append!(lines, tally(election, field, parse_method(words)).lines)
    end
    lines
end

function main()
    input = readlines()
    lab = Laboratory()
    for index in 1:parse(Int, input[1])
        try
            for line in execute!(lab, input[index + 1])
                println(line)
            end
        catch error
            error isa CommandError || rethrow()
            println("ERROR ", error.message)
        end
    end
end
main()
