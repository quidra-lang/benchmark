local dfg = require('dfg')
local F = require('report').rational
local M = {}
function M.dependency(counts, a, b)
    local f, r = dfg.get(counts, a, b), dfg.get(counts, b, a)
    return F(f - r, f + r + 1)
end
function M.loop(count) return F(count, count + 1) end
function M.split(counts, a, b, c)
    return F(dfg.get(counts, b, c) + dfg.get(counts, c, b), dfg.get(counts, a, b) + dfg.get(counts, a, c) + 1)
end
function M.join(counts, a, b, c)
    return F(dfg.get(counts, b, c) + dfg.get(counts, c, b), dfg.get(counts, b, a) + dfg.get(counts, c, a) + 1)
end
return M
