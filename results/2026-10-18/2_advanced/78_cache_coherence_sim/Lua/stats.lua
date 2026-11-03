local stats = {}
stats.transactions = {'BusRd', 'BusRdX', 'BusUpgr', 'BusWr', 'WB'}
stats.services = {'l1', 'upgrade', 'through', 'cache', 'l2', 'memory'}
stats.misses = {'compulsory', 'capacity', 'conflict', 'coherence'}
stats.snoops = {'invalidations_sent', 'invalidations_received', 'supplied', 'back_invalidations'}
local zero = {__index = function() return 0 end}
function stats.counter() return setmetatable({}, zero) end
function stats.empty()
    return {simple = stats.counter(), misses = stats.counter(), service = stats.counter(), bus = stats.counter(), snoop = stats.counter(), finish = 0}
end
function stats.total(per_core)
    local total = stats.empty()
    for _, entry in ipairs(per_core) do
        for _, section in ipairs({'simple', 'misses', 'service', 'bus', 'snoop'}) do for key, value in pairs(entry[section]) do total[section][key] = total[section][key] + value end end
        total.finish = math.max(total.finish, entry.finish)
    end
    return total
end
function stats.fraction(p, q)
    local a, b = p, q; while b ~= 0 do a, b = b, a % b end
    return (p // a) .. '/' .. (q // a)
end
function stats.decimal(p, q)
    local value = (2 * p * 100 + q) // (2 * q)
    return (value // 100) .. '.' .. string.format('%02d', value % 100)
end
function stats.core_string(cores)
    local values = {}; for core in pairs(cores) do values[#values + 1] = core end; table.sort(values)
    return #values > 0 and table.concat(values) or '-'
end
function stats.range_counts(values, labels, limits)
    local counts, output = {}, {}
    for index = 1, #labels do counts[index] = 0 end
    for _, value in ipairs(values) do
        local bucket = #labels
        for index, limit in ipairs(limits) do if value <= limit then bucket = index; break end end
        counts[bucket] = counts[bucket] + 1
    end
    for index, label in ipairs(labels) do output[index] = label .. ':' .. counts[index] end
    return table.concat(output, ' ')
end
function stats.six_lines(label, entry)
    local s, misses, service, bus, snoop = entry.simple, entry.misses, entry.service, entry.bus, entry.snoop
    local function named(names, values)
        local pieces = {}; for _, name in ipairs(names) do pieces[#pieces + 1] = name .. ' ' .. values[name] end; return table.concat(pieces, ' ')
    end
    return {label .. ' accesses ' .. s.accesses .. ' reads ' .. s.reads .. ' writes ' .. s.writes .. ' hits ' .. s.hits .. ' misses ' .. s.misses .. ' fences ' .. s.fences,
        label .. ' misses ' .. named(stats.misses, misses) .. ' true_sharing ' .. misses.true_sharing .. ' false_sharing ' .. misses.false_sharing,
        label .. ' service ' .. named(stats.services, service), label .. ' bus ' .. named(stats.transactions, bus), label .. ' snoop ' .. named(stats.snoops, snoop),
        label .. ' time latency ' .. s.latency .. ' amat ' .. stats.fraction(s.latency, s.accesses) .. ' ' .. stats.decimal(s.latency, s.accesses) .. ' fence_stall ' .. s.fence_stall .. ' finish ' .. entry.finish}
end
return stats
