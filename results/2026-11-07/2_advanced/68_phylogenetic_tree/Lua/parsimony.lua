local tree = require('tree_building')
local M = {}
function M.merge(a, b)
    local common = a & b
    if common ~= 0 then return common, 0 end
    return a | b, 1
end
function M.provisional(r, pattern)
    local sets, changes = {}, 0
    for i = #r.order, 1, -1 do
        local n = r.order[i]
        if n <= r.tree.size then sets[n] = pattern[n] else
            local children = {}; for _, c in ipairs(r.children[n]) do if c ~= r.outgroup then children[#children + 1] = c end end
            local merged, added = M.merge(sets[children[1]], sets[children[2]])
            sets[n] = merged; changes = changes + added
            if n == r.root then local _, extra = M.merge(sets[n], sets[r.outgroup]); changes = changes + extra end
        end
    end
    return sets, changes
end
function M.pattern_scores(t, patterns, outgroup)
    local r, out = tree.rooted(t, outgroup), {}
    for i, pattern in ipairs(patterns.encoded) do local _, changes = M.provisional(r, pattern); out[i] = changes end
    return out
end
function M.score(t, patterns, outgroup)
    local scores, total = M.pattern_scores(t, patterns, outgroup), 0
    for i, n in ipairs(scores) do total = total + n * patterns.weights[i] end
    return total
end
function M.edge_key(a, b) if a > b then a, b = b, a end; return a .. ':' .. b end
function M.reconstruct(t, patterns, outgroup)
    local r = tree.rooted(t, outgroup)
    local ancestors, branch_changes, scores = {}, {}, {}
    for _, n in ipairs(tree.internals(t)) do ancestors[n] = {} end
    local edges = tree.edges(t)
    for _, edge in ipairs(edges) do branch_changes[M.edge_key(edge[1], edge[2])] = 0 end
    local letters = {[1] = 'A', [2] = 'C', [4] = 'G', [8] = 'T'}
    for index, pattern in ipairs(patterns.encoded) do
        local sets, changes = M.provisional(r, pattern); scores[index] = changes
        local combined = M.merge(sets[r.root], sets[outgroup])
        local first, states = combined & -combined, {}
        for _, n in ipairs({r.root, outgroup}) do states[n] = sets[n] & first ~= 0 and first or (sets[n] & -sets[n]) end
        for i = 2, #r.order do
            local n = r.order[i]
            if n ~= outgroup then
                local parent_state = states[r.parents[n]]
                states[n] = sets[n] & parent_state ~= 0 and parent_state or (sets[n] & -sets[n])
            end
        end
        for n, values in pairs(ancestors) do values[index] = letters[states[n]] end
        for _, edge in ipairs(edges) do
            if states[edge[1]] ~= states[edge[2]] then
                local key = M.edge_key(edge[1], edge[2]); branch_changes[key] = branch_changes[key] + patterns.weights[index]
            end
        end
    end
    local sequences, site_changes = {}, {}
    for n, values in pairs(ancestors) do
        local chars = {}; for col, index in ipairs(patterns.columns) do chars[col] = values[index] end; sequences[n] = table.concat(chars)
    end
    for col, index in ipairs(patterns.columns) do site_changes[col] = scores[index] end
    return sequences, branch_changes, site_changes
end
function M.branches(t, outgroup)
    local r, out = tree.rooted(t, outgroup), {}
    for i = 2, #r.order do
        local n = r.order[i]
        out[#out + 1] = {mask = n == outgroup and r.ingroup or r.masks[n], first = r.parents[n], second = n}
    end
    table.sort(out, function(a, b) return a.mask < b.mask end)
    return out
end
function M.insert(t, a, b, taxon)
    local result = tree.copy(t); tree.disconnect(result, a, b)
    local n = tree.internal(result); result.adjacent[taxon] = {}
    tree.connect(result, a, n); tree.connect(result, b, n); tree.connect(result, taxon, n)
    return result
end
function M.nni(t, outgroup)
    local r, out = tree.rooted(t, outgroup), {}
    for _, branch in ipairs(M.branches(t, outgroup)) do
        local a, b = branch.first, branch.second
        if a > t.size and b > t.size then
            local sibling
            for _, c in ipairs(r.children[a]) do if c ~= b and c ~= outgroup then sibling = c; break end end
            local children = {}; for i, c in ipairs(r.children[b]) do children[i] = c end
            table.sort(children, function(x, y) return r.masks[x] < r.masks[y] end)
            for swap, c in ipairs(children) do
                local result = tree.copy(t)
                local sl, cl = tree.disconnect(result, a, sibling), tree.disconnect(result, b, c)
                tree.connect(result, a, c, cl); tree.connect(result, b, sibling, sl)
                out[#out + 1] = {mask = branch.mask, swap = swap, tree = result}
            end
        end
    end
    return out
end
return M
