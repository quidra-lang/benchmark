local board = require('board')
local scoring = require('scoring')
local M = {LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'}
local function cell_key(row, column) return (row - 1) * 15 + column end
function M.anchors(position)
    if #board.tiles(position) == 0 then return {{8, 8}} end
    local result = {}
    for r = 1, 15 do
        for c = 1, 15 do
            if position[r][c] == '.' then
                for _, neighbor in ipairs(board.neighbors(r, c)) do if position[neighbor[1]][neighbor[2]] ~= '.' then result[#result + 1] = {r, c}; break end end
            end
        end
    end
    return result
end
function M.cross_checks(position, trie)
    local result = {}
    for r = 1, 15 do
        for c = 1, 15 do
            if position[r][c] == '.' then
                local first, last = r, r
                while first > 1 and position[first - 1][c] ~= '.' do first = first - 1 end
                while last < 15 and position[last + 1][c] ~= '.' do last = last + 1 end
                if first ~= last then
                    local prefix, suffix = {}, {}
                    for row = first, r - 1 do prefix[#prefix + 1] = position[row][c] end
                    for row = r + 1, last do suffix[#suffix + 1] = position[row][c] end
                    local before, after, allowed = table.concat(prefix):upper(), table.concat(suffix):upper(), {}
                    for i = 1, 26 do local letter = M.LETTERS:sub(i, i); if trie:contains(before .. letter .. after) then allowed[letter] = true end end
                    result[cell_key(r, c)] = allowed
                end
            end
        end
    end
    return result
end
function M.across_moves(position, rack, trie, anchors, checks)
    local result, counts, anchor_set = {}, {}, {}
    for i = 1, #rack do local letter = rack:sub(i, i); counts[letter] = (counts[letter] or 0) + 1 end
    for _, anchor in ipairs(anchors) do anchor_set[cell_key(anchor[1], anchor[2])] = true end
    for _, square in ipairs(anchors) do
        local row, anchor = square[1], square[2]
        local function extend(node, column, word, start)
            local empty = column == 16 or position[row][column] == '.'
            if empty and column > anchor and node.terminal then result[#result + 1] = {row = row, column = start, direction = 0, word = word} end
            if column == 16 then return end
            if not empty then
                local letter = position[row][column]
                local child = node.children[letter:upper()]
                if child then extend(child, column + 1, word .. letter, start) end
                return
            end
            local allowed = checks[cell_key(row, column)]
            for i = 1, 26 do
                local letter = M.LETTERS:sub(i, i)
                local child = node.children[letter]
                if child and (not allowed or allowed[letter]) then
                    for _, option in ipairs({{letter, letter}, {'?', letter:lower()}}) do
                        local tile, written = option[1], option[2]
                        if (counts[tile] or 0) > 0 then counts[tile] = counts[tile] - 1; extend(child, column + 1, word .. written, start); counts[tile] = counts[tile] + 1 end
                    end
                end
            end
        end
        local function left_part(node, prefix, remaining)
            extend(node, anchor, prefix, anchor - #prefix)
            if remaining == 0 then return end
            for i = 1, 26 do
                local letter = M.LETTERS:sub(i, i)
                local child = node.children[letter]
                if child then
                    for _, option in ipairs({{letter, letter}, {'?', letter:lower()}}) do
                        local tile, written = option[1], option[2]
                        if (counts[tile] or 0) > 0 then counts[tile] = counts[tile] - 1; left_part(child, prefix .. written, remaining - 1); counts[tile] = counts[tile] + 1 end
                    end
                end
            end
        end
        if anchor > 1 and position[row][anchor - 1] ~= '.' then
            local first = anchor - 1
            while first > 1 and position[row][first - 1] ~= '.' do first = first - 1 end
            local letters = {}
            for c = first, anchor - 1 do letters[#letters + 1] = position[row][c] end
            local prefix = table.concat(letters)
            local node = trie:prefix(prefix:upper())
            if node then extend(node, anchor, prefix, first) end
        else
            local first = anchor - 1
            while first >= 1 and position[row][first] == '.' and not anchor_set[cell_key(row, first)] do first = first - 1 end
            left_part(trie.root, '', anchor - first - 1)
        end
    end
    return result
end
function M.placement_key(tiles)
    local parts = {}
    for _, tile in ipairs(tiles) do parts[#parts + 1] = {tile[1], tile[2], tile[3]} end
    table.sort(parts, function(a, b) return a[1] < b[1] or a[1] == b[1] and (a[2] < b[2] or a[2] == b[2] and a[3] < b[3]) end)
    local result = {}
    for _, tile in ipairs(parts) do result[#result + 1] = tile[1] .. ':' .. tile[2] .. ':' .. tile[3] end
    return table.concat(result, ';')
end
function M.generate(position, rack, trie)
    local anchors = M.anchors(position)
    local moves = M.across_moves(position, rack, trie, anchors, M.cross_checks(position, trie))
    local transposed, swapped = board.transpose(position), {}
    for _, anchor in ipairs(anchors) do swapped[#swapped + 1] = {anchor[2], anchor[1]} end
    table.sort(swapped, function(a, b) return a[1] < b[1] or a[1] == b[1] and a[2] < b[2] end)
    for _, move in ipairs(M.across_moves(transposed, rack, trie, swapped, M.cross_checks(transposed, trie))) do moves[#moves + 1] = {row = move.column, column = move.row, direction = 1, word = move.word} end
    local unique, result = {}, {}
    for _, move in ipairs(moves) do
        local tiles, keep = scoring.placement(position, move), true
        if #tiles == 1 and move.direction == 1 then
            local tile = tiles[1]
            if #board.run_at(scoring.apply(position, tiles), tile[1], tile[2], 0).word >= 2 then keep = false end
        end
        if keep then
            local key = M.placement_key(tiles)
            if not unique[key] then unique[key] = true; result[#result + 1] = move end
        end
    end
    return result
end
return M
