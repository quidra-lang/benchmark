enum RingsAromatic {
    static func edgeSet(_ molecule: Molecule, _ ring: [Int]) -> Set<Int> {
        Set(ring.indices.map {
            molecule.bond(ring[$0], ring[($0 + 1) % ring.count])!
        })
    }
    static func detect(_ molecule: Molecule) {
        let n = molecule.atoms.count
        var candidates: [([Int], Set<Int>, Int)] = [], seen: Set<Set<Int>> = []
        for root in 0..<n {
            var parent = Array<Int?>(repeating: nil, count: n), visited = Array(repeating: false, count: n), queue = [root], head = 0
            visited[root] = true
            while head < queue.count {
                let a = queue[head];
                head += 1
                for (b, _) in molecule.neighbors[a] where !visited[b] {
                    visited[b] = true;
                    parent[b] = a;
                    queue.append(b)
                }
            }
            func path(_ atom: Int) -> [Int] {
                var x = atom, result = [atom]
                while let a = parent[x] {
                    result.append(a);
                    x = a
                }
                return result
            }
            for bond in molecule.bonds {
                let x = bond.a, y = bond.b
                if parent[x] == y || parent[y] == x {
                    continue
                }
                let a = path(x), b = path(y)
                if a.contains(where: {
                    $0 != root && b.contains($0)
                }) {
                    continue
                }
                let ring = Array(a.reversed()) + b.dropLast(), edges = edgeSet(molecule, ring)
                if seen.insert(edges).inserted {
                    candidates.append((ring, edges, candidates.count))
                }
            }
        }
        candidates.sort {
            $0.0.count == $1.0.count ? $0.2 < $1.2 : $0.0.count < $1.0.count
        }
        var basis: [Int: Set<Int>] = [:], selected: [[Int]] = []
        for (ring, edges, _) in candidates {
            var vector = edges
            while let pivot = vector.max() {
                if let b = basis[pivot] {
                    vector.formSymmetricDifference(b)
                }
                else {
                    basis[pivot] = vector;
                    selected.append(ring);
                    break
                }
            }
        }
        selected = selected.map {
            ring in
            let k = ring.firstIndex(of: ring.min()!)!
            var ring = Array(ring[k...]) + ring[..<k]
            if ring[1] > ring.last! {
                ring = [ring[0]] + ring.dropFirst().reversed()
            }
            return ring
        }.sorted {
            $0.count == $1.count ? $0.lexicographicallyPrecedes($1) : $0.count < $1.count
        }
        for ring in selected {
            for edge in edgeSet(molecule, ring) {
                molecule.bonds[edge].ring = true
            }
        }
        molecule.rings = selected
    }
    static func kekulize(_ molecule: Molecule, _ elements: Elements) throws {
        var remaining = Set(molecule.atoms.indices.filter {
            molecule.needsPi($0, elements, true)
        }), paired: [Int: Int] = [:]
        func matching(_ system: Set<Int>) -> Bool {
            guard let u = system.filter({
                paired[$0] == nil
            }).min() else {
                return true
            }
            for (v, edge) in molecule.neighbors[u] where system.contains(v) && paired[v] == nil && molecule.bonds[edge].kind == 4 {
                paired[u] = v;
                paired[v] = u
                if matching(system) {
                    return true
                }
                paired.removeValue(forKey: u);
                paired.removeValue(forKey: v)
            }
            return false
        }
        while let start = remaining.min() {
            var system: Set<Int> = [], stack = [start]
            remaining.remove(start)
            while let a = stack.popLast() {
                system.insert(a)
                for (b, edge) in molecule.neighbors[a] where molecule.bonds[edge].kind == 4 {
                    if remaining.remove(b) != nil {
                        stack.append(b)
                    }
                }
            }
            if !matching(system) {
                throw MoleculeError("kekulization failed", molecule.atoms[system.min()!].column)
            }
        }
        for i in molecule.bonds.indices {
            let bond = molecule.bonds[i]
            molecule.bonds[i].multiplicity = bond.kind == 4 ? (paired[bond.a] == bond.b ? 2 : 1) : bond.kind
        }
    }
}
