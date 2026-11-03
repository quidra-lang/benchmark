@enum Targets GroundTargets AirTargets BothTargets
parse_targets(text::String) = text == "ground" ? GroundTargets : text == "air" ? AirTargets : BothTargets
can_aim(targets::Targets, movement::Movement) = targets == BothTargets || targets == GroundTargets && movement == GroundMovement || targets == AirTargets && movement == AirMovement
struct Level
    cost::Int
    range::Int
    power::Int
    interval::Int
    shot_speed::Int
    splash::Int
    slow_rate::Int
    slow_time::Int
    burn_amount::Int
    burn_time::Int
end
Level(fields::Vector{String}) = Level(parse.(Int, fields[2:end])...)
struct TowerType
    name::String
    symbol::UInt8
    targets::Targets
    levels::Vector{Level}
end
function parse_tower_types(lines::Vector{String})
    types = TowerType[]
    index = 1
    while index <= length(lines)
        fields = String.(split(lines[index], ' '))
        level_count = parse(Int, fields[5])
        levels = [Level(String.(split(line, ' '))) for line in lines[index+1:index+level_count]]
        push!(types, TowerType(fields[2], codeunit(fields[3], 1), parse_targets(fields[4]), levels))
        index += level_count + 1
    end
    types
end
@enum TargetMode FirstTarget LastTarget StrongestTarget WeakestTarget ClosestTarget
const TARGET_MODES = [FirstTarget, LastTarget, StrongestTarget, WeakestTarget, ClosestTarget]
const TARGET_NAMES = ["FIRST", "LAST", "STRONGEST", "WEAKEST", "CLOSEST"]
function parse_mode(text::String)
    index = findfirst(==(text), TARGET_NAMES)
    index === nothing ? nothing : TARGET_MODES[index]
end
mode_text(mode::TargetMode) = TARGET_NAMES[findfirst(==(mode), TARGET_MODES)]
mutable struct Tower
    number::Int
    kind::Int
    cell::Cell
    level::Int
    mode::TargetMode
    ready::Int
    investment::Int
    built::Int
    sold::Union{Nothing,Int}
    shots::Int
    hits::Int
    fizzles::Int
    kills::Int
    damage::Int
end
Tower(number::Int, kind::Int, types::Vector{TowerType}, cell::Cell, tick::Int) = Tower(number, kind, cell, 1, FirstTarget, tick, types[kind].levels[1].cost, tick, nothing, 0, 0, 0, 0, 0)
standing(tower::Tower) = tower.sold === nothing
tower_center(tower::Tower) = cell_center(tower.cell)
tower_stats(tower::Tower, types::Vector{TowerType}) = types[tower.kind].levels[tower.level]
function in_range(tower::Tower, point::Point, types::Vector{TowerType})
    reach = tower_stats(tower, types).range
    squared_distance(tower_center(tower), point) <= reach * reach
end
function select_target(tower::Tower, enemies::Vector{Enemy}, types::Vector{EnemyType}, tower_types::Vector{TowerType}, field::DistanceField)
    best = nothing
    best_key = 0
    for (index, enemy) in enumerate(enemies)
        (!enemy.alive || !can_aim(tower_types[tower.kind].targets, types[enemy.kind].movement) || !in_range(tower, enemy_point(enemy), tower_types)) && continue
        key = if tower.mode == FirstTarget
            remaining_distance(enemy, field)
        elseif tower.mode == LastTarget
            -remaining_distance(enemy, field)
        elseif tower.mode == StrongestTarget
            -enemy.hp
        elseif tower.mode == WeakestTarget
            enemy.hp
        else
            squared_distance(tower_center(tower), enemy_point(enemy))
        end
        if best === nothing || key < best_key
            best, best_key = index, key
        end
    end
    best
end
