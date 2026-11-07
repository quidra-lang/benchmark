mutable struct Minstd
    state::Int
end
function draw!(generator::Minstd)
    generator.state = generator.state * 48271 % 2147483647
end
random_index!(generator::Minstd, size::Int) = draw!(generator) % size
function roll!(generator::Minstd, count::Int, sides::Int)
    total = 0
    for _ in 1:count
        total += 1 + random_index!(generator, sides)
    end
    total
end
function weighted_index!(generator::Minstd, weights::Vector{Int})
    threshold = random_index!(generator, sum(weights))
    total = 0
    for (index, weight) in enumerate(weights)
        total += weight
        threshold < total && return index
    end
    error("Invalid weights")
end
