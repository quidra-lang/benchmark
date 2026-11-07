local yaochuu = require('tiles').yaochuu_kinds
local shanten = {}
local pattern_cache, pattern_size, number_cache, number_size = {}, 0, {}, 0
local patterns
patterns = function(counts, suited)
    local identity = (suited and 's' or 'h') .. table.concat(counts, ',')
    if pattern_cache[identity] then return pattern_cache[identity] end
    local first; for index, count in ipairs(counts) do if count > 0 then first = index; break end end
    if first == nil then return {[0] = 0} end
    local choices = {{removed = {first}, sets = 0, partial = 0, pair = 0}}
    if counts[first] >= 3 then choices[#choices + 1] = {removed = {first, first, first}, sets = 1, partial = 0, pair = 0} end
    if counts[first] >= 2 then
        choices[#choices + 1] = {removed = {first, first}, sets = 0, partial = 1, pair = 0}
        choices[#choices + 1] = {removed = {first, first}, sets = 0, partial = 0, pair = 1}
    end
    if suited then
        if first <= 7 and counts[first + 1] > 0 and counts[first + 2] > 0 then choices[#choices + 1] = {removed = {first, first + 1, first + 2}, sets = 1, partial = 0, pair = 0} end
        for difference = 1, 2 do
            local other = first + difference
            if other <= 9 and counts[other] > 0 then choices[#choices + 1] = {removed = {first, other}, sets = 0, partial = 1, pair = 0} end
        end
    end
    local best = {}
    for _, choice in ipairs(choices) do
        local remaining = {table.unpack(counts)}; for _, index in ipairs(choice.removed) do remaining[index] = remaining[index] - 1 end
        for key, partial in pairs(patterns(remaining, suited)) do
            local sets, pair = key // 2 + choice.sets, key % 2 + choice.pair
            if sets <= 4 and pair <= 1 then
                local combined = sets * 2 + pair; local value = math.min(4, partial + choice.partial)
                if value > (best[combined] or -1) then best[combined] = value end
            end
        end
    end
    if pattern_size >= 65536 then pattern_cache, pattern_size = {}, 0 end
    pattern_cache[identity], pattern_size = best, pattern_size + 1
    return best
end
function shanten.standard(counts)
    local states = {[0] = 0}
    for _, range in ipairs({{1, 9}, {10, 18}, {19, 27}, {28, 34}}) do
        local local_counts = {}; for index = range[1], range[2] do local_counts[#local_counts + 1] = counts[index] end
        local options, combined = patterns(local_counts, range[1] < 28), {}
        for key, partial in pairs(states) do
            for local_key, local_partial in pairs(options) do
                local sets, pair = key // 2 + local_key // 2, key % 2 + local_key % 2
                if sets <= 4 and pair <= 1 then
                    local target, value = sets * 2 + pair, math.min(4, partial + local_partial)
                    if value > (combined[target] or -1) then combined[target] = value end
                end
            end
        end
        states = combined
    end
    local best = 8
    for key, partial in pairs(states) do local sets, pair = key // 2, key % 2; best = math.min(best, 8 - 2 * sets - math.min(partial, 4 - sets) - pair) end
    return best
end
function shanten.numbers(counts)
    local identity = table.concat(counts, ',')
    if number_cache[identity] then return table.unpack(number_cache[identity]) end
    local pairs_count, kinds, orphans, duplicate = 0, 0, 13, false
    for _, count in ipairs(counts) do if count >= 1 then kinds = kinds + 1 end; if count >= 2 then pairs_count = pairs_count + 1 end end
    for _, kind in ipairs(yaochuu) do if counts[kind + 1] >= 1 then orphans = orphans - 1 end; if counts[kind + 1] >= 2 then duplicate = true end end
    if duplicate then orphans = orphans - 1 end
    local values = {shanten.standard(counts), 6 - pairs_count + math.max(0, 7 - kinds), orphans}
    if number_size >= 8192 then number_cache, number_size = {}, 0 end
    number_cache[identity], number_size = values, number_size + 1
    return table.unpack(values)
end
return shanten
