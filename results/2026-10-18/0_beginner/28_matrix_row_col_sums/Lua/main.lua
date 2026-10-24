local matrix = {{125,340,78,912,456},{603,27,819,150,384},{0,765,231,498,62},{947,113,586,39,720}}
local columns, total = {0,0,0,0,0}, 0
for _, row in ipairs(matrix) do
    local row_sum = 0
    for j, value in ipairs(row) do
        row_sum = row_sum + value
        columns[j] = columns[j] + value
        io.write(string.format("%6d", value))
    end
    total = total + row_sum
    io.write(string.format("%6d\n", row_sum))
end
for _, value in ipairs(columns) do io.write(string.format("%6d", value)) end
io.write(string.format("%6d\n", total))
