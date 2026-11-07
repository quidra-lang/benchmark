local M = {SIZE = 15, CENTER = 8, COLUMNS = 'ABCDEFGHIJKLMNO'}
local premium_rows = {'#..+...#...+..#', '.*...^...^...*.', '..*...+.+...*..', '+..*...+...*..+', '....*.....*....', '.^...^...^...^.', '..+...+.+...+..', '#..+...*...+..#', '..+...+.+...+..', '.^...^...^...^.', '....*.....*....', '+..*...+...*..+', '..*...+.+...*..', '.*...^...^...*.', '#..+...#...+..#'}
M.PREMIUMS = {}
for r, row in ipairs(premium_rows) do M.PREMIUMS[r] = {}; for c = 1, 15 do M.PREMIUMS[r][c] = row:sub(c, c) end end
function M.inside(row, column) return row >= 1 and row <= 15 and column >= 1 and column <= 15 end
function M.square_name(row, column) return M.COLUMNS:sub(column, column) .. row end
function M.position(move)
    local column = M.COLUMNS:sub(move.column, move.column)
    return move.direction == 0 and move.row .. column or column .. move.row
end
function M.parse_position(text)
    local row, column = text:match('^([1-9]%d?)([A-O])$')
    if row and tonumber(row) <= 15 then return tonumber(row), column:byte() - 64, 0 end
    column, row = text:match('^([A-O])([1-9]%d?)$')
    if row and tonumber(row) <= 15 then return tonumber(row), column:byte() - 64, 1 end
    return nil
end
function M.empty()
    local result = {}
    for r = 1, 15 do result[r] = {}; for c = 1, 15 do result[r][c] = '.' end end
    return result
end
function M.transpose(board)
    local result = M.empty()
    for r = 1, 15 do for c = 1, 15 do result[r][c] = board[c][r] end end
    return result
end
function M.tiles(board)
    local result = {}
    for r = 1, 15 do for c = 1, 15 do if board[r][c] ~= '.' then result[#result + 1] = {r, c, board[r][c]} end end end
    return result
end
function M.neighbors(row, column)
    local result = {}
    for _, cell in ipairs({{row - 1, column}, {row + 1, column}, {row, column - 1}, {row, column + 1}}) do if M.inside(cell[1], cell[2]) then result[#result + 1] = cell end end
    return result
end
function M.run_at(board, row, column, direction)
    local dr, dc = direction, 1 - direction
    while M.inside(row - dr, column - dc) and board[row - dr][column - dc] ~= '.' do row, column = row - dr, column - dc end
    local first_row, first_column, letters = row, column, {}
    while M.inside(row, column) and board[row][column] ~= '.' do letters[#letters + 1] = board[row][column]; row, column = row + dr, column + dc end
    return {row = first_row, column = first_column, direction = direction, word = table.concat(letters)}
end
function M.words(board)
    local result = {}
    for direction = 0, 1 do
        for line = 1, 15 do
            local offset = 1
            while offset <= 15 do
                local row, column = direction == 0 and line or offset, direction == 0 and offset or line
                if board[row][column] == '.' then offset = offset + 1
                else
                    local word = M.run_at(board, row, column, direction)
                    if #word.word >= 2 then result[#result + 1] = word end
                    offset = offset + #word.word
                end
            end
        end
    end
    return result
end
function M.connected(board)
    local tiles = M.tiles(board)
    if #tiles == 0 then return true end
    local occupied, seen, pending, count = {}, {}, {{tiles[1][1], tiles[1][2]}}, 1
    for _, tile in ipairs(tiles) do occupied[(tile[1] - 1) * 15 + tile[2]] = true end
    seen[(tiles[1][1] - 1) * 15 + tiles[1][2]] = true
    while #pending > 0 do
        local cell = table.remove(pending)
        for _, neighbor in ipairs(M.neighbors(cell[1], cell[2])) do
            local key = (neighbor[1] - 1) * 15 + neighbor[2]
            if occupied[key] and not seen[key] then seen[key] = true; count = count + 1; pending[#pending + 1] = neighbor end
        end
    end
    return count == #tiles
end
function M.display(board)
    local columns, result = {}, {}
    for c = 1, 15 do columns[c] = M.COLUMNS:sub(c, c) end
    result[1] = '   ' .. table.concat(columns, ' ')
    for r = 1, 15 do
        local letters = {}
        for c = 1, 15 do letters[c] = board[r][c] == '.' and M.PREMIUMS[r][c] or board[r][c] end
        result[#result + 1] = string.format('%2d ', r) .. table.concat(letters, ' ')
    end
    return result
end
return M
