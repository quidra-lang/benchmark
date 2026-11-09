const DIRECTIONS = [(0, -1), (1, 0), (0, 1), (-1, 0)]
neighbor(cell::Cell, direction::Int) = (cell[1] + DIRECTIONS[direction][1], cell[2] + DIRECTIONS[direction][2])
struct DistanceField
    dist::Matrix{Union{Nothing,Int}}
    exit::Cell
    width::Int
    height::Int
end
function DistanceField(grid::GridMap, towers::Set{Cell})
    dist = Matrix{Union{Nothing,Int}}(undef, grid.height, grid.width)
    fill!(dist, nothing)
    dist[grid.exit[2] + 1, grid.exit[1] + 1] = 0
    queue = [grid.exit]
    head = 1
    while head <= length(queue)
        cell = queue[head]
        head += 1
        for direction in eachindex(DIRECTIONS)
            following = neighbor(cell, direction)
            if inside(grid, following) && !is_rock(grid, following) && !(following in towers) && dist[following[2] + 1, following[1] + 1] === nothing
                dist[following[2] + 1, following[1] + 1] = dist[cell[2] + 1, cell[1] + 1] + 1
                push!(queue, following)
            end
        end
    end
    DistanceField(dist, grid.exit, grid.width, grid.height)
end
distance_at(field::DistanceField, cell::Cell) = field.dist[cell[2] + 1, cell[1] + 1]
function direction_of(field::DistanceField, cell::Cell)
    best = nothing
    best_distance = 0
    for direction in eachindex(DIRECTIONS)
        following = neighbor(cell, direction)
        0 <= following[1] < field.width && 0 <= following[2] < field.height || continue
        distance = distance_at(field, following)
        if distance !== nothing && (best === nothing || distance < best_distance)
            best, best_distance = direction, distance
        end
    end
    best
end
next_cell(field::DistanceField, cell::Cell) = neighbor(cell, direction_of(field, cell))
function spawn_path(field::DistanceField, start::Cell)
    cells = [start]
    while cells[end] != field.exit
        push!(cells, next_cell(field, cells[end]))
    end
    cells
end
