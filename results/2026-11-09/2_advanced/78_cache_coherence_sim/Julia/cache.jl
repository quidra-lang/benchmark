mutable struct HierarchyCache
    number_sets::Int
    ways::Int
    replacement::String
    blocks::Matrix{Int}
    states::Matrix{String}
    touched::Matrix{Int}
    bits::Matrix{Int}
    fills::Vector{Int}
    evictions::Vector{Int}
    clock::Int
end

function HierarchyCache(sets, ways, replacement)
    return HierarchyCache(
        sets,
        ways,
        replacement,
        fill(-1, sets, ways),
        fill("I", sets, ways),
        zeros(Int, sets, ways),
        zeros(Int, sets, ways - 1),
        zeros(Int, sets),
        zeros(Int, sets),
        0
    )
end

function cache_locate(cache, block)
    row = block % cache.number_sets + 1
    way = findfirst(==(block), view(cache.blocks, row, :))
    return way === nothing ? nothing : (row, way)
end

function cache_state(cache, block)
    place = cache_locate(cache, block)
    return place === nothing ? "I" : cache.states[place...]
end

function cache_change!(cache, block, state)
    place = cache_locate(cache, block)
    place !== nothing && (cache.states[place...] = state)
end

function cache_touch_way!(cache, row, way, filling=false)
    if cache.replacement == "LRU" || (cache.replacement == "FIFO" && filling)
        cache.clock += 1
        cache.touched[row, way] = cache.clock
    elseif cache.replacement == "PLRU"
        low, high, node = 0, cache.ways, 1
        while high - low > 1
            middle = (low + high) ÷ 2
            if way - 1 < middle
                cache.bits[row, node] = 1
                high = middle
                node *= 2
            else
                cache.bits[row, node] = 0
                low = middle
                node = 2 * node + 1
            end
        end
    end
end

function cache_touch!(cache, block)
    place = cache_locate(cache, block)
    place !== nothing && cache_touch_way!(cache, place...)
end

function cache_victim(cache, row)
    if cache.replacement == "PLRU"
        low, high, node = 0, cache.ways, 1
        while high - low > 1
            middle = (low + high) ÷ 2
            if cache.bits[row, node] == 0
                high = middle
                node *= 2
            else
                low = middle
                node = 2 * node + 1
            end
        end
        return low + 1
    end
    return argmin(view(cache.touched, row, :))
end

function cache_fill!(cache, block, state)
    row = block % cache.number_sets + 1
    empty_way = findfirst(==(-1), view(cache.blocks, row, :))
    way = empty_way === nothing ? cache_victim(cache, row) : empty_way
    victim = cache.blocks[row, way] == -1 ? nothing : (
        block=cache.blocks[row, way],
        state=cache.states[row, way]
    )
    victim !== nothing && (cache.evictions[row] += 1)
    cache.blocks[row, way] = block
    cache.states[row, way] = state
    cache.fills[row] += 1
    cache_touch_way!(cache, row, way, true)
    return victim
end

function cache_remove!(cache, block)
    place = cache_locate(cache, block)
    place === nothing && return nothing
    old = (block=block, state=cache.states[place...])
    cache.blocks[place...] = -1
    cache.states[place...] = "I"
    return old
end

function cache_order(cache, row)
    if cache.replacement == "PLRU"
        return cache.ways == 1 ? "-" : join(cache.bits[row, :])
    end
    active = [way for way in 1:cache.ways if cache.blocks[row, way] != -1]
    sort!(active; by=way -> (-cache.touched[row, way], way))
    return isempty(active) ? "-" : join(active .- 1, " ")
end

function cache_lines(cache)
    return [(
        block=cache.blocks[row, way],
        state=cache.states[row, way]
    ) for row in 1:cache.number_sets for way in 1:cache.ways if cache.blocks[row, way] != -1]
end
