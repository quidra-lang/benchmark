from collections import Counter, defaultdict, deque
from functools import cmp_to_key
from math import gcd
from pathlib import Path
from string import ascii_letters, digits

from canonical import canonicalize
from molecule import AnalysisError, Atom, BOND_TYPES, Molecule, needs_pi, organic_hydrogens, read_elements
from rings_aromatic import find_rings, kekulize
from search import embeddings, fingerprint, molecule_pattern, read_pattern_atom, tanimoto
from smiles_parser import parse_smiles


NAME_CHARACTERS = frozenset(ascii_letters + digits + "_-")
ARGUMENT_COUNTS = {"MATCH": (1, 1), "CONTAINS": (2, 2), "MATRIX": (2, 12),
                   "NEAREST": (2, 2), "WITHIN": (2, 2), "COMPARE": (2, 2), "CLUSTER": (1, 1)}
SYSTEM_KINDS = ("isolated", "fused", "spiro", "bridged")


def data_lines(filename):
    lines = Path(filename).read_text(encoding="ascii").splitlines()
    return [(number, line) for number, line in enumerate(lines, 1)
            if line and not line.startswith("#")]


def valid_name(value):
    return 1 <= len(value) <= 32 and all(character in NAME_CHARACTERS for character in value)


def valid_number(value, minimum, maximum):
    if not value or not value.isdigit() or len(value) > 1 and value[0] == "0":
        return False
    return minimum <= int(value) <= maximum


def read_threshold(value):
    parts = value.split("/")
    if len(parts) != 2:
        return None
    if not valid_number(parts[0], 0, 99) or not valid_number(parts[1], 1, 99):
        return None
    numerator, denominator = map(int, parts)
    return (numerator, denominator) if numerator <= denominator else None


def fraction_text(value):
    numerator, denominator = value
    divisor = gcd(numerator, denominator)
    return f"{numerator // divisor}/{denominator // divisor}"


def fraction_compare(first, second):
    left = first[0] * second[1]
    right = second[0] * first[1]
    return (left > right) - (left < right)


def atom_numbers(atoms, separator=","):
    return separator.join(str(atom + 1) for atom in atoms)


def member_names(molecules):
    return ",".join(molecule.name for molecule in molecules)


def analyze(molecule):
    find_rings(molecule)
    for bond in molecule.bonds.values():
        if bond.symbol is not None:
            bond.kind = BOND_TYPES[bond.symbol]
        else:
            first, second = bond.ends
            aromatic = molecule.atoms[first].aromatic and molecule.atoms[second].aromatic
            bond.kind = 4 if aromatic and bond.ring else 1
    needing = [number for number in range(len(molecule.atoms)) if needs_pi(molecule, number)]
    kekulize(molecule, needing)
    for number, atom in enumerate(molecule.atoms):
        total = molecule.bond_total(number)
        if atom.bracket:
            if total + atom.hydrogens > atom.element.valences[-1] + abs(atom.charge):
                raise AnalysisError("bad valence", atom.column)
        else:
            hydrogens = organic_hydrogens(atom, total)
            if hydrogens is None:
                raise AnalysisError("bad valence", atom.column)
            atom.hydrogens = hydrogens


