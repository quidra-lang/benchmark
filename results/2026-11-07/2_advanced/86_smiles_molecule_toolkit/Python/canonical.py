from collections import Counter

from molecule import AROMATIC, ORGANIC, needs_pi, organic_hydrogens


def dense_ranks(values):
    ranks = {value: index for index, value in enumerate(sorted(set(values)), 1)}
    return [ranks[value] for value in values]


def refine(molecule, ranks):
    while True:
        values = [(ranks[atom], tuple(sorted((ranks[neighbor], bond.kind)
                                            for neighbor, bond in neighbors.items())))
                  for atom, neighbors in enumerate(molecule.neighbors)]
        new_ranks = dense_ranks(values)
        if len(set(new_ranks)) == len(set(ranks)):
            return new_ranks
        ranks = new_ranks


def canonical_ranks(molecule):
    invariants = [(molecule.degree(number), atom.element.number, atom.mass,
                   atom.charge, atom.hydrogens, int(atom.aromatic))
                  for number, atom in enumerate(molecule.atoms)]
    ranks = refine(molecule, dense_ranks(invariants))
    classes = len(set(ranks))
    while len(set(ranks)) != len(ranks):
        counts = Counter(ranks)
        tied_rank = min(rank for rank, count in counts.items() if count > 1)
        first = ranks.index(tied_rank)
        values = [2 * rank - int(number == first) for number, rank in enumerate(ranks)]
        ranks = refine(molecule, dense_ranks(values))
    return ranks, classes


def atom_notation(molecule, number):
    atom = molecule.atoms[number]
    symbol = atom.element.symbol
    ordinary = symbol in ORGANIC and (not atom.aromatic or symbol in AROMATIC)
    ordinary = ordinary and atom.mass == 0 and atom.charge == 0
    if atom.aromatic:
        ordinary = ordinary and needs_pi(molecule, number) == needs_pi(molecule, number, 0)
        symbol = symbol.lower()
    hydrogens = organic_hydrogens(atom, molecule.bond_total(number))
    if ordinary and hydrogens is not None and hydrogens == atom.hydrogens:
        return symbol
    text = "[" + (str(atom.mass) if atom.mass else "") + symbol
    if atom.hydrogens:
        text += "H" + (str(atom.hydrogens) if atom.hydrogens != 1 else "")
    if atom.charge:
        text += "+" if atom.charge > 0 else "-"
        if abs(atom.charge) != 1:
            text += str(abs(atom.charge))
    return text + "]"


def bond_symbol(molecule, bond):
    first, second = bond.ends
    in_ring = bond.ring and molecule.atoms[first].aromatic and molecule.atoms[second].aromatic
    if bond.kind == 1:
        return "-" if in_ring else ""
    if bond.kind == 2:
        return "="
    if bond.kind == 3:
        return "#"
    return "" if in_ring else ":"


def canonical_smiles(molecule, ranks):
    visits = {}
    children = [[] for atom in molecule.atoms]
    closures = set()

    def visit(atom, incoming):
        visits[atom] = len(visits) + 1
        for neighbor in sorted(molecule.neighbors[atom], key=lambda number: ranks[number]):
            bond = molecule.neighbors[atom][neighbor]
            if bond is incoming or bond.ends in closures:
                continue
            if neighbor not in visits:
                children[atom].append((neighbor, bond))
                visit(neighbor, bond)
            else:
                closures.add(bond.ends)

    root = ranks.index(1)
    visit(root, None)
    assignments = {}
    occupied = set()

    def write(atom):
        parts = [atom_notation(molecule, atom)]
        neighbors = sorted(molecule.neighbors[atom], key=lambda number: visits[number])
        for neighbor in neighbors:
            bond = molecule.neighbors[atom][neighbor]
            if bond.ends not in closures:
                continue
            if bond.ends in assignments:
                number = assignments.pop(bond.ends)
                occupied.remove(number)
                symbol = ""
            else:
                number = 1
                while number in occupied:
                    number += 1
                assignments[bond.ends] = number
                occupied.add(number)
                symbol = bond_symbol(molecule, bond)
            parts.append(symbol + (str(number) if number < 10 else f"%{number:02d}"))
        for index, (child, bond) in enumerate(children[atom]):
            continuation = bond_symbol(molecule, bond) + write(child)
            parts.append("(" + continuation + ")" if index + 1 < len(children[atom]) else continuation)
        return "".join(parts)

    return write(root)


def canonicalize(molecule):
    ranks, classes = canonical_ranks(molecule)
    return canonical_smiles(molecule, ranks), classes
