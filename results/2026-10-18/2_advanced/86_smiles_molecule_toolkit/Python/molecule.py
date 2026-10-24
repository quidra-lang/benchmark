from collections import namedtuple
from pathlib import Path


Element = namedtuple("Element", "symbol number weight valences")
ORGANIC = frozenset(("B", "C", "N", "O", "P", "S", "F", "Cl", "Br", "I"))
AROMATIC = frozenset("BCNOPS")
BOND_TYPES = {"-": 1, "/": 1, "\\": 1, "=": 2, "#": 3, ":": 4}
BASE_VALUES = (0, 1, 2, 3, 1)


class AnalysisError(Exception):
    def __init__(self, reason, column):
        super().__init__(reason)
        self.reason = reason
        self.column = column


class Atom:
    def __init__(self, element, aromatic=False, mass=0, charge=0, hydrogens=0,
                 bracket=False, column=0):
        self.element = element
        self.aromatic = aromatic
        self.mass = mass
        self.charge = charge
        self.hydrogens = hydrogens
        self.bracket = bracket
        self.column = column


class Bond:
    def __init__(self, first, second, symbol):
        self.ends = tuple(sorted((first, second)))
        self.symbol = symbol
        self.kind = None
        self.multiplicity = 0
        self.ring = False


class Molecule:
    def __init__(self, elements):
        self.elements = elements
        self.atoms = []
        self.neighbors = []
        self.bonds = {}
        self.rings = []
        self.ring_atoms = set()
        self.name = ""

    def add_atom(self, atom):
        number = len(self.atoms)
        self.atoms.append(atom)
        self.neighbors.append({})
        return number

    def add_bond(self, first, second, symbol):
        bond = Bond(first, second, symbol)
        self.bonds[bond.ends] = bond
        self.neighbors[first][second] = bond
        self.neighbors[second][first] = bond
        return bond

    def ordered_bonds(self):
        return [self.bonds[ends] for ends in sorted(self.bonds)]

    def degree(self, number):
        return len(self.neighbors[number])

    def base_total(self, number):
        return sum(BASE_VALUES[bond.kind] for bond in self.neighbors[number].values())

    def bond_total(self, number):
        return sum(bond.multiplicity for bond in self.neighbors[number].values())


def read_elements(path):
    elements = {}
    for line in Path(path).read_text(encoding="ascii").splitlines():
        if not line or line.startswith("#"):
            continue
        symbol, number, weight, valences = line.split(" ")
        elements[symbol] = Element(symbol, int(number), int(weight),
                                   tuple(int(value) for value in valences.split(",")))
    return elements


def needs_pi(molecule, number, hydrogens=None):
    atom = molecule.atoms[number]
    if hydrogens is None:
        hydrogens = atom.hydrogens
    occupied = molecule.base_total(number) + hydrogens
    return atom.aromatic and atom.element.valences[0] + atom.charge >= occupied + 1


def organic_hydrogens(atom, bond_total):
    for valence in atom.element.valences:
        if valence >= bond_total:
            return valence - bond_total
    return None
