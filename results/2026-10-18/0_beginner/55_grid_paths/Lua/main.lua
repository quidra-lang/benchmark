local grid = {".......", "..#....", "....#..", ".#.....", "...#.#.", "......."}

local function count_paths(obstacles)
    local paths = {}
    for row = 1, #grid do
        paths[row] = {}
        for column = 1, #grid[1] do
            if obstacles and grid[row]:sub(column, column) == "#" then
                paths[row][column] = 0
            elseif row == 1 and column == 1 then
                paths[row][column] = 1
            else
                paths[row][column] = (row > 1 and paths[row - 1][column] or 0)
                    + (column > 1 and paths[row][column - 1] or 0)
            end
        end
    end
    return paths[#grid][#grid[1]]
end

io.write(string.format("without obstacles: %d\nwith obstacles: %d\n", count_paths(false), count_paths(true)))
