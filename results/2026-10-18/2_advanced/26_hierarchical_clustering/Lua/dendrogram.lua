local M = {}

function M.children(merges, count)
    local minimum, children = {}, {}
    for i = 1, count do minimum[i] = i - 1 end
    for step, merge in ipairs(merges) do
        local a, b = merge.a, merge.b
        children[step] = minimum[a + 1] < minimum[b + 1] and {a, b} or {b, a}
        minimum[count + step] = math.min(minimum[a + 1], minimum[b + 1])
    end
    return children
end

function M.order(children, count)
    local order, pending = {}, {count + #children - 1}
    while #pending > 0 do
        local node = table.remove(pending)
        if node < count then order[#order + 1] = node + 1
        else
            local pair = children[node - count + 1]
            pending[#pending + 1], pending[#pending + 2] = pair[2], pair[1]
        end
    end
    return order
end

function M.column(height, maximum, width)
    local position = height / maximum * width
    if position >= width + 1 then return width + 1 end
    return math.floor(position)
end

function M.rows(tree, idents, labels, maximum, cuts, width)
    local n, grid, anchor, columns = tree.count, {}, {}, {}
    for row, leaf in ipairs(tree.order) do
        grid[row], anchor[leaf] = {}, row
        for x = 1, width + 1 do grid[row][x] = 0 end
    end
    local function mark(row, x, level) grid[row][x + 1] = math.max(grid[row][x + 1], level) end
    for _, x in ipairs(cuts) do if x <= width then for row = 1, n do mark(row, x, 1) end end end
    for step, merge in ipairs(tree.merges) do columns[step] = M.column(merge.height, maximum, width) end
    for step, pair in ipairs(tree.children) do
        local upper, lower, x = pair[1] + 1, pair[2] + 1, columns[step]
        mark(anchor[upper], x, 4)
        mark(anchor[lower], x, 4)
        for row = anchor[upper] + 1, anchor[lower] - 1 do mark(row, x, 3) end
        for _, child in ipairs({upper, lower}) do
            local start = child <= n and 0 or columns[child - n] + 1
            for position = start, x - 1 do mark(anchor[child], position, 2) end
        end
        anchor[n + step] = (anchor[upper] + anchor[lower]) // 2
    end
    local iw, lw, rows = 0, 0, {}
    for i = 1, n do iw, lw = math.max(iw, #idents[i]), math.max(lw, #labels[i]) end
    local marks = " :-|+"
    for row, leaf in ipairs(tree.order) do
        local cells = {}
        for _, level in ipairs(grid[row]) do cells[#cells + 1] = marks:sub(level + 1, level + 1) end
        rows[#rows + 1] = (idents[leaf] .. string.rep(" ", iw - #idents[leaf]) .. " " .. labels[leaf] .. string.rep(" ", lw - #labels[leaf]) .. " " .. table.concat(cells)):gsub(" +$", "")
    end
    local scale = {}
    for x = 0, width do scale[#scale + 1] = x % 10 == 0 and "+" or "-" end
    rows[#rows + 1] = string.rep(" ", iw + lw + 2) .. table.concat(scale)
    return rows
end

return M
