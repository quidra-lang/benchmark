local M = {}
function M.key(a, b) return a .. ':' .. b end
function M.get(counts, a, b) return counts[M.key(a, b)] or 0 end
function M.count(log)
    local counts = {}
    for _, row in ipairs(log) do
        for i = 1, #row.trace - 1 do
            local key = M.key(row.trace[i], row.trace[i + 1]); counts[key] = (counts[key] or 0) + row.weight
        end
    end
    return counts
end
function M.relation(counts, a, b)
    local f, r = M.get(counts, a, b) > 0, M.get(counts, b, a) > 0
    if f and not r then return '->' end
    if r and not f then return '<-' end
    return f and '||' or '#'
end
function M.table(rows, width)
    local cells, out = {}, {}
    for i = 1, #rows do cells[#cells + 1] = string.format('%' .. width .. 'd', i) end
    out[1] = '    ' .. table.concat(cells)
    for i, row in ipairs(rows) do
        cells = {string.format('%4d', i)}
        for _, value in ipairs(row) do cells[#cells + 1] = string.format('%' .. width .. 's', tostring(value)) end
        out[#out + 1] = table.concat(cells)
    end
    return out
end
function M.footprint(activities, relation)
    local out, rows = {}, {}
    for i, a in ipairs(activities) do
        out[#out + 1] = 'ACTIVITY ' .. i .. ' ' .. a
        rows[i] = {}; for j, b in ipairs(activities) do rows[i][j] = relation(a, b) end
    end
    for _, line in ipairs(M.table(rows, 4)) do out[#out + 1] = line end
    return out
end
return M
