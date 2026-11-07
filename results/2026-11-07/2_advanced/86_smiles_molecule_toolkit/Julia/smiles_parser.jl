character_at(text, position) = 1 <= position <= length(text) ? text[position] : '\0'
text_slice(text, a, b) = a <= b ? String(text[a:b]) : ""
ascii_digit(c) = '0' <= c <= '9'
function read_organic(text, position)
    pair = text_slice(text, position, min(length(text), position + 1))
    pair in ("Cl", "Br") && return (symbol=pair, aromatic=false, next=position + 2)
    c = character_at(text, position)
    c in "BCNOPSFI" && return (symbol=string(c), aromatic=false, next=position + 1)
    c in "bcnops" && return (symbol=uppercase(string(c)), aromatic=true, next=position + 1)
    nothing
end
function read_bracket(content, elements, column)
    position = 1
    while ascii_digit(character_at(content, position))
        position += 1
    end
    (position >= 5 || (position > 1 && content[1] == '0')) && analysis_error("bad bracket atom", column)
    mass = position == 1 ? 0 : parse(Int, content[1:position-1])
    c = character_at(content, position)
    c == '\0' && analysis_error("bad bracket atom", column)
    aromatic = c in "bcnops"
    if aromatic
        symbol = uppercase(string(c))
        position += 1
    elseif 'A' <= c <= 'Z'
        pair = text_slice(content, position, min(length(content), position + 1))
        if length(pair) == 2 && 'a' <= pair[2] <= 'z' && haskey(elements, pair)
            symbol = pair
            position += 2
        elseif haskey(elements, string(c))
            symbol = string(c)
            position += 1
        else
            analysis_error("unknown element", column)
        end
    else
        analysis_error("bad bracket atom", column)
    end
    if character_at(content, position) == '@'
        position += 1
        character_at(content, position) == '@' && (position += 1)
    end
    hydrogens, charge = 0, 0
    if character_at(content, position) == 'H'
        hydrogens = 1
        position += 1
        if ascii_digit(character_at(content, position))
            hydrogens = Int(content[position] - '0')
            position += 1
        end
    end
    c = character_at(content, position)
    if c in ('+', '-')
        charge = c == '+' ? 1 : -1
        position += 1
        c = character_at(content, position)
        if '1' <= c <= '9'
            charge *= Int(c - '0')
            position += 1
        end
    end
    position == length(content) + 1 || analysis_error("bad bracket atom", column)
    ChemAtom(elements[symbol], aromatic, mass, charge, hydrogens, true, column)
end
function read_atom(text, position, elements)
    if text[position] == '['
        last = findnext(==(']'), text, position + 1)
        last === nothing && analysis_error("unclosed bracket", position)
        return read_bracket(text_slice(text, position + 1, last - 1), elements, position), last + 1
    end
    organic = read_organic(text, position)
    organic === nothing && analysis_error("unexpected character", position)
    ChemAtom(elements[organic.symbol], organic.aromatic, 0, 0, 0, false, position), organic.next
end
function parse_smiles(text, elements; pattern=false)
    molecule = new_molecule(elements)
    symbols = pattern ? Dict("-" => 1, "=" => 2, "#" => 3, ":" => 4, "~" => 5) : BOND_TYPES
    current, pending, position = 0, nothing, 1
    branches = Tuple{Int,Int}[]
    open_rings = Dict{Int,Any}()
    while position <= length(text)
        c, column = text[position], position
        symbol = string(c)
        if haskey(symbols, symbol)
            (current == 0 || pending !== nothing) && analysis_error("misplaced bond", column)
            pending = (symbol=symbol, column=column)
            position += 1
        elseif c == '('
            if current == 0 || pending !== nothing || character_at(text, position - 1) == '('
                analysis_error("misplaced branch", column)
            end
            push!(branches, (current, column))
            position += 1
        elseif c == ')'
            isempty(branches) && analysis_error("unmatched parenthesis", column)
            pending !== nothing && analysis_error("dangling bond", pending.column)
            character_at(text, position - 1) == '(' && analysis_error("empty branch", column)
            current, _ = pop!(branches)
            position += 1
        elseif ascii_digit(c) || c == '%'
            current == 0 && analysis_error("misplaced ring closure", column)
            if c == '%'
                if !(ascii_digit(character_at(text, position + 1)) && ascii_digit(character_at(text, position + 2)))
                    analysis_error("bad ring number", column)
                end
                ring = parse(Int, text[position+1:position+2])
                position += 3
            else
                ring = Int(c - '0')
                position += 1
            end
            bond_symbol = pending === nothing ? nothing : pending.symbol
            pending = nothing
            if !haskey(open_rings, ring)
                open_rings[ring] = (atom=current, symbol=bond_symbol, column=column)
                continue
            end
            opened = open_rings[ring]
            opened.atom == current && analysis_error("self bond", column)
            if opened.symbol !== nothing && bond_symbol !== nothing && symbols[opened.symbol] != symbols[bond_symbol]
                analysis_error("ring bond mismatch", column)
            end
            haskey(molecule.neighbors[opened.atom], current) && analysis_error("duplicate bond", column)
            add_bond!(molecule, opened.atom, current, bond_symbol === nothing ? opened.symbol : bond_symbol)
            delete!(open_rings, ring)
        else
            atom, next = pattern ? read_pattern_atom(text, position, elements) : read_atom(text, position, elements)
            number = add_atom!(molecule, atom)
            current != 0 && add_bond!(molecule, current, number, pending === nothing ? nothing : pending.symbol)
            current, pending, position = number, nothing, next
        end
    end
    pending !== nothing && analysis_error("dangling bond", pending.column)
    isempty(branches) || analysis_error("unmatched parenthesis", branches[1][2])
    isempty(open_rings) || analysis_error("unclosed ring", minimum(r.column for r in values(open_rings)))
    molecule
end