def molecular_properties(molecule):
    counts = Counter(atom.element.symbol for atom in molecule.atoms)
    hydrogens = sum(atom.hydrogens for atom in molecule.atoms)
    counts["H"] += hydrogens
    symbols = sorted(symbol for symbol, count in counts.items() if count)
    if counts["C"]:
        symbols.remove("C")
        first = ["C"]
        if "H" in symbols:
            symbols.remove("H")
            first.append("H")
        symbols = first + symbols
    formula = "".join(symbol + (str(counts[symbol]) if counts[symbol] != 1 else "")
                      for symbol in symbols)
    weight = sum(atom.mass * 1000 if atom.mass else atom.element.weight for atom in molecule.atoms)
    weight += hydrogens * molecule.elements["H"].weight
    heavy = sum(atom.element.symbol != "H" for atom in molecule.atoms)
    heavy_degrees = [sum(molecule.atoms[neighbor].element.symbol != "H" for neighbor in neighbors)
                     for neighbors in molecule.neighbors]
    triple_ends = set()
    for bond in molecule.bonds.values():
        if bond.multiplicity == 3:
            triple_ends.update(bond.ends)
    rotatable = 0
    for bond in molecule.bonds.values():
        first, second = bond.ends
        if bond.multiplicity != 1 or bond.ring:
            continue
        if heavy_degrees[first] < 2 or heavy_degrees[second] < 2:
            continue
        if first not in triple_ends and second not in triple_ends:
            rotatable += 1
    donors = acceptors = 0
    for number, atom in enumerate(molecule.atoms):
        if atom.element.symbol in ("N", "O"):
            acceptors += 1
            attached = atom.hydrogens
            attached += sum(molecule.atoms[neighbor].element.symbol == "H"
                            for neighbor in molecule.neighbors[number])
            donors += attached >= 1
    violations = int(weight > 500000) + int(donors > 5) + int(acceptors > 10)
    return {"formula": formula, "weight": weight, "heavy": heavy, "rotatable": rotatable,
            "donors": donors, "acceptors": acceptors, "lipinski": "pass" if violations <= 1 else "fail",
            "charge": sum(atom.charge for atom in molecule.atoms)}


def scaffold_molecule(molecule):
    if not molecule.rings:
        return None
    remaining = set(range(len(molecule.atoms)))
    while True:
        leaf = None
        for atom in sorted(remaining - molecule.ring_atoms):
            degree = sum(neighbor in remaining for neighbor in molecule.neighbors[atom])
            if degree == 1:
                leaf = atom
                break
        if leaf is None:
            break
        remaining.remove(leaf)
    kept = set(remaining)
    for atom in remaining:
        for neighbor, bond in molecule.neighbors[atom].items():
            if neighbor not in remaining and bond.kind == 2:
                kept.add(neighbor)
    scaffold = Molecule(molecule.elements)
    renumber = {}
    for number in sorted(kept):
        original = molecule.atoms[number]
        added_hydrogens = sum(bond.multiplicity for neighbor, bond in molecule.neighbors[number].items()
                              if neighbor not in kept)
        atom = Atom(original.element, original.aromatic, original.mass, original.charge,
                    original.hydrogens + added_hydrogens, original.bracket, original.column)
        renumber[number] = scaffold.add_atom(atom)
    for original in molecule.ordered_bonds():
        first, second = original.ends
        if first in kept and second in kept:
            bond = scaffold.add_bond(renumber[first], renumber[second], original.symbol)
            bond.kind = original.kind
            bond.multiplicity = original.multiplicity
            bond.ring = original.ring
    scaffold.rings = [tuple(renumber[atom] for atom in ring) for ring in molecule.rings]
    scaffold.ring_atoms = {renumber[atom] for atom in molecule.ring_atoms}
    return scaffold


def ring_systems(molecule):
    atom_sets = [set(ring) for ring in molecule.rings]
    connections = [set() for ring in molecule.rings]
    relations = {}
    for first in range(len(atom_sets)):
        for second in range(first + 1, len(atom_sets)):
            shared = atom_sets[first].intersection(atom_sets[second])
            if not shared:
                continue
            connections[first].add(second)
            connections[second].add(first)
            if len(shared) == 1:
                relation = "spiro"
            elif len(shared) == 2:
                atom, neighbor = sorted(shared)
                relation = "fused" if neighbor in molecule.neighbors[atom] else "bridged"
            else:
                relation = "bridged"
            relations[first, second] = relation
    systems = []
    unseen = set(range(len(atom_sets)))
    while unseen:
        start = min(unseen)
        unseen.remove(start)
        component = {start}
        queue = deque([start])
        while queue:
            ring = queue.popleft()
            for neighbor in sorted(connections[ring]):
                if neighbor in unseen:
                    unseen.remove(neighbor)
                    component.add(neighbor)
                    queue.append(neighbor)
        kinds = {kind for (first, second), kind in relations.items()
                 if first in component and second in component}
        if len(component) == 1:
            kind = "isolated"
        elif "bridged" in kinds:
            kind = "bridged"
        elif "fused" in kinds:
            kind = "fused"
        else:
            kind = "spiro"
        atoms = set()
        for ring in component:
            atoms.update(atom_sets[ring])
        systems.append({"rings": sorted(component), "atoms": len(atoms), "kind": kind})
    return systems


