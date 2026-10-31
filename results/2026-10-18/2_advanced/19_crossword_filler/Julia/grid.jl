struct Grid
    width::Int
    height::Int
    cells::Vector{Char}
end
Grid(rows) = Grid(length(rows[1]), length(rows), collect(join(rows)))
cell(grid, row, column) = (row - 1) * grid.width + column
location(grid, index) = "$(div(index - 1, grid.width) + 1),$(mod(index - 1, grid.width) + 1)"
is_open(grid, row, column) = 1 <= row <= grid.height && 1 <= column <= grid.width && grid.cells[cell(grid, row, column)] != '#'
white_cells(grid) = [index for index in eachindex(grid.cells) if grid.cells[index] != '#']

function asymmetric_cell(grid, symmetry)
    for row in 1:grid.height, column in 1:grid.width
        other_row = symmetry == "rot180" ? grid.height + 1 - row : row
        is_open(grid, row, column) != is_open(grid, other_row, grid.width + 1 - column) && return cell(grid, row, column)
    end
    nothing
end

function component_count(grid)
    seen = falses(length(grid.cells))
    amount = 0
    for start in white_cells(grid)
        seen[start] && continue
        amount += 1
        seen[start] = true
        stack = [start]
        while !isempty(stack)
            index = pop!(stack)
            row, column = div(index - 1, grid.width) + 1, mod(index - 1, grid.width) + 1
            for (dr, dc) in [(-1, 0), (1, 0), (0, -1), (0, 1)]
                r, c = row + dr, column + dc
                if is_open(grid, r, c)
                    neighbor = cell(grid, r, c)
                    if !seen[neighbor]
                        seen[neighbor] = true
                        push!(stack, neighbor)
                    end
                end
            end
        end
    end
    amount
end
