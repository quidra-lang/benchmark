const GRID_ACTIONS = ((0, 0, '.'), (0, -1, 'N'), (1, 0, 'E'), (0, 1, 'S'), (-1, 0, 'W'))
function read_grid()
    lines = readlines("input/map.txt")
    width, height = parse.(Int, split(lines[1], ' '))
    rows = lines[2:end]
    free = [rows[y + 1][x + 1] == '.' for y in 0:height - 1 for x in 0:width - 1]
    return (; width, height, rows, free)
end

function read_agents(grid)
    agents = NamedTuple[]
    for line in readlines("input/agents.csv")[2:end]
        id, sx, sy, gx, gy = parse.(Int, split(line, ','))
        push!(
            agents,
            (id=id, start=sy * grid.width + sx, goal=gy * grid.width + gx, name=Char(Int('A') + id))
        )
    end
    return agents
end

function destinations(grid, cell)
    x, y = cell % grid.width, cell ÷ grid.width
    result = Tuple{Int,Char}[]
    for (dx, dy, action) in GRID_ACTIONS
        nx, ny = x + dx, y + dy
        if 0 <= nx < grid.width && 0 <= ny < grid.height
            destination = ny * grid.width + nx
            grid.free[destination + 1] && push!(result, (destination, action))
        end
    end
    return result
end

grid_neighbors(grid, cell) = [destination for (
    destination,
    action
) in destinations(grid, cell) if action != '.']

function distance_table(grid, goal)
    distances = fill(-1, length(grid.free))
    distances[goal + 1] = 0
    queue, index = [goal], 1
    while index <= length(queue)
        cell = queue[index]
        index += 1
        for next_cell in grid_neighbors(grid, cell)
            if distances[next_cell + 1] == -1
                distances[next_cell + 1] = distances[cell + 1] + 1
                push!(queue, next_cell)
            end
        end
    end
    return distances
end