def read_molecules(elements, causes):
    molecules = []
    errors = []
    reserved = set()
    lines = data_lines("input/molecules.smi")
    for line_number, line in lines:
        tokens = line.split(" ")
        if len(tokens) != 2 or not tokens[0] or not valid_name(tokens[1]):
            errors.append(f"line {line_number}: bad line")
            causes["bad line"] += 1
            continue
        smiles, name = tokens
        if name in reserved:
            errors.append(f"line {line_number} {name}: duplicate name")
            causes["duplicate name"] += 1
            continue
        reserved.add(name)
        try:
            molecule = parse_smiles(smiles, elements)
            analyze(molecule)
        except AnalysisError as error:
            errors.append(f"line {line_number} {name}: {error.reason} at column {error.column}")
            causes[error.reason] += 1
            continue
        molecule.name = name
        molecule.order = len(molecules)
        molecules.append(molecule)
    paragraph = [f"MOLECULES lines={len(lines)} valid={len(molecules)} errors={len(errors)}"]
    paragraph.extend(errors)
    return molecules, paragraph


def prepare_molecules(molecules):
    for molecule in molecules:
        molecule.properties = molecular_properties(molecule)
        molecule.canonical, molecule.classes = canonicalize(molecule)
        scaffold = scaffold_molecule(molecule)
        molecule.scaffold = canonicalize(scaffold)[0] if scaffold is not None else None
        molecule.systems = ring_systems(molecule)
        molecule.aromatic_rings = [all(molecule.atoms[atom].aromatic for atom in ring)
                                   for ring in molecule.rings]
        molecule.bits, molecule.paths = fingerprint(molecule)


def check_arguments(query, elements, by_name):
    kind, arguments = query["type"], query["arguments"]
    minimum, maximum = ARGUMENT_COUNTS[kind]
    if not minimum <= len(arguments) <= maximum:
        return "bad arguments"
    if kind == "MATCH":
        try:
            query["pattern"] = parse_smiles(arguments[0], elements, read_pattern_atom, pattern=True)
        except AnalysisError as error:
            return f"bad pattern {error.reason} at column {error.column}"
    elif kind == "CLUSTER":
        query["threshold"] = read_threshold(arguments[0])
        if query["threshold"] is None:
            return "bad threshold"
    elif kind in ("CONTAINS", "MATRIX", "COMPARE"):
        for name in arguments:
            if name not in by_name:
                return "unknown molecule " + name
        if len(set(arguments)) != len(arguments):
            return "repeated molecule"
    else:
        if arguments[0] not in by_name:
            return "unknown molecule " + arguments[0]
        if kind == "NEAREST":
            if not valid_number(arguments[1], 1, 99):
                return "bad count"
            query["count"] = int(arguments[1])
        else:
            query["threshold"] = read_threshold(arguments[1])
            if query["threshold"] is None:
                return "bad threshold"
    return None


def query_error(line, kind, identifier, reason, causes):
    if reason == "unknown query":
        text = f"line {line}: unknown query"
    elif reason == "bad id":
        text = f"line {line} {kind}: bad id"
    else:
        text = f"line {line} {kind} {identifier}: {reason}"
    if reason.startswith("bad pattern "):
        cause = "bad pattern"
    elif reason.startswith("unknown molecule "):
        cause = "unknown molecule"
    else:
        cause = reason
    causes[cause] += 1
    return text


def read_queries(elements, by_name, causes):
    queries = []
    errors = []
    reserved = set()
    lines = data_lines("input/queries.txt")
    for line_number, line in lines:
        tokens = line.split(" ")
        kind = tokens[0]
        identifier = tokens[1] if len(tokens) >= 2 else None
        if kind not in ARGUMENT_COUNTS:
            reason = "unknown query"
        elif identifier is None or not valid_name(identifier):
            reason = "bad id"
        elif identifier in reserved:
            reason = "duplicate id"
        else:
            reserved.add(identifier)
            query = {"type": kind, "id": identifier, "arguments": tokens[2:]}
            reason = check_arguments(query, elements, by_name)
            if reason is None:
                queries.append(query)
                continue
        errors.append(query_error(line_number, kind, identifier, reason, causes))
    paragraph = [f"QUERIES lines={len(lines)} valid={len(queries)} errors={len(errors)}"]
    paragraph.extend(errors)
    return queries, paragraph


