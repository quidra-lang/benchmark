mutable struct Minstd
    state::Int
end
function draw!(rng)
    rng.state = 48271*rng.state % 2147483647
end
below!(rng,limit) = draw!(rng) % limit
chance!(rng,fraction) = below!(rng,fraction[2]) < fraction[1]
function shuffle_genes!(rng,genes)
    for i in length(genes):-1:2
        j = below!(rng,i)+1
        genes[i],genes[j] = genes[j],genes[i]
    end
    genes
end
