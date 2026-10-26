const DIRECTION_NAMES = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const DIRECTIONS = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
function passable(level::Level, x::Int, y::Int)
    0 <= x < level.width && 0 <= y < level.height && level.terrain[y + 1, x + 1] in ('.', '#', '+', '<', '>')
end
function can_move(level::Level, x::Int, y::Int, dx::Int, dy::Int)
    passable(level, x + dx, y + dy) && (dx == 0 || dy == 0 || (level.terrain[y + 1, x + 1] != '+' && level.terrain[y + dy + 1, x + dx + 1] != '+'))
end
function line_cells(x0::Int, y0::Int, x1::Int, y1::Int)
    dx = abs(x1 - x0)
    dy = abs(y1 - y0)
    sx = x1 > x0 ? 1 : -1
    sy = y1 > y0 ? 1 : -1
    error = dx - dy
    x, y = x0, y0
    cells = Cell[]
    while x != x1 || y != y1
        twice = 2 * error
        if twice > -dy
            error -= dy
            x += sx
        end
        if twice < dx
            error += dx
            y += sy
        end
        push!(cells, Cell(x, y))
    end
    cells
end
function field_of_view(level::Level, px::Int, py::Int, radius::Int)
    visible = falses(level.height, level.width)
    for y in max(0, py - radius):min(level.height - 1, py + radius), x in max(0, px - radius):min(level.width - 1, px + radius)
        (x - px)^2 + (y - py)^2 > radius^2 && continue
        cells = line_cells(px, py, x, y)
        if all(point -> passable(level, point.x, point.y), cells[1:max(0, length(cells) - 1)])
            visible[y + 1, x + 1] = true
        end
    end
    visible
end
function distances(level::Level, px::Int, py::Int)
    distance = fill(-1, level.height, level.width)
    distance[py + 1, px + 1] = 0
    queue = [Cell(px, py)]
    head = 1
    while head <= length(queue)
        point = queue[head]
        head += 1
        for (dx, dy) in DIRECTIONS
            x, y = point.x + dx, point.y + dy
            if can_move(level, point.x, point.y, dx, dy) && distance[y + 1, x + 1] == -1
                distance[y + 1, x + 1] = distance[point.y + 1, point.x + 1] + 1
                push!(queue, Cell(x, y))
            end
        end
    end
    distance
end
