@enum Movement GroundMovement AirMovement
mutable struct EnemyType
    name::String
    symbol::UInt8
    movement::Movement
    hp::Int
    armor::Int
    speed::Int
    bounty::Int
    lives::Int
    regen::Int
    split_into::Union{Nothing,Int}
    split_count::Int
    spawned::Int
    kills::Int
    leaks::Int
    damage::Int
end
struct Group
    kind::Int
    spawn::Int
    count::Int
    delay::Int
    interval::Int
    multiplier::Int
end
spawn_tick(group::Group, start::Int, index::Int) = start + group.delay + index * group.interval
struct Wave
    reward::Int
    groups::Vector{Group}
end
Wave(reward::Int) = Wave(reward, Group[])
enemy_count(wave::Wave) = sum(group.count for group in wave.groups)
function parse_waves(lines::Vector{String})
    types = EnemyType[]
    known = Dict{String,Int}()
    waves = Wave[]
    for line in lines
        fields = String.(split(line, ' '))
        if fields[1] == "enemy"
            split_into = fields[11] == "-" ? nothing : known[fields[11]]
            kind = EnemyType(fields[2], codeunit(fields[3], 1), fields[4] == "air" ? AirMovement : GroundMovement,
                parse(Int, fields[5]), parse(Int, fields[6]), parse(Int, fields[7]), parse(Int, fields[8]), parse(Int, fields[9]), parse(Int, fields[10]),
                split_into, parse(Int, fields[12]), 0, 0, 0, 0)
            push!(types, kind)
            known[kind.name] = length(types)
        elseif fields[1] == "wave"
            push!(waves, Wave(parse(Int, fields[2])))
        else
            push!(waves[end].groups, Group(known[fields[2]], parse(Int, fields[3]), parse(Int, fields[4]), parse(Int, fields[5]), parse(Int, fields[6]), parse(Int, fields[7])))
        end
    end
    types, waves
end
struct GroundPosition
    cell::Cell
    next_cell::Cell
    progress::Int
end
struct AirPosition
    point::Point
end
const EnemyPosition = Union{GroundPosition,AirPosition}
mutable struct Enemy
    number::Int
    kind::Int
    multiplier::Int
    max_hp::Int
    hp::Int
    slow::Effect
    burn::Effect
    alive::Bool
    position::EnemyPosition
end
function Enemy(number::Int, kind::Int, types::Vector{EnemyType}, multiplier::Int, position::EnemyPosition)
    hp = types[kind].hp * multiplier ÷ 100
    Enemy(number, kind, multiplier, hp, hp, Effect(), Effect(), true, position)
end
enemy_point(position::AirPosition) = position.point
enemy_point(position::GroundPosition) = (100 * position.cell[1] + (position.next_cell[1] - position.cell[1]) * position.progress,
    100 * position.cell[2] + (position.next_cell[2] - position.cell[2]) * position.progress)
enemy_point(enemy::Enemy) = enemy_point(enemy.position)
occupied_cell(position::AirPosition) = ((position.point[1] + 50) ÷ 100, (position.point[2] + 50) ÷ 100)
occupied_cell(position::GroundPosition) = position.progress < 50 ? position.cell : position.next_cell
occupied_cell(enemy::Enemy) = occupied_cell(enemy.position)
function remaining_distance(enemy::Enemy, field::DistanceField)
    position = enemy.position
    position isa AirPosition && return integer_sqrt(squared_distance(position.point, cell_center(field.exit)))
    100 * distance_at(field, position.next_cell) + 100 - position.progress
end
function slowed_speed(enemy::Enemy, types::Vector{EnemyType})
    speed = types[enemy.kind].speed
    effect_active(enemy.slow) ? speed * (100 - enemy.slow.strength) ÷ 100 : speed
end
split_enemy(enemy::Enemy, number::Int, types::Vector{EnemyType}) = Enemy(number, types[enemy.kind].split_into, types, enemy.multiplier, enemy.position)
