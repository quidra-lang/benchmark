local text = {
    "#############",
    "#S..#.......#",
    "#.#.#.###.#.#",
    "#.#...#...#.#",
    "#.###.#.###.#",
    "#...#...#...#",
    "###.#####.#.#",
    "#.......#..G#",
    "#############",
}
local maze, start, goal = {}, nil, nil
for row, line in ipairs(text) do
    maze[row] = {}
    for column = 1, #line do
        local c = line:sub(column, column)
        maze[row][column] = c
        if c == "S" then
            start = {row, column}
        elseif c == "G" then
            goal = {row, column}
        end
    end
end

local function key(row, column) return row .. "," .. column end

local queue, parents, head = {start}, {}, 1
parents[key(table.unpack(start))] = start
while head <= #queue do
    local cell = queue[head]
    head = head + 1
    if cell[1] == goal[1] and cell[2] == goal[2] then break end
    for _, direction in ipairs({{-1, 0}, {1, 0}, {0, -1}, {0, 1}}) do
        local r, c = cell[1] + direction[1], cell[2] + direction[2]
        local position = key(r, c)
        if r >= 1 and r <= 9 and c >= 1 and c <= 13 and maze[r][c] ~= "#" and not parents[position] then
            parents[position] = cell
            queue[#queue + 1] = {r, c}
        end
    end
end
local cell, steps = goal, 0
while cell[1] ~= start[1] or cell[2] ~= start[2] do
    local r, c = table.unpack(cell)
    if maze[r][c] == "." then maze[r][c] = "*" end
    cell = parents[key(r, c)]
    steps = steps + 1
end
io.write(string.format("steps: %d\n", steps))
for _, row in ipairs(maze) do io.write(table.concat(row), "\n") end
