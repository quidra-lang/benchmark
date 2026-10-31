module Baskets
export Product, Transaction, bit, hasitems, members, setless, sizeless, records, extended
struct Product
    name::String
    category::Int
    price::Int
    code::Int
end
mutable struct Transaction
    tid::String
    customer::String
    day::Int
    units::Vector{Int}
    mask::UInt128
end
bit(code) = UInt128(1) << (code-1)
hasitems(basket,itemset) = basket & itemset == itemset
function members(mask::UInt128)
    values = Int[]
    while mask != 0
        code = trailing_zeros(mask)+1
        push!(values,code)
        mask &= mask-1
    end
    values
end
function setless(a::UInt128,b::UInt128)
    while a != 0 && b != 0
        first,second = trailing_zeros(a),trailing_zeros(b)
        first != second && return first < second
        a &= a-1
        b &= b-1
    end
    a == 0 && b != 0
end
sizeless(a,b) = count_ones(a) == count_ones(b) ? setless(a,b) : count_ones(a) < count_ones(b)
records(name) = [String.(split(line,',')) for line in readlines("input/"*name)[2:end]]
function extended(basket,products)
    mask = basket.mask
    for (p,quantity) in zip(products,basket.units)
        quantity > 0 && (mask |= bit(p.category))
    end
    mask
end
end
