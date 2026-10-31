local function outcome(board)
    local lines = {board[1], board[2], board[3]}
    for column = 1, 3 do
        lines[#lines + 1] = board[1]:sub(column, column) .. board[2]:sub(column, column) .. board[3]:sub(column, column)
    end
    lines[#lines + 1] = board[1]:sub(1, 1) .. board[2]:sub(2, 2) .. board[3]:sub(3, 3)
    lines[#lines + 1] = board[1]:sub(3, 3) .. board[2]:sub(2, 2) .. board[3]:sub(1, 1)
    for _, line in ipairs(lines) do
        local first = line:sub(1, 1)
        if first ~= "." and line == string.rep(first, 3) then return first .. " wins" end
    end
    return table.concat(board):find(".", 1, true) and "in progress" or "draw"
end

local boards = {
    {"XXX", "OO.", "O.X"}, {"X.O", ".X.", "O.."}, {"XO.", ".OX", "XO."}, {"XOX", "XOO", "OXX"},
    {"X.O", "XO.", "O.X"}, {"XOX", "OXO", "OXX"},
}
for number, board in ipairs(boards) do io.write(string.format("board %d: %s\n", number, outcome(board))) end
