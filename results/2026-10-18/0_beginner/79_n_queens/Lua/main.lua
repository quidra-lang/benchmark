local function solve_queens(n)
    local columns, first, solutions = {}, {}, 0
    local function place(row)
        if row == n then
            solutions = solutions + 1
            if #first == 0 then
                first = {table.unpack(columns)}
            end
            return
        end
        for column = 0, n - 1 do
            local valid = true
            for previous = 0, row - 1 do
                if columns[previous + 1] == column or math.abs(columns[previous + 1] - column) == row - previous then
                    valid = false
                    break
                end
            end
            if valid then
                columns[row + 1] = column
                place(row + 1)
            end
        end
    end
    place(0)
    return solutions, first
end

local first_eight
for n = 4, 8 do
    local solutions, first = solve_queens(n)
    io.write(string.format("N=%d: %d solutions\n", n, solutions))
    if n == 8 then first_eight = first end
end
for _, column in ipairs(first_eight) do io.write(string.rep(".", column), "Q", string.rep(".", 7 - column), "\n") end
