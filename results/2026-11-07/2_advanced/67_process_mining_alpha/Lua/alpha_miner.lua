local dfg = require('dfg')
local M = {}
function M.members(mask, names)
    local out = {}
    for i, name in ipairs(names) do if mask & (1 << (i - 1)) ~= 0 then out[#out + 1] = name end end
    return out
end
function M.extend(pair, index, side, names, relation)
    local bit, activity = 1 << (index - 1), names[index]
    local group, other = pair[side], pair[3 - side]
    if group & bit ~= 0 or relation(activity, activity) ~= '#' then return nil end
    for i, name in ipairs(names) do
        local b = 1 << (i - 1)
        if group & b ~= 0 and relation(activity, name) ~= '#' then return nil end
        if other & b ~= 0 then
            local r = side == 1 and relation(activity, name) or relation(name, activity)
            if r ~= '->' then return nil end
        end
    end
    return side == 1 and {pair[1] | bit, pair[2]} or {pair[1], pair[2] | bit}
end
local function sequence_less(a, b)
    for i = 1, math.min(#a, #b) do if a[i] ~= b[i] then return a[i] < b[i] end end
    return #a < #b
end
function M.less(a, b, names)
    if a[1] == b[1] then return sequence_less(M.members(a[2], names), M.members(b[2], names)) end
    return sequence_less(M.members(a[1], names), M.members(b[1], names))
end
function M.triangles(log)
    local counts = {}
    for _, row in ipairs(log) do
        for i = 1, #row.trace - 2 do
            local a, b = row.trace[i], row.trace[i + 1]
            if a == row.trace[i + 2] and a ~= b then local key = dfg.key(a, b); counts[key] = (counts[key] or 0) + row.weight end
        end
    end
    return counts
end
function M.relation(counts, triangles, a, b)
    local f, r = dfg.get(counts, a, b) > 0, dfg.get(counts, b, a) > 0
    local loop = a ~= b and dfg.get(triangles, a, b) > 0 and dfg.get(triangles, b, a) > 0
    if f and (not r or loop) then return '->' end
    if r and (not f or loop) then return '<-' end
    return f and r and '||' or '#'
end
return M
