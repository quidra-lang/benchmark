from collections import deque

from molecule import AnalysisError


def breadth_first(molecule, root):
    parents = {root: None}
    queue = deque([root])
    while queue:
        atom = queue.popleft()
        for neighbor in sorted(molecule.neighbors[atom]):
            if neighbor not in parents:
                parents[neighbor] = atom
                queue.append(neighbor)
    paths = {}
    for atom in parents:
        path = []
        current = atom
        while current is not None:
            path.append(current)
            current = parents[current]
        paths[atom] = path
    return parents, paths


def ring_edges(sequence):
    return frozenset(tuple(sorted((sequence[index - 1], atom)))
                     for index, atom in enumerate(sequence))


def ring_sequence(sequence):
    first = sequence.index(min(sequence))
    forward = tuple(sequence[first:] + sequence[:first])
    backward = (forward[0],) + tuple(reversed(forward[1:]))
    return min(forward, backward)


def find_rings(molecule):
    candidates = []
    seen = set()
    bonds = sorted(molecule.bonds)
    for root in range(len(molecule.atoms)):
        parents, paths = breadth_first(molecule, root)
        for first, second in bonds:
            if parents[first] == second or parents[second] == first:
                continue
            if set(paths[first]).intersection(paths[second]) != {root}:
                continue
            sequence = list(reversed(paths[first])) + paths[second][:-1]
            edges = ring_edges(sequence)
            if edges not in seen:
                seen.add(edges)
                candidates.append((sequence, edges))
    basis = {}
    rings = []
    for sequence, original in sorted(candidates, key=lambda candidate: len(candidate[0])):
        reduced = original
        while reduced:
            pivot = max(reduced)
            if pivot not in basis:
                basis[pivot] = reduced
                rings.append(ring_sequence(sequence))
                break
            reduced = reduced.symmetric_difference(basis[pivot])
    molecule.rings = sorted(rings, key=lambda ring: (len(ring), ring))
    for ring in molecule.rings:
        molecule.ring_atoms.update(ring)
        for edge in ring_edges(ring):
            molecule.bonds[edge].ring = True


def aromatic_systems(molecule, needing):
    remaining = set(needing)
    systems = []
    while remaining:
        start = min(remaining)
        remaining.remove(start)
        system = {start}
        queue = deque([start])
        while queue:
            atom = queue.popleft()
            for neighbor, bond in sorted(molecule.neighbors[atom].items()):
                if bond.kind == 4 and neighbor in remaining:
                    remaining.remove(neighbor)
                    system.add(neighbor)
                    queue.append(neighbor)
        systems.append(system)
    return systems


def match_system(molecule, system):
    unpaired = set(system)
    pairs = []

    def search():
        if not unpaired:
            return True
        first = min(unpaired)
        unpaired.remove(first)
        for second, bond in sorted(molecule.neighbors[first].items()):
            if second not in unpaired or bond.kind != 4:
                continue
            unpaired.remove(second)
            pairs.append(bond.ends)
            if search():
                return True
            pairs.pop()
            unpaired.add(second)
        unpaired.add(first)
        return False

    return pairs if search() else None


def kekulize(molecule, needing):
    selected = set()
    for system in aromatic_systems(molecule, needing):
        pairs = match_system(molecule, system)
        if pairs is None:
            raise AnalysisError("kekulization failed", molecule.atoms[min(system)].column)
        selected.update(pairs)
    for bond in molecule.bonds.values():
        bond.multiplicity = (2 if bond.ends in selected else 1) if bond.kind == 4 else bond.kind
