function dense_ranks(values)
    ordered = sort(unique(values))
    mapping = Dict(v => i for (i, v) in enumerate(ordered))
    [mapping[v] for v in values]
end
function refine_ranks(m, ranks)
    while true
        values = [(ranks[a], Tuple(sort([(ranks[b], m.neighbors[a][b].kind)
            for b in neighbor_numbers(m, a)]))) for a in eachindex(m.atoms)]
        new_ranks = dense_ranks(values)
        length(unique(new_ranks)) == length(unique(ranks)) && return new_ranks
        ranks = new_ranks
    end
end
function canonical_ranks(m)
    invariants = [(degree(m, a), atom.element.number, atom.mass, atom.charge,
        atom.hydrogens, Int(atom.aromatic)) for (a, atom) in enumerate(m.atoms)]
    ranks = refine_ranks(m, dense_ranks(invariants))
    classes = length(unique(ranks))
    while length(unique(ranks)) != length(ranks)
        tied = minimum(r for r in unique(ranks) if count(==(r), ranks) > 1)
        first_atom = findfirst(==(tied), ranks)
        values = [2*r - Int(i == first_atom) for (i, r) in enumerate(ranks)]
        ranks = refine_ranks(m, dense_ranks(values))
    end
    ranks, classes
end
function atom_notation(m, a)
    atom = m.atoms[a]
    symbol = atom.element.symbol
    ordinary = symbol in ORGANIC && (!atom.aromatic || symbol in AROMATIC) && atom.mass == 0 && atom.charge == 0
    if atom.aromatic
        ordinary &= needs_pi(m, a) == needs_pi(m, a, 0)
        symbol = lowercase(symbol)
    end
    hydrogens = organic_hydrogens(atom, bond_total(m, a))
    ordinary && hydrogens !== nothing && hydrogens == atom.hydrogens && return symbol
    text = "[" * (atom.mass == 0 ? "" : string(atom.mass)) * symbol
    atom.hydrogens != 0 && (text *= "H" * (atom.hydrogens == 1 ? "" : string(atom.hydrogens)))
    if atom.charge != 0
        text *= atom.charge > 0 ? "+" : "-"
        abs(atom.charge) != 1 && (text *= string(abs(atom.charge)))
    end
    text * "]"
end
function canonical_bond_symbol(m, bond)
    a, b = bond.ends
    in_ring = bond.ring && m.atoms[a].aromatic && m.atoms[b].aromatic
    bond.kind == 1 && return in_ring ? "-" : ""
    bond.kind == 2 && return "="
    bond.kind == 3 && return "#"
    in_ring ? "" : ":"
end
function canonical_smiles(m, ranks)
    visits = zeros(Int, length(m.atoms))
    children = [Tuple{Int,ChemBond}[] for _ in m.atoms]
    closures = Set{Tuple{Int,Int}}()
    visit_count = 0
    function visit(a, incoming)
        visit_count += 1
        visits[a] = visit_count
        for b in sort(neighbor_numbers(m, a); by=b -> ranks[b])
            bond = m.neighbors[a][b]
            (bond === incoming || bond.ends in closures) && continue
            if visits[b] == 0
                push!(children[a], (b, bond))
                visit(b, bond)
            else
                push!(closures, bond.ends)
            end
        end
    end
    root = findfirst(==(1), ranks)
    visit(root, nothing)
    assignments, occupied = Dict{Tuple{Int,Int},Int}(), Set{Int}()
    function write_atom(a)
        parts = [atom_notation(m, a)]
        for b in sort(neighbor_numbers(m, a); by=b -> visits[b])
            bond = m.neighbors[a][b]
            bond.ends in closures || continue
            if haskey(assignments, bond.ends)
                number = pop!(assignments, bond.ends)
                delete!(occupied, number)
                symbol = ""
            else
                number = 1
                while number in occupied
                    number += 1
                end
                assignments[bond.ends] = number
                push!(occupied, number)
                symbol = canonical_bond_symbol(m, bond)
            end
            push!(parts, symbol * (number < 10 ? string(number) : "%" * lpad(string(number), 2, '0')))
        end
        for (i, (child, bond)) in enumerate(children[a])
            continuation = canonical_bond_symbol(m, bond) * write_atom(child)
            push!(parts, i < length(children[a]) ? "(" * continuation * ")" : continuation)
        end
        join(parts)
    end
    write_atom(root)
end
function canonicalize(m)
    ranks, classes = canonical_ranks(m)
    canonical_smiles(m, ranks), classes
end
