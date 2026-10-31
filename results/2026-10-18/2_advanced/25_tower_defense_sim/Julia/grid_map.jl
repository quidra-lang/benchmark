const Cell = NTuple{2,Int}
const Point = NTuple{2,Int}
cell_center(cell::Cell) = (100 * cell[1], 100 * cell[2])
struct GridMap
    width::Int
    height::Int
    rows::Vector{Vector{UInt8}}
    exit::Cell
    spawns::Vector{Cell}
end
function read_map(path::String)
    lines = readlines(path)
    width, height = parse.(Int, split(lines[1], ' '))
    rows = [collect(codeunits(line)) for line in lines[2:height+1]]
    exit = (0, 0)
    found = Dict{Int,Cell}()
    for y in 0:height-1, x in 0:width-1
        terrain = rows[y + 1][x + 1]
        if UInt8('1') <= terrain <= UInt8('9')
            found[Int(terrain - UInt8('0'))] = (x, y)
        elseif terrain == UInt8('E')
            exit = (x, y)
        end
    end
    GridMap(width, height, rows, exit, [found[number] for number in sort!(collect(keys(found)))])
end
inside(grid::GridMap, cell::Cell) = 0 <= cell[1] < grid.width && 0 <= cell[2] < grid.height
terrain(grid::GridMap, cell::Cell) = grid.rows[cell[2] + 1][cell[1] + 1]
is_rock(grid::GridMap, cell::Cell) = terrain(grid, cell) == UInt8('#')
is_water(grid::GridMap, cell::Cell) = terrain(grid, cell) == UInt8('~')
buildable(grid::GridMap, cell::Cell) = terrain(grid, cell) == UInt8('.')
