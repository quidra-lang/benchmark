const SHANTEN_PATTERN_CACHE = Dict{Any,Any}()
const SHANTEN_NUMBER_CACHE = Dict{Any,NTuple{3,Int}}()

function shanten_patterns(counts, suited)
    key = (Tuple(counts), suited)
    return get!(SHANTEN_PATTERN_CACHE, key) do
        first_index = findfirst(>(0), counts)
        first_index === nothing && return [(0, 0, 0)]
        choices = [([first_index], 0, 0, 0)]
        counts[first_index] >= 3 && push!(choices, (fill(first_index, 3), 1, 0, 0))
        if counts[first_index] >= 2
            push!(choices, (fill(first_index, 2), 0, 1, 0))
            push!(choices, (fill(first_index, 2), 0, 0, 1))
        end
        if suited
            first_index <= 7 && counts[first_index + 1] > 0 && counts[first_index + 2] > 0 && push!(
                choices,
                ([first_index, first_index + 1, first_index + 2], 1, 0, 0)
            )
            for difference in (1, 2)
                other = first_index + difference
                other <= 9 && counts[other] > 0 && push!(choices, ([first_index, other], 0, 1, 0))
            end
        end
        best = Dict{Tuple{Int,Int},Int}()
        for (removed, extra_sets, extra_partial, extra_pair) in choices
            remaining = copy(counts)
            for index in removed
                remaining[index] -= 1
            end
            for (sets, partial, pair) in shanten_patterns(remaining, suited)
                sets += extra_sets
                pair += extra_pair
                (sets > 4 || pair > 1) && continue
                partial = min(4, partial + extra_partial)
                state = (sets, pair)
                best[state] = max(get(best, state, -1), partial)
            end
        end
        [(sets, partial, pair) for ((sets, pair), partial) in best]
    end
end

function standard_shanten(counts)
    states = Dict((0, 0) => 0)
    for (start, stop) in ((1, 9), (10, 18), (19, 27), (28, 34))
        local_patterns = shanten_patterns(counts[start:stop], start < 28)
        combined = Dict{Tuple{Int,Int},Int}()
        for ((sets, pair), partial) in states, (local_sets, local_partial, local_pair) in local_patterns
            total_sets, total_pair = sets + local_sets, pair + local_pair
            (total_sets > 4 || total_pair > 1) && continue
            state = (total_sets, total_pair)
            combined[state] = max(get(combined, state, -1), min(4, partial + local_partial))
        end
        states = combined
    end
    return minimum(8 - 2 * sets - min(partial, 4 - sets) - pair for ((sets, pair), partial) in states)
end

function shanten_numbers(counts)
    return get!(SHANTEN_NUMBER_CACHE, Tuple(counts)) do
        pairs, kinds = count(>=(2), counts), count(>=(1), counts)
        seven = 6 - pairs + max(0, 7 - kinds)
        orphans = 13 - count(kind -> counts[kind + 1] >= 1, YAOCHUU) - Int(any(
            kind -> counts[kind + 1] >= 2,
            YAOCHUU
        ))
        (standard_shanten(counts), seven, orphans)
    end
end
