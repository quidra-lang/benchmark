from molecule import AnalysisError, BOND_TYPES, Molecule
from smiles_parser import read_organic


class PatternAtom:
    def __init__(self, choices=None, aromatic=None):
        self.choices = choices
        self.aromatic = aromatic

    def matches(self, atom):
        if self.choices is not None:
            return (atom.element.symbol, atom.aromatic) in self.choices
        return self.aromatic is None or atom.aromatic == self.aromatic


def read_pattern_atom(text, position, elements):
    character = text[position]
    if character in ("*", "A", "a"):
        aromatic = None if character == "*" else character == "a"
        return PatternAtom(aromatic=aromatic), position + 1
    if character == "[":
        end = text.find("]", position + 1)
        if end < 0:
            raise AnalysisError("unclosed bracket", position + 1)
        choices = set()
        for item in text[position + 1:end].split(","):
            organic = read_organic(item, 0)
            if organic is None or organic[2] != len(item):
                raise AnalysisError("bad bracket atom", position + 1)
            choices.add(organic[:2])
        return PatternAtom(choices), end + 1
    organic = read_organic(text, position)
    if organic is None:
        raise AnalysisError("unexpected character", position + 1)
    return PatternAtom({organic[:2]}), organic[2]


def molecule_pattern(molecule):
    pattern = Molecule(molecule.elements)
    for atom in molecule.atoms:
        pattern.add_atom(PatternAtom({(atom.element.symbol, atom.aromatic)}))
    for bond in molecule.ordered_bonds():
        pattern.add_bond(*bond.ends, bond.kind)
    return pattern


def bond_matches(pattern_bond, molecule_bond):
    symbol = pattern_bond.symbol
    if symbol is None:
        return molecule_bond.kind in (1, 4)
    if symbol == "~":
        return True
    kind = BOND_TYPES[symbol] if isinstance(symbol, str) else symbol
    return molecule_bond.kind == kind


def embeddings(pattern, molecule):
    if len(pattern.atoms) > len(molecule.atoms):
        return 0, 0, None
    candidates = [[number for number, atom in enumerate(molecule.atoms)
                   if pattern_atom.matches(atom) and molecule.degree(number) >= pattern.degree(index)]
                  for index, pattern_atom in enumerate(pattern.atoms)]
    earlier = [[(neighbor, bond) for neighbor, bond in neighbors.items() if neighbor < number]
               for number, neighbors in enumerate(pattern.neighbors)]
    mapping = []
    used = set()
    unique = set()
    count = 0
    first_mapping = None

    def assign(index):
        nonlocal count, first_mapping
        if index == len(pattern.atoms):
            count += 1
            unique.add(frozenset(used))
            if first_mapping is None:
                first_mapping = tuple(mapping)
            return
        for atom in candidates[index]:
            if atom in used:
                continue
            for neighbor, bond in earlier[index]:
                target_bond = molecule.neighbors[atom].get(mapping[neighbor])
                if target_bond is None or not bond_matches(bond, target_bond):
                    break
            else:
                mapping.append(atom)
                used.add(atom)
                assign(index + 1)
                used.remove(atom)
                mapping.pop()

    assign(0)
    return count, len(unique), first_mapping


def fingerprint(molecule):
    codes = [16 * atom.element.number + 8 * int(atom.aromatic) + molecule.degree(number)
             for number, atom in enumerate(molecule.atoms)]
    bits = set()
    count = 0
    used = set()

    def extend(atom, depth, value):
        nonlocal count
        count += 1
        bits.add(value % 1024)
        if depth == 5:
            return
        for neighbor, bond in sorted(molecule.neighbors[atom].items()):
            if neighbor in used:
                continue
            next_value = (value * 31 + bond.kind) % 1000003
            next_value = (next_value * 31 + codes[neighbor]) % 1000003
            used.add(neighbor)
            extend(neighbor, depth + 1, next_value)
            used.remove(neighbor)

    for atom, code in enumerate(codes):
        used.add(atom)
        extend(atom, 0, code)
        used.remove(atom)
    return frozenset(bits), count


def tanimoto(first, second):
    common = len(first.intersection(second))
    return common, len(first) + len(second) - common
