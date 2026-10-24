local puzzle = {"800025000","070080005","260400070","000001900","010000040","600200000","900010000","700000004","020000036"}
local board,placements = {},0
for row = 1,9 do
    board[row] = {}
    for column = 1,9 do board[row][column] = tonumber(puzzle[row]:sub(column,column)) end
end
local function valid(row,column,digit)
    for i = 1,9 do
        if board[row][i] == digit or board[i][column] == digit then return false end
    end
    local block_row,block_column = ((row-1)//3)*3+1,((column-1)//3)*3+1
    for r = block_row,block_row+2 do
        for c = block_column,block_column+2 do
            if board[r][c] == digit then return false end
        end
    end
    return true
end
local function solve()
    for row = 1,9 do
        for column = 1,9 do
            if board[row][column] == 0 then
                for digit = 1,9 do
                    if valid(row,column,digit) then
                        board[row][column] = digit
                        placements = placements+1
                        if solve() then return true end
                        board[row][column] = 0
                    end
                end
                return false
            end
        end
    end
    return true
end
solve()
for _,row in ipairs(board) do io.write(table.concat(row," "),"\n") end
io.write(string.format("placements: %d\n",placements))
