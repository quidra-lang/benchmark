mutable struct Minstd
    state::Int64
    draws::Int
end
Minstd(seed) = Minstd(seed,0)
function draw_random!(random)
    random.state = (48271*random.state)%2147483647
    random.draws += 1
    random.state
end
between!(random,minimum,maximum) = minimum+draw_random!(random)%(maximum-minimum+1)
