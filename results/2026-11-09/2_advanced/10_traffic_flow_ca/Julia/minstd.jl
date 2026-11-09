module RandomTraffic
export Minstd, draw!, select_weight
mutable struct Minstd
    state::Int
end
function draw!(rng)
    rng.state = mod(48271 * rng.state, 2147483647)
end
function select_weight(weights, value)
    q = mod(value, sum(weights))
    total = 0
    for (i, weight) in enumerate(weights)
        total += weight
        q < total && return i
    end
    error("invalid weights")
end
end
