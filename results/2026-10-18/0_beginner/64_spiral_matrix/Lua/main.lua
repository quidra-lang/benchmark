local matrix = {}
for row = 1,5 do
    matrix[row] = {}
    for column = 1,6 do matrix[row][column] = 0 end
end
local directions = {{0,1},{1,0},{0,-1},{-1,0}}
local row,column,direction = 1,1,1
for value = 1,30 do
    matrix[row][column] = value
    if value == 30 then break end
    local dr,dc = table.unpack(directions[direction])
    local r,c = row+dr,column+dc
    if r < 1 or r > 5 or c < 1 or c > 6 or matrix[r][c] ~= 0 then
        direction = direction%4+1
        dr,dc = table.unpack(directions[direction])
    end
    row,column = row+dr,column+dc
end
for _, values in ipairs(matrix) do
    for _, value in ipairs(values) do io.write(string.format("%3d",value)) end
    io.write("\n")
end
