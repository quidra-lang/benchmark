local M = {}
function M.keys(map) local out = {}; for k in pairs(map) do out[#out + 1] = k end; table.sort(out); return out end
function M.new(size, taxa)
    local t = {size = size, adjacent = {}, next_node = size + 1, negative = 0}
    for _, i in ipairs(taxa) do t.adjacent[i] = {} end
    return t
end
function M.internal(t) local n = t.next_node; t.next_node = n + 1; t.adjacent[n] = {}; return n end
function M.connect(t, a, b, length) length = length or 0.0; t.adjacent[a][b] = length; t.adjacent[b][a] = length end
function M.disconnect(t, a, b)
    local length = t.adjacent[a][b]; t.adjacent[a][b] = nil; t.adjacent[b][a] = nil; return length
end
function M.copy(t)
    local out = M.new(t.size, {}); out.next_node, out.negative = t.next_node, t.negative
    for a, neighbors in pairs(t.adjacent) do out.adjacent[a] = {}; for b, length in pairs(neighbors) do out.adjacent[a][b] = length end end
    return out
end
function M.taxa(t)
    local out = {}; for _, i in ipairs(M.keys(t.adjacent)) do if i <= t.size then out[#out + 1] = i end end; return out
end
function M.internals(t)
    local out = {}; for _, i in ipairs(M.keys(t.adjacent)) do if i > t.size then out[#out + 1] = i end end; return out
end
function M.edges(t)
    local out = {}
    for _, a in ipairs(M.keys(t.adjacent)) do
        for _, b in ipairs(M.keys(t.adjacent[a])) do if a < b then out[#out + 1] = {a, b, t.adjacent[a][b]} end end
    end
    return out
end
function M.rooted(t, outgroup)
    local r = {tree = t, outgroup = outgroup, root = M.keys(t.adjacent[outgroup])[1], parents = {}, children = {}, masks = {}, order = {}}
    local function visit(n, parent)
        r.parents[n] = parent; r.order[#r.order + 1] = n; r.children[n] = {}
        local mask = n <= t.size and (1 << (n - 1)) or 0
        for _, c in ipairs(M.keys(t.adjacent[n])) do
            if c ~= parent then visit(c, n); r.children[n][#r.children[n] + 1] = c; mask = mask | r.masks[c] end
        end
        r.masks[n] = mask
    end
    visit(r.root, nil); r.ingroup = r.masks[r.root] ~ (1 << (outgroup - 1)); return r
end
function M.splits(r)
    local out = {}; for _, n in ipairs(M.internals(r.tree)) do if n ~= r.root then out[r.masks[n]] = true end end; return out
end
function M.lengths(r)
    local out = {}
    for i = 2, #r.order do
        local n = r.order[i]; local mask = n == r.outgroup and r.ingroup or r.masks[n]
        out[mask] = r.tree.adjacent[n][r.parents[n]]
    end
    return out
end
function M.star(size, taxa)
    local t = M.new(size, taxa); local root = M.internal(t)
    for _, i in ipairs(taxa) do M.connect(t, root, i) end
    return t
end
function M.nj(matrix, taxa)
    local active = {}; for i, v in ipairs(taxa) do active[i] = v end
    local tree = M.new(#matrix, active)
    local distances = {}
    for _, a in ipairs(active) do distances[a] = {}; for _, b in ipairs(active) do distances[a][b] = matrix[a][b] end end
    while #active >= 4 do
        local r, totals = #active, {}
        for _, a in ipairs(active) do
            totals[a] = 0.0; for _, b in ipairs(active) do if a ~= b then totals[a] = totals[a] + distances[a][b] end end
        end
        local minimum, first, second
        for i, a in ipairs(active) do
            for j = i + 1, r do
                local b = active[j]; local q = (r - 2) * distances[a][b] - totals[a] - totals[b]
                if minimum == nil or q < minimum then minimum, first, second = q, a, b end
            end
        end
        local u = M.internal(tree)
        local d = distances[first][second]
        local li = d / 2 + (totals[first] - totals[second]) / (2 * (r - 2))
        M.connect(tree, first, u, li); M.connect(tree, second, u, d - li)
        local remaining = {}; distances[u] = {}
        for _, k in ipairs(active) do
            if k ~= first and k ~= second then
                remaining[#remaining + 1] = k
                local value = (distances[first][k] + distances[second][k] - d) / 2
                distances[u][k], distances[k][u] = value, value
            end
        end
        remaining[#remaining + 1] = u; active = remaining
    end
    local a, b, c = active[1], active[2], active[3]
    local ab, ac, bc = distances[a][b], distances[a][c], distances[b][c]
    local z = M.internal(tree)
    M.connect(tree, a, z, (ab + ac - bc) / 2); M.connect(tree, b, z, (ab + bc - ac) / 2); M.connect(tree, c, z, (ac + bc - ab) / 2)
    for _, edge in ipairs(M.edges(tree)) do if edge[3] < 0 then M.connect(tree, edge[1], edge[2], 0.0); tree.negative = tree.negative + 1 end end
    return tree
end
function M.paths(t, start, unit)
    local distances = {[start] = unit and 0 or 0.0}
    local function visit(n, parent)
        for _, c in ipairs(M.keys(t.adjacent[n])) do
            if c ~= parent then distances[c] = distances[n] + (unit and 1 or t.adjacent[n][c]); visit(c, n) end
        end
    end
    visit(start, nil); return distances
end
function M.patristic(t)
    local matrix = {}
    for i = 1, t.size do matrix[i] = {}; for j = 1, t.size do matrix[i][j] = 0.0 end end
    local taxa = M.taxa(t)
    for i, a in ipairs(taxa) do
        local distances = M.paths(t, a)
        for j = i + 1, #taxa do local b = taxa[j]; matrix[a][b], matrix[b][a] = distances[b], distances[b] end
    end
    return matrix
end
return M
