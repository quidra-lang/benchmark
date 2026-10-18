local board = {}
for r = 0,10 do
    board[r] = {}
    for c = 0,10 do board[r][c] = false end
end
local row,column,direction = 5,5,0
local directions = {{-1,0},{0,1},{1,0},{0,-1}}
for step = 1,300 do
    direction = (direction+(board[row][column] and -1 or 1))%4
    board[row][column] = not board[row][column]
    row = (row+directions[direction+1][1])%11
    column = (column+directions[direction+1][2])%11
end
local black = 0
for r = 0,10 do
    for c = 0,10 do
        if board[r][c] then black = black+1 end
        io.write(r == row and c == column and "A" or board[r][c] and "#" or ".")
    end
    io.write("\n")
end
io.write(string.format("black: %d\n",black))
