local Grid = {}
local actions = {{0, 0}, {0, -1}, {1, 0}, {0, 1}, {-1, 0}}

function Grid.words(line)
    local values = {}
    for word in line:gmatch("%S+") do values[#values + 1] = word end
    return values
end

function Grid.xy(cell)
    return (cell - 1) % Grid.width, (cell - 1) // Grid.width
end

function Grid.read()
    local file = assert(io.open("input/map.txt", "r"))
    local dimensions = Grid.words(file:read("l"))
    local width, height = tonumber(dimensions[1]), tonumber(dimensions[2])
    Grid.width, Grid.area = width, width * height + 1
    local grid = {width = width, height = height, rows = {}, free = {}, cells = {}, destinations = {}, neighbors = {}}
    for y = 0, height - 1 do
        local row = file:read("l")
        grid.rows[y + 1] = row
        for x = 0, width - 1 do
            if row:sub(x + 1, x + 1) == "." then
                local cell = y * width + x + 1
                grid.free[cell] = true
                grid.cells[#grid.cells + 1] = cell
            end
        end
    end
    file:close()
    for _, cell in ipairs(grid.cells) do
        local x, y = Grid.xy(cell)
        local destinations, neighbors = {}, {}
        for index, delta in ipairs(actions) do
            local nx, ny = x + delta[1], y + delta[2]
            local next_cell = ny * width + nx + 1
            if nx >= 0 and nx < width and ny >= 0 and ny < height and grid.free[next_cell] then
                destinations[#destinations + 1] = next_cell
                if index > 1 then neighbors[#neighbors + 1] = next_cell end
            end
        end
        grid.destinations[cell], grid.neighbors[cell] = destinations, neighbors
    end
    return grid
end

function Grid.agents()
    local agents = {}
    local file = assert(io.open("input/agents.csv", "r"))
    file:read("l")
    for line in file:lines() do
        local fields = {}
        for value in line:gmatch("%d+") do fields[#fields + 1] = tonumber(value) end
        agents[#agents + 1] = {id = fields[1], name = string.char(65 + fields[1]),
            start = fields[3] * Grid.width + fields[2] + 1,
            goal = fields[5] * Grid.width + fields[4] + 1}
    end
    file:close()
    return agents
end

function Grid.distance(grid, goal)
    local distances, queue, head = {[goal] = 0}, {goal}, 1
    while head <= #queue do
        local cell = queue[head]
        head = head + 1
        for _, neighbor in ipairs(grid.neighbors[cell]) do
            if distances[neighbor] == nil then
                distances[neighbor] = distances[cell] + 1
                queue[#queue + 1] = neighbor
            end
        end
    end
    return distances
end

function Grid.statistics(grid)
    local result = {isolated = 0, dead_ends = 0, corridors = 0, junctions = 0, components = 0}
    local names, seen = {"isolated", "dead_ends", "corridors", "junctions"}, {}
    for _, cell in ipairs(grid.cells) do
        local name = names[math.min(#grid.neighbors[cell], 3) + 1]
        result[name] = result[name] + 1
        if not seen[cell] then
            result.components = result.components + 1
            local queue, head = {cell}, 1
            seen[cell] = true
            while head <= #queue do
                local current = queue[head]
                head = head + 1
                for _, other in ipairs(grid.neighbors[current]) do
                    if not seen[other] then seen[other] = true; queue[#queue + 1] = other end
                end
            end
        end
    end
    return result
end

return Grid
