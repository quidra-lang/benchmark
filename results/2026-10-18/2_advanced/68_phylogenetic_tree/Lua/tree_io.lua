local tree = require('tree_building')
local M = {}
function M.real(value, places)
    local text = string.format('%.' .. places .. 'f', value)
    if text:sub(1, 1) == '-' and tonumber(text) == 0 then text = text:sub(2) end
    return text
end
function M.symbols(mask, count)
    local chars = {}; for i = 1, count do chars[i] = mask & (1 << (i - 1)) ~= 0 and '*' or '.' end
    return table.concat(chars)
end
function M.children(r, names)
    local minimum, children = {}, {}
    for i = #r.order, 1, -1 do
        local n = r.order[i]; children[n] = {}
        if n <= r.tree.size then minimum[n] = names[n] else
            for j, c in ipairs(r.children[n]) do children[n][j] = c end
            table.sort(children[n], function(a, b) return minimum[a] < minimum[b] end)
            minimum[n] = minimum[children[n][1]]
        end
    end
    return children
end
function M.newick(t, names, outgroup, lengths, support)
    local r = tree.rooted(t, outgroup); local children = M.children(r, names)
    local function render(n)
        local text
        if n <= t.size then text = names[n] else
            local parts = {}; for i, c in ipairs(children[n]) do parts[i] = render(c) end
            text = '(' .. table.concat(parts, ',') .. ')'
            if support and n ~= r.root then text = text .. (support[r.masks[n]] or 0) end
        end
        if lengths and n ~= r.root then text = text .. ':' .. M.real(t.adjacent[n][r.parents[n]], 5) end
        return text
    end
    return render(r.root) .. ';'
end
function M.cladogram(t, names, outgroup, support)
    local r = tree.rooted(t, outgroup); local children = M.children(r, names)
    local out = {'*'}
    local function descend(n, prefix)
        for i, c in ipairs(children[n]) do
            local last = i == #children[n]
            local label = c <= t.size and names[c] or ('[' .. (support[r.masks[c]] or 0) .. ']')
            out[#out + 1] = prefix .. (last and '`-- ' or '|-- ') .. label
            descend(c, prefix .. (last and '    ' or '|   '))
        end
    end
    descend(r.root, ''); return out
end
function M.write(name, lines)
    local file = assert(io.open('output/' .. name, 'w'))
    file:write(table.concat(lines, '\n'), '\n'); file:close()
end
return M
