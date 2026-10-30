function breadth_first(m, root)
    parents = fill(-1, length(m.atoms))
    parents[root] = 0
    queue, head = [root], 1
    while head <= length(queue)
        a = queue[head]
        head += 1
        for b in neighbor_numbers(m, a)
            parents[b] != -1 && continue
            parents[b] = a
            push!(queue, b)
        end
    end
    paths = Vector{Int}[]
    for a in eachindex(m.atoms)
        path, current = Int[], a
        while current != 0
            push!(path, current)
            current = parents[current]
        end
        push!(paths, path)
    end
    parents, paths
end
ring_bond_keys(r) = Set(bond_key(r[mod1(i-1, length(r))], r[i]) for i in eachindex(r))
function ring_sequence(sequence)
    index = argmin(sequence)
    forward = [sequence[index:end]; sequence[1:index-1]]
    backward = [forward[1:1]; reverse(forward[2:end])]
    Tuple(forward) < Tuple(backward) ? forward : backward
end
function find_rings!(m)
    candidates = Any[]
    seen = Set{Tuple}()
    bonds = sort(collect(keys(m.bonds)))
    indices = Dict(b => i for (i, b) in enumerate(bonds))
    for root in eachindex(m.atoms)
        parents, paths = breadth_first(m, root)
        for (x, y) in bonds
            (parents[x] == y || parents[y] == x) && continue
            intersect(Set(paths[x]), Set(paths[y])) == Set([root]) || continue
            sequence = [reverse(paths[x]); paths[y][1:end-1]]
            edges = Set(indices[key] for key in ring_bond_keys(sequence))
            key = Tuple(sort(collect(edges)))
            key in seen && continue
            push!(seen, key)
            push!(candidates, (sequence=sequence, edges=edges))
        end
    end
    sort!(candidates; alg=MergeSort, by=c -> length(c.sequence))
    basis = Dict{Int,Set{Int}}()
    for candidate in candidates
        reduced = copy(candidate.edges)
        while !isempty(reduced)
            pivot = maximum(reduced)
            if !haskey(basis, pivot)
                basis[pivot] = reduced
                push!(m.rings, ring_sequence(candidate.sequence))
                break
            end
            reduced = symdiff(reduced, basis[pivot])
        end
    end
    sort!(m.rings; by=r -> (length(r), Tuple(r)))
    for ring in m.rings
        union!(m.ring_atoms, ring)
        for key in ring_bond_keys(ring)
            m.bonds[key].ring = true
        end
    end
end
function aromatic_systems(m, needing)
    remaining, systems = Set(needing), Vector{Int}[]
    while !isempty(remaining)
        start = minimum(remaining)
        delete!(remaining, start)
        queue, head = [start], 1
        while head <= length(queue)
            a = queue[head]
            head += 1
            for b in neighbor_numbers(m, a)
                if b in remaining && m.neighbors[a][b].kind == 4
                    delete!(remaining, b)
                    push!(queue, b)
                end
            end
        end
        push!(systems, sort(queue))
    end
    systems
end
function match_system(m, system)
    unpaired, pairs = Set(system), Tuple{Int,Int}[]
    function search()
        isempty(unpaired) && return true
        a = minimum(unpaired)
        delete!(unpaired, a)
        for b in neighbor_numbers(m, a)
            (b in unpaired && m.neighbors[a][b].kind == 4) || continue
            delete!(unpaired, b)
            push!(pairs, bond_key(a, b))
            search() && return true
            pop!(pairs)
            push!(unpaired, b)
        end
        push!(unpaired, a)
        false
    end
    search() ? pairs : nothing
end
function kekulize!(m, needing)
    selected = Set{Tuple{Int,Int}}()
    for system in aromatic_systems(m, needing)
        pairs = match_system(m, system)
        pairs === nothing && analysis_error("kekulization failed", m.atoms[minimum(system)].column)
        union!(selected, pairs)
    end
    for bond in ordered_bonds(m)
        bond.multiplicity = bond.kind == 4 ? (bond.ends in selected ? 2 : 1) : bond.kind
    end
end
