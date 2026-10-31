cell_text(cell, grid) = "$(cell % grid.width),$(cell ÷ grid.width)"
agent_name(number) = string(Char(Int('A') + number - 1))
function action_string(path, grid)
    result = Char[]
    for index in 2:length(path)
        source, destination = path[index - 1], path[index]
        dx, dy = destination % grid.width - source % grid.width, destination ÷ grid.width - source ÷ grid.width
        push!(result, first(action for (x, y, action) in GRID_ACTIONS if (x, y) == (dx, dy)))
    end
    return join(result)
end
function conflict_text(conflict, grid)
    beginning = "$(conflict.kind) t $(conflict.time) $(agent_name(conflict.a)) $(agent_name(conflict.b))"
    conflict.kind == "vertex" && return beginning * " at " * cell_text(conflict.u, grid)
    return beginning * " from $(cell_text(conflict.u, grid)) to $(cell_text(conflict.v, grid))"
end
function reduced_fraction(numerator, denominator)
    divisor = gcd(numerator, denominator)
    return "$(numerator ÷ divisor)/$(denominator ÷ divisor)"
end
csv_line(values) = join(values, ",")
function save_file(name, lines)
    mkpath("output")
    write(joinpath("output", name), join(lines, "\n") * "\n")
end
function grid_picture(grid, placements)
    return [join(get(
        placements,
        y * grid.width + x,
        grid.rows[y + 1][x + 1]
    ) for x in 0:grid.width - 1) for y in 0:grid.height - 1]
end
