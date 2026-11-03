mutable struct Minstd
    state::Int
end

function draw!(generator)
    generator.state = mod(48271 * generator.state, 2147483647)
end

draw_below!(generator, limit) = mod(draw!(generator), limit)

function shuffle!(generator, items)
    for index in length(items):-1:2
        other = draw_below!(generator, index) + 1
        items[index], items[other] = items[other], items[index]
    end
    items
end
