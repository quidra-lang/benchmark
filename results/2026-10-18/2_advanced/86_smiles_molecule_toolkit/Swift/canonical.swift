enum Canonical {
    static func dense(_ values: [[Int]]) -> [Int] {
        let sorted = Set(values).sorted {
            $0.lexicographicallyPrecedes($1)
        }
        let ranks = Dictionary(uniqueKeysWithValues: sorted.enumerated().map {
            ($0.element, $0.offset + 1)
        })
        return values.map {
            ranks[$0]!
        }
    }
    static func refine(_ molecule: Molecule, _ input: [Int]) -> [Int] {
        var ranks = input
        while true {
            let classes = Set(ranks).count
            let values = molecule.atoms.indices.map {
                i -> [Int] in
                let neighbors = molecule.neighbors[i].map {
                    (ranks[$0.0], molecule.bonds[$0.1].kind)
                }.sorted {
                    $0 < $1
                }
                return [ranks[i]] + neighbors.flatMap {
                    [$0.0, $0.1]
                }
            }
            ranks = dense(values)
            if Set(ranks).count == classes {
                return ranks
            }
        }
    }
    static func ranks(_ molecule: Molecule, _ elements: Elements) -> ([Int], Int) {
        let values = molecule.atoms.enumerated().map {
            i, atom in
            [molecule.neighbors[i].count, elements[atom.element]!.number, atom.mass, atom.charge, atom.hydrogens, atom.aromatic ? 1 : 0]
        }
        var ranks = refine(molecule, dense(values))
        let classes = Set(ranks).count
        while Set(ranks).count < molecule.atoms.count {
            var counts: [Int: Int] = [:]
            for rank in ranks {
                counts[rank, default: 0] += 1
            }
            let tied = counts.keys.filter {
                counts[$0]! > 1
            }.min()!, atom = ranks.firstIndex(of: tied)!
            var values = ranks.map {
                $0 * 2
            }
            values[atom] -= 1
            ranks = refine(molecule, dense(values.map {
                [$0]
            }))
        }
        return (ranks, classes)
    }
    static func atom(_ molecule: Molecule, _ i: Int, _ elements: Elements) -> String {
        let atom = molecule.atoms[i], symbol = atom.aromatic ? atom.element.lowercased() : atom.element
        let allowed = ["B", "C", "N", "O", "P", "S", "F", "Cl", "Br", "I"].contains(atom.element) && (!atom.aromatic || ["B", "C", "N", "O", "P", "S"].contains(atom.element))
        let simple = allowed && atom.mass == 0 && atom.charge == 0 && (!atom.aromatic || molecule.needsPi(i, elements, true) == molecule.needsPi(i, elements, false)) && molecule.organicHydrogens(i, elements) == atom.hydrogens
        if simple {
            return symbol
        }
        var text = "["
        if atom.mass != 0 {
            text += String(atom.mass)
        }
        text += symbol
        if atom.hydrogens > 0 {
            text += "H";
            if atom.hydrogens > 1 {
                text += String(atom.hydrogens)
            }
        }
        if atom.charge != 0 {
            text += atom.charge > 0 ? "+" : "-";
            if abs(atom.charge) > 1 {
                text += String(abs(atom.charge))
            }
        }
        return text + "]"
    }
    static func bond(_ molecule: Molecule, _ edge: Int) -> String {
        let bond = molecule.bonds[edge], aromatic = molecule.atoms[bond.a].aromatic && molecule.atoms[bond.b].aromatic && bond.ring
        switch bond.kind {
            case 1: return aromatic ? "-" : ""
            case 2: return "="
            case 3: return "#"
            default: return aromatic ? "" : ":"
        }
    }
    static func smiles(_ molecule: Molecule, _ elements: Elements) -> (String, Int) {
        let (ranks, classes) = self.ranks(molecule, elements), start = ranks.firstIndex(of: 1)!
        var visited = Array(repeating: 0, count: molecule.atoms.count), kind = Array(repeating: 0, count: molecule.bonds.count)
        var children = Array(repeating: [(Int, Int)](), count: molecule.atoms.count), serial = 0, assigned: [Int: Int] = [:]
        func visit(_ a: Int, _ incoming: Int?) {
            serial += 1;
            visited[a] = serial
            let neighbors = molecule.neighbors[a].sorted {
                ranks[$0.0] < ranks[$1.0]
            }
            for (b, edge) in neighbors {
                if edge == incoming || kind[edge] == 2 {
                    continue
                }
                if visited[b] == 0 {
                    kind[edge] = 1;
                    children[a].append((b, edge));
                    visit(b, edge)
                }
                else {
                    kind[edge] = 2
                }
            }
        }
        func write(_ a: Int) -> String {
            var text = atom(molecule, a, elements)
            let closures = molecule.neighbors[a].filter {
                kind[$0.1] == 2
            }.sorted {
                visited[$0.0] < visited[$1.0]
            }
            for (_, edge) in closures {
                let number: Int
                if let old = assigned.removeValue(forKey: edge) {
                    number = old
                }
                else {
                    var next = 1
                    while assigned.values.contains(next) {
                        next += 1
                    }
                    number = next;
                    assigned[edge] = next;
                    text += bond(molecule, edge)
                }
                text += number < 10 ? String(number) : "%" + String(number)
            }
            for (i, child) in children[a].enumerated() {
                let branch = i + 1 < children[a].count
                if branch {
                    text += "("
                }
                text += bond(molecule, child.1) + write(child.0)
                if branch {
                    text += ")"
                }
            }
            return text
        }
        visit(start, nil)
        return (write(start), classes)
    }
}
