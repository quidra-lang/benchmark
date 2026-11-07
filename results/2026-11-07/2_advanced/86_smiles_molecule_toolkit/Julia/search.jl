struct PatternAtom
    choices::Union{Nothing,Set{Tuple{String,Bool}}}
    aromatic::Union{Nothing,Bool}
end
function pattern_matches(pattern, atom)
    if pattern.choices !== nothing
        return (atom.element.symbol, atom.aromatic) in pattern.choices
    end
    pattern.aromatic === nothing || atom.aromatic == pattern.aromatic
end
function read_pattern_atom(text, position, elements)
    c = text[position]
    if c in ('*', 'A', 'a')
        return PatternAtom(nothing, c == '*' ? nothing : c == 'a'), position + 1
    elseif c == '['
        last = findnext(==(']'), text, position + 1)
        last === nothing && analysis_error("unclosed bracket", position)
        choices = Set{Tuple{String,Bool}}()
        for item in split(text_slice(text, position + 1, last - 1), ','; keepempty=true)
            organic = read_organic(item, 1)
            (organic === nothing || organic.next != length(item) + 1) && analysis_error("bad bracket atom", position)
            push!(choices, (organic.symbol, organic.aromatic))
        end
        return PatternAtom(choices, nothing), last + 1
    end
    organic = read_organic(text, position)
    organic === nothing && analysis_error("unexpected character", position)
    PatternAtom(Set([(organic.symbol, organic.aromatic)]), nothing), organic.next
end
function molecule_pattern(m)
    pattern = new_molecule(m.elements)
    for atom in m.atoms
        add_atom!(pattern, PatternAtom(Set([(atom.element.symbol, atom.aromatic)]), nothing))
    end
    for bond in ordered_bonds(m)
        add_bond!(pattern, bond.ends[1], bond.ends[2], bond.kind)
    end
    pattern
end
function bond_matches(pattern, bond)
    symbol = pattern.symbol
    symbol === nothing && return bond.kind in (1, 4)
    symbol == "~" && return true
    bond.kind == (symbol isa Int ? symbol : BOND_TYPES[symbol])
end
function embeddings(pattern, m)
    n, k = length(m.atoms), length(pattern.atoms)
    k > n && return (count=0, unique=0, mapping=Int[])
    candidates = [[a for a in 1:n if pattern_matches(pattern.atoms[i], m.atoms[a]) && degree(m, a) >= degree(pattern, i)] for i in 1:k]
    mapping, used, sets = Int[], Set{Int}(), Set{Tuple}()
    count_matches, first_mapping = 0, Int[]
    function assign_atom(i)
        if i > k
            count_matches += 1
            push!(sets, Tuple(sort(collect(used))))
            isempty(first_mapping) && (first_mapping = copy(mapping))
            return
        end
        for a in candidates[i]
            a in used && continue
            feasible = true
            for b in neighbor_numbers(pattern, i)
                b >= i && continue
                target = get(m.neighbors[a], mapping[b], nothing)
                if target === nothing || !bond_matches(pattern.neighbors[i][b], target)
                    feasible = false
                    break
                end
            end
            feasible || continue
            push!(mapping, a)
            push!(used, a)
            assign_atom(i + 1)
            delete!(used, a)
            pop!(mapping)
        end
    end
    assign_atom(1)
    (count=count_matches, unique=length(sets), mapping=first_mapping)
end
function fingerprint(m)
    codes = [16*atom.element.number + 8*Int(atom.aromatic) + degree(m, a) for (a, atom) in enumerate(m.atoms)]
    bits, used, paths = Set{Int}(), Set{Int}(), 0
    function extend_path(a, depth, value)
        paths += 1
        push!(bits, value % 1024)
        depth == 5 && return
        for b in neighbor_numbers(m, a)
            b in used && continue
            next_value = (value*31 + m.neighbors[a][b].kind) % 1000003
            next_value = (next_value*31 + codes[b]) % 1000003
            push!(used, b)
            extend_path(b, depth + 1, next_value)
            delete!(used, b)
        end
    end
    for (a, code) in enumerate(codes)
        push!(used, a)
        extend_path(a, 0, code)
        delete!(used, a)
    end
    bits, paths
end
function tanimoto(a, b)
    common = length(intersect(a, b))
    common, length(a) + length(b) - common
end
