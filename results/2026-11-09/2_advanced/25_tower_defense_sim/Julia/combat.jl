function squared_distance(first::Point, second::Point)
    dx, dy = first[1] - second[1], first[2] - second[2]
    dx * dx + dy * dy
end
function integer_sqrt(value::Int)
    low, high = 0, value + 1
    while low + 1 < high
        middle = (low + high) ÷ 2
        if middle <= value ÷ middle
            low = middle
        else
            high = middle
        end
    end
    low
end
function advance_point(point::Point, goal::Point, step::Int)
    dx, dy = goal[1] - point[1], goal[2] - point[2]
    squared = dx * dx + dy * dy
    squared <= step * step && return (goal, true)
    length = integer_sqrt(squared)
    (point[1] + div(dx * step, length), point[2] + div(dy * step, length)), false
end
damage_dealt(hp::Int, power::Int, armor::Int) = min(hp, max(1, power - armor))
mutable struct Effect
    strength::Int
    remaining::Int
    source::Union{Nothing,Int}
end
Effect() = Effect(0, 0, nothing)
effect_active(effect::Effect) = effect.remaining > 0
function receive!(effect::Effect, strength::Int, duration::Int, source::Union{Nothing,Int} = nothing)
    if strength > effect.strength
        effect.strength, effect.remaining, effect.source = strength, duration, source
    elseif strength == effect.strength
        effect.remaining = max(effect.remaining, duration)
    end
end
function advance_time!(effect::Effect)
    effect.remaining -= 1
    if effect.remaining == 0
        effect.strength = 0
        effect.source = nothing
    end
end
mutable struct Projectile{T,S}
    number::Int
    tower::Int
    target::Int
    position::Point
    aim::Point
    targets::T
    stats::S
end
function fly!(projectile::Projectile)
    projectile.stats.shot_speed == 0 && return true
    point, arrived = advance_point(projectile.position, projectile.aim, projectile.stats.shot_speed)
    projectile.position = point
    arrived
end
