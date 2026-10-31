local M = {}
local function filled(n, value)
    local result = {}
    for i = 1, n do result[i] = value end
    return result
end
function M.btb(entries)
    return {size = entries, entries = {}}
end
function M.lookup(btb, pc)
    local entry = btb.entries[(pc // 4) % btb.size + 1]
    if entry and entry[1] == pc then return entry[2] end
end
function M.insert(btb, pc, target)
    btb.entries[(pc // 4) % btb.size + 1] = {pc, target}
end
function M.ras(depth)
    return {depth = depth, stack = {}}
end
function M.push(ras, address)
    if ras.depth == 0 then return end
    if #ras.stack == ras.depth then table.remove(ras.stack, 1) end
    ras.stack[#ras.stack + 1] = address
end
function M.pop(ras)
    return table.remove(ras.stack)
end
function M.direction(definition)
    local result = {scheme = definition.scheme, parameters = definition.parameters, history = 0}
    local p, scheme = result.parameters, result.scheme
    if scheme == 'ONEBIT' or scheme == 'TWOBIT' or scheme == 'GSHARE' then
        result.table = filled(p[1], scheme == 'ONEBIT' and 0 or 1)
    elseif scheme == 'TOURNAMENT' then
        result.local_table, result.global_table, result.chooser = filled(p[1], 1), filled(p[2], 1), filled(p[4], 1)
    end
    return result
end
function M.predict(d, pc, target)
    local scheme, index = d.scheme, pc // 4
    if scheme == 'STATIC_NT' or scheme == 'PERFECT' then return false end
    if scheme == 'BTFN' then return target < pc end
    if scheme == 'ONEBIT' then return d.table[index % #d.table + 1] == 1 end
    if scheme == 'TWOBIT' then return d.table[index % #d.table + 1] >= 2 end
    if scheme == 'GSHARE' then return d.table[(index ~ d.history) % #d.table + 1] >= 2 end
    local local_taken = d.local_table[index % #d.local_table + 1] >= 2
    local global_taken = d.global_table[(index ~ d.history) % #d.global_table + 1] >= 2
    if d.chooser[index % #d.chooser + 1] >= 2 then return global_taken end
    return local_taken
end
local function updated(value, taken)
    if taken then return math.min(3, value + 1) end
    return math.max(0, value - 1)
end
function M.update(d, pc, taken)
    local scheme, index = d.scheme, pc // 4
    if scheme == 'STATIC_NT' or scheme == 'BTFN' or scheme == 'PERFECT' then return end
    if scheme == 'TOURNAMENT' then
        local li, gi, ci = index % #d.local_table + 1, (index ~ d.history) % #d.global_table + 1, index % #d.chooser + 1
        local lp, gp = d.local_table[li] >= 2, d.global_table[gi] >= 2
        if lp ~= gp then d.chooser[ci] = updated(d.chooser[ci], gp == taken) end
        d.local_table[li], d.global_table[gi] = updated(d.local_table[li], taken), updated(d.global_table[gi], taken)
        d.history = (2 * d.history + (taken and 1 or 0)) % (1 << d.parameters[3])
    else
        if scheme == 'GSHARE' then index = index ~ d.history end
        index = index % #d.table + 1
        if scheme == 'ONEBIT' then d.table[index] = taken and 1 or 0
        else d.table[index] = updated(d.table[index], taken) end
        if scheme == 'GSHARE' then d.history = (2 * d.history + (taken and 1 or 0)) % (1 << d.parameters[2]) end
    end
end
function M.storage(d)
    local p, s = d.parameters, d.scheme
    if s == 'ONEBIT' then return p[1] end
    if s == 'TWOBIT' then return 2 * p[1] end
    if s == 'GSHARE' then return 2 * p[1] + p[2] end
    if s == 'TOURNAMENT' then return 2 * (p[1] + p[2] + p[4]) + p[3] end
    return 0
end
return M
