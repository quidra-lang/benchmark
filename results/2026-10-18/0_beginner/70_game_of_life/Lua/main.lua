local initial = {".#......", "..#.....", "###.....", "........", "........", "........", ".....###", "........"}
local board = {}
for row = 1, 8 do
    board[row] = {}
    for column = 1, 8 do board[row][column] = initial[row]:sub(column, column) == "#" end
end
for generation = 0, 4 do
    io.write(string.format("generation %d\n", generation))
    for row = 1, 8 do
        for column = 1, 8 do io.write(board[row][column] and "#" or ".") end
        io.write("\n")
    end
    if generation == 4 then break end
    local following = {}
    for row = 1, 8 do
        following[row] = {}
        for column = 1, 8 do
            local neighbors = 0
            for dr = -1, 1 do
                for dc = -1, 1 do
                    local r, c = row + dr, column + dc
                    if (dr ~= 0 or dc ~= 0) and r >= 1 and r <= 8 and c >= 1 and c <= 8 and board[r][c] then
                        neighbors = neighbors + 1
                    end
                end
            end
            following[row][column] = neighbors == 3 or (board[row][column] and neighbors == 2)
        end
    end
    board = following
end
local alive = 0
for row = 1, 8 do
    for column = 1, 8 do
        if board[row][column] then alive = alive + 1 end
    end
end
io.write(string.format("alive: %d\n", alive))