def properties_lines(molecules):
    lines = ["name,formula,weight,heavy_atoms,rings,rotatable,donors,acceptors,lipinski"]
    for molecule in molecules:
        values = molecule.properties
        weight = values["weight"]
        row = [molecule.name, values["formula"], f"{weight // 1000}.{weight % 1000:03d}",
               str(values["heavy"]), str(len(molecule.rings)), str(values["rotatable"]),
               str(values["donors"]), str(values["acceptors"]), values["lipinski"]]
        lines.append(",".join(row))
    return lines


def canonical_paragraphs(molecules):
    by_canonical = defaultdict(list)
    by_formula = defaultdict(list)
    by_scaffold = defaultdict(list)
    acyclic = 0
    for molecule in molecules:
        by_canonical[molecule.canonical].append(molecule)
        by_formula[molecule.properties["formula"]].append(molecule)
        if molecule.scaffold is None:
            acyclic += 1
        else:
            by_scaffold[molecule.scaffold].append(molecule)
    canonical = [f"CANONICAL molecules={len(molecules)} unique={len(by_canonical)}"]
    for molecule in molecules:
        charge = molecule.properties["charge"]
        text = f"{charge:+d}" if charge else "0"
        canonical.append(f"{molecule.name} {molecule.canonical} classes={molecule.classes} charge={text}")
    groups = [(smiles, members) for smiles, members in by_canonical.items() if len(members) >= 2]
    count = sum(len(members) for smiles, members in groups)
    duplicates = [f"DUPLICATES groups={len(groups)} molecules={count}"]
    for number, (smiles, members) in enumerate(groups, 1):
        duplicates.append(f"group {number} {smiles} members={member_names(members)}")
    groups = []
    for formula, members in by_formula.items():
        forms = len({molecule.canonical for molecule in members})
        if forms >= 2:
            groups.append((formula, members, forms))
    isomers = [f"ISOMERS groups={len(groups)}"]
    for number, (formula, members, forms) in enumerate(groups, 1):
        isomers.append(f"isomer {number} {formula} forms={forms} members={member_names(members)}")
    scaffolds = [f"SCAFFOLDS distinct={len(by_scaffold)} acyclic={acyclic}"]
    groups = sorted(by_scaffold.items(), key=lambda item: (-len(item[1]), item[0]))
    for number, (smiles, members) in enumerate(groups, 1):
        scaffolds.append(f"scaffold {number} {smiles} count={len(members)} members={member_names(members)}")
    return [canonical, duplicates, isomers, scaffolds]


def ring_paragraphs(molecules):
    paragraphs = []
    sizes = Counter()
    kinds = Counter()
    total_aromatic = 0
    total_rings = 0
    for molecule in molecules:
        if not molecule.rings:
            continue
        aromatic = sum(molecule.aromatic_rings)
        total_aromatic += aromatic
        total_rings += len(molecule.rings)
        ring_bonds = sum(bond.ring for bond in molecule.bonds.values())
        paragraph = [f"MOLECULE {molecule.name} atoms={len(molecule.atoms)} bonds={len(molecule.bonds)} "
                     f"rings={len(molecule.rings)} aromatic={aromatic} systems={len(molecule.systems)} "
                     f"ring_atoms={len(molecule.ring_atoms)} ring_bonds={ring_bonds}"]
        for number, ring in enumerate(molecule.rings, 1):
            flag = "yes" if molecule.aromatic_rings[number - 1] else "no"
            hetero = sum(molecule.atoms[atom].element.symbol != "C" for atom in ring)
            paragraph.append(f"ring {number} size={len(ring)} aromatic={flag} hetero={hetero} "
                             f"atoms={atom_numbers(ring, '-')}")
            sizes[len(ring)] += 1
        for number, system in enumerate(molecule.systems, 1):
            kinds[system["kind"]] += 1
            paragraph.append(f"system {number} kind={system['kind']} rings={atom_numbers(system['rings'])} "
                             f"atoms={system['atoms']}")
        double_bonds = [atom_numbers(bond.ends, "=") for bond in molecule.ordered_bonds()
                        if bond.kind == 4 and bond.multiplicity == 2]
        paragraph.append("kekule " + (" ".join(double_bonds) if double_bonds else "-"))
        paragraphs.append(paragraph)
    summary = [f"SUMMARY molecules={len(molecules)} cyclic={len(paragraphs)} rings={total_rings} "
               f"aromatic={total_aromatic}"]
    summary.append("sizes " + (" ".join(f"{size}={sizes[size]}" for size in sorted(sizes)) if sizes else "-"))
    summary.append("systems " + " ".join(f"{kind}={kinds[kind]}" for kind in SYSTEM_KINDS))
    paragraphs.append(summary)
    return paragraphs


