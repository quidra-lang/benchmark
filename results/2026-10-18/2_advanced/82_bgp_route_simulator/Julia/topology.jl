const IPPrefix = Tuple{Int,Int}
address_value(text) = foldl((value, octet) -> 256 * value + parse(Int, octet), split(text, '.'); init=0)
address_text(value) = join(((value >> shift) & 255 for shift in (24, 16, 8, 0)), ".")
function parse_prefix(text)
    address, length = split(text, '/')
    return address_value(address), parse(Int, length)
end
prefix_text(prefix) = address_text(prefix[1]) * "/" * string(prefix[2])
prefix_contains(prefix, address) = address >> (32 - prefix[2]) == prefix[1] >> (32 - prefix[2])

mutable struct BGPLink
    number::Int
    name::String
    first::Int
    second::Int
    relationship::String
    delay::Int
    mrai::Int
    up::Bool
    down_count::Int
end

other_end(link, owner) = owner == link.first ? link.second : link.first
link_role(link, owner) = link.relationship == "P2P" ? "peer" : owner == link.first ? "customer" : "provider"
link_direction(link, owner) = Dict(
    "customer" => "D",
    "peer" => "P",
    "provider" => "U"
)[link_role(link, owner)]

function read_topology()
    router_ids, links, initial = Dict{Int,Int}(), BGPLink[], Any[]
    for line in readlines("input/topology.txt")
        fields = String.(split(line, ' '))
        if fields[1] == "AS"
            router_ids[parse(Int, fields[2])] = address_value(fields[3])
        elseif fields[1] == "LINK"
            push!(
                links,
                BGPLink(
                    length(links) + 1,
                    fields[2],
                    parse(Int, fields[3]),
                    parse(Int, fields[4]),
                    fields[5],
                    parse(Int, fields[6]),
                    parse(Int, fields[7]),
                    true,
                    0
                )
            )
        else
            push!(initial, (parse(Int, fields[2]), parse_prefix(fields[3]), fields[4], fields[5:end]))
        end
    end
    ases = sort!(collect(keys(router_ids)))
    at_as = Dict(owner => [link.number for link in links if owner in (
        link.first,
        link.second
    )] for owner in ases)
    by_name = Dict(link.name => link.number for link in links)
    between = Dict{Tuple{Int,Int},Vector{Int}}()
    for link in links
        key = minmax(link.first, link.second)
        push!(get!(between, key, Int[]), link.number)
    end
    return (; router_ids, ases, links, initial, at_as, by_name, between)
end
