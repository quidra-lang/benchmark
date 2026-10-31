const TILE_ORDER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ?"
mutable struct Minstd
    state::Int64
end
function next_random!(random)
    random.state = (48271*random.state)%2147483647
end
function shuffle_bag!(bag,random)
    for i in length(bag):-1:2
        j = next_random!(random)%i+1
        bag[i],bag[j] = bag[j],bag[i]
    end
    bag
end
function make_bag(counts,random)
    bag = [letter for letter in TILE_ORDER for _ in 1:counts[tile_index(letter)]]
    shuffle_bag!(bag,random)
end
function draw_tiles!(bag,n)
    join([pop!(bag) for _ in 1:min(n,length(bag))])
end
function exchange_tiles!(bag,returned,random)
    drawn = draw_tiles!(bag,length(returned))
    append!(bag,sort!(collect(returned)))
    shuffle_bag!(bag,random)
    drawn
end
collection_points(collection,values) = sum((values[tile_index(l)] for l in collection);init=0)