def substructure_paragraphs(queries, molecules, by_name):
    paragraphs = []
    patterns = hits = contains = found = 0
    for query in queries:
        kind, identifier, arguments = query["type"], query["id"], query["arguments"]
        if kind == "MATCH":
            patterns += 1
            pattern = query["pattern"]
            matches = []
            for molecule in molecules:
                count, unique, mapping = embeddings(pattern, molecule)
                if count:
                    matches.append((molecule, count, unique, mapping))
            hits += len(matches)
            total = sum(match[1] for match in matches)
            paragraph = [f"MATCH {identifier} {arguments[0]} atoms={len(pattern.atoms)} "
                         f"bonds={len(pattern.bonds)} hits={len(matches)} embeddings={total}"]
            for molecule, count, unique, mapping in matches:
                paragraph.append(f"{molecule.name} count={count} unique={unique} map={atom_numbers(mapping)}")
            if matches:
                top = max(matches, key=lambda match: match[1])
                paragraph.append(f"top {top[0].name} count={top[1]}")
            paragraphs.append(paragraph)
        elif kind == "CONTAINS":
            contains += 1
            first, second = (by_name[name] for name in arguments)
            count, unique, mapping = embeddings(molecule_pattern(first), second)
            text = f"CONTAINS {identifier} {first.name} {second.name} result="
            if count:
                found += 1
                text += f"yes count={count} unique={unique} map={atom_numbers(mapping)}"
            else:
                text += "no"
            paragraphs.append([text])
    paragraphs.append([f"SUMMARY patterns={patterns} hits={hits} contains={contains} found={found}"])
    return paragraphs


class Similarities:
    def __init__(self):
        self.cache = {}

    def get(self, first, second):
        key = tuple(sorted((first.order, second.order)))
        if key not in self.cache:
            self.cache[key] = tanimoto(first.bits, second.bits)
        return self.cache[key]


def matrix_paragraph(query, by_name, similarities):
    molecules = [by_name[name] for name in query["arguments"]]
    paragraph = [f"MATRIX {query['id']} size={len(molecules)}"]
    for first in molecules:
        row = [fraction_text(similarities.get(first, second)) for second in molecules]
        paragraph.append("row " + first.name + " " + " ".join(row))
    best_first, best_second = molecules[0], molecules[1]
    best = similarities.get(best_first, best_second)
    for index, first in enumerate(molecules):
        for second in molecules[index + 1:]:
            value = similarities.get(first, second)
            if fraction_compare(value, best) > 0:
                best_first, best_second, best = first, second, value
    paragraph.append(f"best {best_first.name} {best_second.name} {fraction_text(best)}")
    return paragraph


def ranked_neighbors(source, molecules, similarities):
    neighbors = [(molecule, similarities.get(source, molecule)) for molecule in molecules if molecule is not source]

    def compare(first, second):
        difference = fraction_compare(second[1], first[1])
        if difference:
            return difference
        return first[0].order - second[0].order

    return sorted(neighbors, key=cmp_to_key(compare))


def neighbors_paragraph(query, molecules, by_name, similarities):
    source = by_name[query["arguments"][0]]
    neighbors = ranked_neighbors(source, molecules, similarities)
    if query["type"] == "NEAREST":
        result = neighbors[:query["count"]]
        heading = f"NEAREST {query['id']} {source.name} count={len(result)}"
    else:
        threshold = query["threshold"]
        result = [(molecule, value) for molecule, value in neighbors if fraction_compare(value, threshold) >= 0]
        heading = f"WITHIN {query['id']} {source.name} threshold={fraction_text(threshold)} count={len(result)}"
    paragraph = [heading]
    for number, (molecule, value) in enumerate(result, 1):
        paragraph.append(f"{number} {molecule.name} {fraction_text(value)} common={value[0]}")
    return paragraph


