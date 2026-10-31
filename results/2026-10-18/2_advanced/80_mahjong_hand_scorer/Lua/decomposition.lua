local tiles = require('tiles')
local decomposition = {}
local cache, cache_size = {}, 0
local function set_less(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    return a[1] == a[#a] and b[1] ~= b[#b]
end
function decomposition.standard(counts, meld_count)
    meld_count = meld_count or 0
    local key = meld_count .. ':' .. table.concat(counts, ',')
    if cache[key] then return cache[key] end
    local needed, total = 4 - meld_count, 0; for _, count in ipairs(counts) do total = total + count end
    if total ~= needed * 3 + 2 then return {} end
    local remaining, found, seen = {table.unpack(counts)}, {}, {}
    local function visit(pair, sets)
        if #sets == needed then
            for _, count in ipairs(remaining) do if count > 0 then return end end
            local ordered = {}; for index, block in ipairs(sets) do ordered[index] = block end; table.sort(ordered, set_less)
            local parts = {tostring(pair)}; for _, block in ipairs(ordered) do parts[#parts + 1] = table.concat(block, ',') end
            local identity = table.concat(parts, ':')
            if not seen[identity] then seen[identity] = true; found[#found + 1] = {pair = pair, sets = ordered} end
            return
        end
        local first; for index, count in ipairs(remaining) do if count > 0 then first = index; break end end
        if not first then return end
        local kind = first - 1
        if remaining[first] >= 3 then
            remaining[first] = remaining[first] - 3; sets[#sets + 1] = {kind, kind, kind}; visit(pair, sets); table.remove(sets); remaining[first] = remaining[first] + 3
        end
        if kind < 27 and kind % 9 <= 6 and remaining[first + 1] > 0 and remaining[first + 2] > 0 then
            for index = first, first + 2 do remaining[index] = remaining[index] - 1 end
            sets[#sets + 1] = {kind, kind + 1, kind + 2}; visit(pair, sets); table.remove(sets)
            for index = first, first + 2 do remaining[index] = remaining[index] + 1 end
        end
    end
    for pair = 1, 34 do if remaining[pair] >= 2 then remaining[pair] = remaining[pair] - 2; visit(pair - 1, {}); remaining[pair] = remaining[pair] + 2 end end
    if cache_size >= 16384 then cache, cache_size = {}, 0 end
    cache[key], cache_size = found, cache_size + 1
    return found
end
function decomposition.seven_pairs(counts)
    local pairs = 0
    for _, count in ipairs(counts) do if count == 2 then pairs = pairs + 1 elseif count ~= 0 then return false end end
    return pairs == 7
end
function decomposition.thirteen_orphans(counts)
    local total, allowed = 0, {}
    for _, kind in ipairs(tiles.yaochuu_kinds) do if counts[kind + 1] == 0 then return false end; allowed[kind + 1] = true end
    for index, count in ipairs(counts) do total = total + count; if count > 0 and not allowed[index] then return false end end
    return total == 14
end
function decomposition.winning(counts, meld_count)
    meld_count = meld_count or 0
    return #decomposition.standard(counts, meld_count) > 0 or meld_count == 0 and (decomposition.seven_pairs(counts) or decomposition.thirteen_orphans(counts))
end
function decomposition.waiting_tiles(hand, melds, meld_count)
    local counts, waiting = {table.unpack(hand)}, {}
    for kind = 0, 33 do
        if hand[kind + 1] + melds[kind + 1] <= 3 then
            counts[kind + 1] = counts[kind + 1] + 1
            if decomposition.winning(counts, meld_count) then waiting[#waiting + 1] = kind end
            counts[kind + 1] = counts[kind + 1] - 1
        end
    end
    return waiting
end
function decomposition.wait_shape(form, block, winning, hand_counts)
    if form == 'chiitoitsu' then return 'tanki' end
    if form == 'kokushi' then for _, kind in ipairs(tiles.yaochuu_kinds) do if hand_counts[kind + 1] ~= 1 then return 'single' end end; return 'thirteen' end
    if #block == 2 then return 'tanki' end
    if block[1] == block[#block] then return 'shanpon' end
    local first = block[1]
    if winning == first + 1 then return 'kanchan' end
    if first % 9 == 0 and winning == first + 2 or first % 9 == 6 and winning == first then return 'penchan' end
    return 'ryanmen'
end
return decomposition
