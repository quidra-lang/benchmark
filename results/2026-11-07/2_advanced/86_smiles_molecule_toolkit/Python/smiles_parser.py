from molecule import AnalysisError, Atom, BOND_TYPES, Molecule


def read_organic(text, position):
    pair = text[position:position + 2]
    if pair in ("Cl", "Br"):
        return pair, False, position + 2
    character = text[position:position + 1]
    if character and character in "BCNOPSFI":
        return character, False, position + 1
    if character and character in "bcnops":
        return character.upper(), True, position + 1
    return None


def read_bracket(content, elements, column):
    position = 0
    while position < len(content) and content[position].isdigit():
        position += 1
    if position >= 4 or position and content[0] == "0":
        raise AnalysisError("bad bracket atom", column)
    mass = int(content[:position]) if position else 0
    if position == len(content):
        raise AnalysisError("bad bracket atom", column)
    character = content[position]
    if character in "bcnops":
        symbol, aromatic = character.upper(), True
        position += 1
    elif "A" <= character <= "Z":
        pair = content[position:position + 2]
        if len(pair) == 2 and "a" <= pair[1] <= "z" and pair in elements:
            symbol = pair
            position += 2
        elif character in elements:
            symbol = character
            position += 1
        else:
            raise AnalysisError("unknown element", column)
        aromatic = False
    else:
        raise AnalysisError("bad bracket atom", column)
    if content[position:position + 2] == "@@":
        position += 2
    elif content[position:position + 1] == "@":
        position += 1
    hydrogens = 0
    if content[position:position + 1] == "H":
        hydrogens = 1
        position += 1
        if position < len(content) and content[position].isdigit():
            hydrogens = int(content[position])
            position += 1
    charge = 0
    if content[position:position + 1] in ("+", "-"):
        charge = 1 if content[position] == "+" else -1
        position += 1
        if position < len(content) and content[position] in "123456789":
            charge *= int(content[position])
            position += 1
    if position != len(content):
        raise AnalysisError("bad bracket atom", column)
    return Atom(elements[symbol], aromatic, mass, charge, hydrogens, True, column)


def read_atom(text, position, elements):
    if text[position] == "[":
        end = text.find("]", position + 1)
        if end < 0:
            raise AnalysisError("unclosed bracket", position + 1)
        return read_bracket(text[position + 1:end], elements, position + 1), end + 1
    organic = read_organic(text, position)
    if organic is None:
        raise AnalysisError("unexpected character", position + 1)
    symbol, aromatic, end = organic
    return Atom(elements[symbol], aromatic, column=position + 1), end


def parse_smiles(text, elements, atom_reader=None, pattern=False):
    molecule = Molecule(elements)
    atom_reader = read_atom if atom_reader is None else atom_reader
    symbols = {"-": 1, "=": 2, "#": 3, ":": 4, "~": 5} if pattern else BOND_TYPES
    current = pending = None
    branches = []
    open_rings = {}
    position = 0
    while position < len(text):
        character = text[position]
        column = position + 1
        if character in symbols:
            if current is None or pending is not None:
                raise AnalysisError("misplaced bond", column)
            pending = character, column
            position += 1
        elif character == "(":
            if current is None or pending is not None or text[position - 1] == "(":
                raise AnalysisError("misplaced branch", column)
            branches.append((current, column))
            position += 1
        elif character == ")":
            if not branches:
                raise AnalysisError("unmatched parenthesis", column)
            if pending is not None:
                raise AnalysisError("dangling bond", pending[1])
            if text[position - 1] == "(":
                raise AnalysisError("empty branch", column)
            current, opening = branches.pop()
            position += 1
        elif character.isdigit() or character == "%":
            if current is None:
                raise AnalysisError("misplaced ring closure", column)
            if character == "%":
                digits = text[position + 1:position + 3]
                if len(digits) != 2 or not digits.isdigit():
                    raise AnalysisError("bad ring number", column)
                ring = int(digits)
                position += 3
            else:
                ring = int(character)
                position += 1
            symbol = pending[0] if pending is not None else None
            pending = None
            if ring not in open_rings:
                open_rings[ring] = current, symbol, column
                continue
            first, initial_symbol, opening = open_rings[ring]
            if first == current:
                raise AnalysisError("self bond", column)
            if initial_symbol is not None and symbol is not None and symbols[initial_symbol] != symbols[symbol]:
                raise AnalysisError("ring bond mismatch", column)
            if current in molecule.neighbors[first]:
                raise AnalysisError("duplicate bond", column)
            molecule.add_bond(first, current, symbol if symbol is not None else initial_symbol)
            del open_rings[ring]
        else:
            atom, position = atom_reader(text, position, elements)
            new_atom = molecule.add_atom(atom)
            if current is not None:
                molecule.add_bond(current, new_atom, pending[0] if pending is not None else None)
            current = new_atom
            pending = None
    if pending is not None:
        raise AnalysisError("dangling bond", pending[1])
    if branches:
        raise AnalysisError("unmatched parenthesis", branches[0][1])
    if open_rings:
        raise AnalysisError("unclosed ring", min(record[2] for record in open_rings.values()))
    return molecule