def compare_paragraph(query, by_name, similarities):
    first, second = (by_name[name] for name in query["arguments"])
    value = similarities.get(first, second)
    identical = "yes" if first.canonical == second.canonical else "no"
    return [f"COMPARE {query['id']} {first.name} {second.name} bits={len(first.bits)},{len(second.bits)} "
            f"common={value[0]} union={value[1]} tanimoto={fraction_text(value)} identical={identical}"]


def cluster_paragraph(query, molecules, similarities):
    threshold = query["threshold"]
    neighbors = []
    for first in molecules:
        neighbors.append([second.order for second in molecules if second is not first
                          and fraction_compare(similarities.get(first, second), threshold) >= 0])
    order = sorted(range(len(molecules)), key=lambda number: (-len(neighbors[number]), number))
    assigned = set()
    clusters = []
    for center in order:
        if center in assigned:
            continue
        members = [center] + [neighbor for neighbor in neighbors[center] if neighbor not in assigned]
        clusters.append(members)
        assigned.update(members)
    singletons = sum(len(members) == 1 for members in clusters)
    paragraph = [f"CLUSTER {query['id']} threshold={fraction_text(threshold)} "
                 f"clusters={len(clusters)} singletons={singletons}"]
    number = 0
    for members in clusters:
        if len(members) == 1:
            continue
        number += 1
        selected = [molecules[index] for index in members]
        paragraph.append(f"cluster {number} centroid={selected[0].name} size={len(selected)} "
                         f"members={member_names(selected)}")
    return paragraph


def similarity_paragraphs(queries, molecules, by_name):
    fingerprints = [f"FINGERPRINTS molecules={len(molecules)} size=1024 depth=5"]
    fingerprints.extend(f"{molecule.name} bits={len(molecule.bits)} paths={molecule.paths}" for molecule in molecules)
    paragraphs = [fingerprints]
    similarities = Similarities()
    for query in queries:
        kind = query["type"]
        if kind == "MATRIX":
            paragraph = matrix_paragraph(query, by_name, similarities)
        elif kind in ("NEAREST", "WITHIN"):
            paragraph = neighbors_paragraph(query, molecules, by_name, similarities)
        elif kind == "COMPARE":
            paragraph = compare_paragraph(query, by_name, similarities)
        elif kind == "CLUSTER":
            paragraph = cluster_paragraph(query, molecules, similarities)
        else:
            continue
        paragraphs.append(paragraph)
    return paragraphs


def causes_paragraph(causes):
    paragraph = [f"CAUSES kinds={len(causes)}"]
    for reason, count in sorted(causes.items(), key=lambda item: (-item[1], item[0])):
        paragraph.append(f"{reason}={count}")
    return paragraph


def paragraphs_text(paragraphs):
    return "\n\n".join("\n".join(paragraph) for paragraph in paragraphs) + "\n"


def main():
    elements = read_elements("input/elements.txt")
    causes = Counter()
    molecules, molecule_errors = read_molecules(elements, causes)
    prepare_molecules(molecules)
    by_name = {molecule.name: molecule for molecule in molecules}
    queries, query_errors = read_queries(elements, by_name, causes)
    outputs = {"properties.csv": "\n".join(properties_lines(molecules)) + "\n",
               "canonical.txt": paragraphs_text(canonical_paragraphs(molecules)),
               "rings.txt": paragraphs_text(ring_paragraphs(molecules)),
               "substructure.txt": paragraphs_text(substructure_paragraphs(queries, molecules, by_name)),
               "similarity.txt": paragraphs_text(similarity_paragraphs(queries, molecules, by_name)),
               "errors.txt": paragraphs_text([molecule_errors, query_errors, causes_paragraph(causes)])}
    directory = Path("output")
    directory.mkdir(exist_ok=True)
    for filename, content in outputs.items():
        (directory / filename).write_text(content, encoding="ascii", newline="\n")


if __name__ == "__main__":
    main()
