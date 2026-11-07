struct Cell
    x::Int
    y::Int
end
struct Room
    x::Int
    y::Int
    width::Int
    height::Int
end
center(room::Room) = Cell(room.x + room.width ÷ 2, room.y + room.height ÷ 2)
mutable struct BSPRegion
    rectangle::Room
    first::Union{Nothing,BSPRegion}
    second::Union{Nothing,BSPRegion}
    leaf::Int
end
BSPRegion(rectangle::Room) = BSPRegion(rectangle, nothing, nothing, 0)
mutable struct Level
    depth::Int
    width::Int
    height::Int
    terrain::Matrix{Char}
    memory::Matrix{Char}
    rooms::Vector{Room}
    arrival::Cell
    arrival_room::Int
    target::Cell
    monsters::Vector{Monster}
    items::Vector{Item}
    monsters_created::Int
    items_placed::Int
    kills::Int
    picked::Int
end
function Level(depth::Int, width::Int, height::Int)
    Level(depth, width, height, fill(' ', height, width), fill(' ', height, width), Room[], Cell(0, 0), 0, Cell(0, 0), Monster[], Item[], 0, 0, 0, 0)
end
monster_at(level::Level, x::Int, y::Int) = findfirst(monster -> monster.x == x && monster.y == y, level.monsters)
item_at(level::Level, x::Int, y::Int) = findfirst(item -> item.x == x && item.y == y, level.items)
function draw_interior_cell!(generator::Minstd, level::Level, index::Int)
    room = level.rooms[index]
    x = room.x + 1 + random_index!(generator, room.width - 2)
    y = room.y + 1 + random_index!(generator, room.height - 2)
    Cell(x, y)
end
function draw_room_cell!(generator::Minstd, level::Level)
    room = 1 + random_index!(generator, length(level.rooms))
    (room, draw_interior_cell!(generator, level, room))
end
struct LevelGenerator
    minimum::Int
    max_split::Int
    room_min::Int
    room_max::Int
end
function split_region!(builder::LevelGenerator, generator::Minstd, region::BSPRegion, depth::Int, leaves::Vector{BSPRegion})
    r = region.rectangle
    cv = r.width >= 2 * builder.minimum
    ch = r.height >= 2 * builder.minimum
    if depth == builder.max_split || !(cv || ch)
        region.leaf = length(leaves) + 1
        push!(leaves, region)
        return
    end
    vertical = if cv && ch
        if 4 * r.width >= 5 * r.height
            true
        elseif 4 * r.height >= 5 * r.width
            false
        else
            iseven(draw!(generator))
        end
    else
        cv
    end
    if vertical
        cut = builder.minimum + random_index!(generator, r.width - 2 * builder.minimum + 1)
        a = Room(r.x, r.y, cut, r.height)
        b = Room(r.x + cut, r.y, r.width - cut, r.height)
    else
        cut = builder.minimum + random_index!(generator, r.height - 2 * builder.minimum + 1)
        a = Room(r.x, r.y, r.width, cut)
        b = Room(r.x, r.y + cut, r.width, r.height - cut)
    end
    region.first = BSPRegion(a)
    region.second = BSPRegion(b)
    split_region!(builder, generator, region.first, depth + 1, leaves)
    split_region!(builder, generator, region.second, depth + 1, leaves)
end
function make_room!(builder::LevelGenerator, generator::Minstd, level::Level, region::Room)
    width = builder.room_min + random_index!(generator, min(builder.room_max, region.width - 1) - builder.room_min + 1)
    height = builder.room_min + random_index!(generator, min(builder.room_max, region.height - 1) - builder.room_min + 1)
    x = region.x + random_index!(generator, region.width - width)
    y = region.y + random_index!(generator, region.height - height)
    for row in y:(y + height - 1), column in x:(x + width - 1)
        level.terrain[row + 1, column + 1] = row == y || row == y + height - 1 ? '-' : (column == x || column == x + width - 1 ? '|' : '.')
    end
    Room(x, y, width, height)
end
function dig_corridor!(level::Level, first::Cell, second::Cell, horizontal::Bool)
    span(a, b) = a:(a <= b ? 1 : -1):b
    path = if horizontal
        vcat([Cell(x, first.y) for x in span(first.x, second.x)], [Cell(second.x, y) for y in span(first.y, second.y)])
    else
        vcat([Cell(first.x, y) for y in span(first.y, second.y)], [Cell(x, second.y) for x in span(first.x, second.x)])
    end
    for point in path
        value = level.terrain[point.y + 1, point.x + 1]
        if value == ' '
            level.terrain[point.y + 1, point.x + 1] = '#'
        elseif value == '-' || value == '|'
            level.terrain[point.y + 1, point.x + 1] = '+'
        end
    end
end
function connect_regions!(generator::Minstd, level::Level, region::BSPRegion)
    region.leaf != 0 && return [region.leaf]
    first = connect_regions!(generator, level, region.first)
    second = connect_regions!(generator, level, region.second)
    best = nothing
    for a in first, b in second
        start = center(level.rooms[a])
        finish = center(level.rooms[b])
        candidate = (abs(start.x - finish.x) + abs(start.y - finish.y), a, b)
        if isnothing(best) || candidate < best
            best = candidate
        end
    end
    horizontal = iseven(draw!(generator))
    dig_corridor!(level, center(level.rooms[best[2]]), center(level.rooms[best[3]]), horizontal)
    vcat(first, second)
end
function generate_level!(builder::LevelGenerator, generator::Minstd, depth::Int, width::Int, height::Int)
    level = Level(depth, width, height)
    root = BSPRegion(Room(0, 0, width, height))
    leaves = BSPRegion[]
    split_region!(builder, generator, root, 0, leaves)
    for leaf in leaves
        push!(level.rooms, make_room!(builder, generator, level, leaf.rectangle))
    end
    connect_regions!(generator, level, root)
    room, arrival = draw_room_cell!(generator, level)
    level.arrival = arrival
    level.arrival_room = room
    level.terrain[arrival.y + 1, arrival.x + 1] = '<'
    other = 1 + random_index!(generator, length(level.rooms) - 1)
    other >= room && (other += 1)
    level.target = draw_interior_cell!(generator, level, other)
    level
end
