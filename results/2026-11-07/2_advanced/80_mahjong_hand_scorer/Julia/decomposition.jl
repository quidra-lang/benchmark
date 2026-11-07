const DECOMPOSITION_CACHE = Dict{Any,Any}()
set_key(block) = (block[1], block[1] != block[end])

function standard_decompositions(counts, meld_count=0)
    key = (Tuple(counts), meld_count)
    return get!(DECOMPOSITION_CACHE, key) do
        needed = 4 - meld_count
        sum(counts) != 3 * needed + 2 && return NamedTuple[]
        remaining = copy(counts)
        found = Dict{String,Any}()
        function visit(pair, sets)
            if length(sets) == needed
                if all(iszero, remaining)
                    ordered = sort(sets; by=set_key)
                    signature = string(pair, ":", join((join(block, ",") for block in ordered), ";"))
                    found[signature] = (pair=pair, sets=ordered)
                end
                return
            end
            first_index = findfirst(>(0), remaining)
            first_index === nothing && return
            kind = first_index - 1
            if remaining[first_index] >= 3
                remaining[first_index] -= 3
                visit(pair, vcat(sets, [(kind, kind, kind)]))
                remaining[first_index] += 3
            end
            if kind < 27 && kind % 9 <= 6 && remaining[first_index + 1] > 0 && remaining[first_index + 2] > 0
                remaining[first_index:first_index + 2] .-= 1
                visit(pair, vcat(sets, [(kind, kind + 1, kind + 2)]))
                remaining[first_index:first_index + 2] .+= 1
            end
        end
        for pair in 0:33
            if remaining[pair + 1] >= 2
                remaining[pair + 1] -= 2
                visit(pair, NTuple{3,Int}[])
                remaining[pair + 1] += 2
            end
        end
        collect(values(found))
    end
end

seven_pairs(counts) = count(==(2), counts) == 7 && all(value -> value in (0, 2), counts)
thirteen_orphans(counts) = sum(counts) == 14 && all(kind -> counts[kind + 1] > 0, YAOCHUU) && all(
    kind -> kind in YAOCHUU || counts[kind + 1] == 0,
    0:33
)
winning_form(
    counts,
    meld_count=0
) = !isempty(standard_decompositions(
    counts,
    meld_count
)) || meld_count == 0 && (seven_pairs(counts) || thirteen_orphans(counts))

function waiting_tiles(hand_counts, meld_counts, meld_count)
    waiting, concealed = Int[], copy(hand_counts)
    for kind in 0:33
        hand_counts[kind + 1] + meld_counts[kind + 1] >= 4 && continue
        concealed[kind + 1] += 1
        winning_form(concealed, meld_count) && push!(waiting, kind)
        concealed[kind + 1] -= 1
    end
    return waiting
end

function wait_shape(form, block, winning_tile, hand_counts)
    form == "chiitoitsu" && return "tanki"
    form == "kokushi" && return all(kind -> hand_counts[kind + 1] == 1, YAOCHUU) ? "thirteen" : "single"
    length(block) == 2 && return "tanki"
    block[1] == block[end] && return "shanpon"
    first_kind = block[1]
    winning_tile == first_kind + 1 && return "kanchan"
    ((first_kind % 9 == 0 && winning_tile == first_kind + 2) || (first_kind % 9 == 6 && winning_tile == first_kind)) && return "penchan"
    return "ryanmen"
end
