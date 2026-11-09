import Foundation
enum Matcher {
    case any, aliphatic, aromatic, list([(String, Bool)])
}
struct Pattern {
    let graph: Molecule, atoms: [Matcher]
    static func parse(_ text: String, _ elements: Elements) throws -> Self {
        let parsed = try SmilesParser.parse(text, elements, pattern: true)
        return Self(graph: parsed.molecule, atoms: parsed.matchers)
    }
    static func molecule(_ molecule: Molecule) -> Self {
        Self(graph: molecule, atoms: molecule.atoms.map {
            .list([($0.element, $0.aromatic)])
        })
    }
}
struct Matches {
    let count: Int, unique: Int, first: [Int]
}
struct Fingerprint {
    var bits: Set<Int> = [];
    var paths = 0
}
enum Search {
    static func patternAtom(_ s: [UInt8], _ column: Int) throws -> (Matcher, Int) {
        switch s[0] {
            case 42: return (.any, 1)
            case 65: return (.aliphatic, 1)
            case 97: return (.aromatic, 1)
            case 91:
            guard let end = s.firstIndex(of: 93) else {
                throw MoleculeError("unclosed bracket", column)
            }
            if end == 1 {
                throw MoleculeError("bad bracket atom", column)
            }
            var list: [(String, Bool)] = []
            for part in s[1..<end].split(separator: 44, omittingEmptySubsequences: false) {
                guard let (element, aromatic, n) = SmilesParser.organic(Array(part)), n == part.count else {
                    throw MoleculeError("bad bracket atom", column)
                }
                list.append((element, aromatic))
            }
            return (.list(list), end + 1)
            default:
            guard let (element, aromatic, n) = SmilesParser.organic(s) else {
                throw MoleculeError("unexpected character", column)
            }
            return (.list([(element, aromatic)]), n)
        }
    }
    static func embeddings(_ pattern: Pattern, _ molecule: Molecule) -> Matches {
        var map: [Int] = [], used: Set<Int> = [], count = 0, sets: Set<[Int]> = [], first: [Int] = []
        func visit() {
            let a = map.count
            if a == pattern.atoms.count {
                count += 1
                if first.isEmpty {
                    first = map.map {
                        $0 + 1
                    }
                }
                sets.insert(map.sorted())
                return
            }
            for b in molecule.atoms.indices where !used.contains(b) {
                let atom = molecule.atoms[b], matches: Bool
                switch pattern.atoms[a] {
                    case .any: matches = true
                    case .aliphatic: matches = !atom.aromatic
                    case .aromatic: matches = atom.aromatic
                    case .list(let list): matches = list.contains {
                        $0.0 == atom.element && $0.1 == atom.aromatic
                    }
                }
                if !matches {
                    continue
                }
                let bonds = pattern.graph.neighbors[a].filter {
                    $0.0 < a
                }.allSatisfy {
                    v, edge in
                    guard let f = molecule.bond(b, map[v]) else {
                        return false
                    }
                    switch pattern.graph.bonds[edge].kind {
                        case 0: return molecule.bonds[f].kind == 1 || molecule.bonds[f].kind == 4
                        case 5: return true
                        case let kind: return molecule.bonds[f].kind == kind
                    }
                }
                if bonds {
                    used.insert(b);
                    map.append(b);
                    visit();
                    map.removeLast();
                    used.remove(b)
                }
            }
        }
        visit()
        return Matches(count: count, unique: sets.count, first: first)
    }
    static func fingerprint(_ molecule: Molecule, _ elements: Elements) -> Fingerprint {
        let codes = molecule.atoms.enumerated().map {
            16 * elements[$0.element.element]!.number + ($0.element.aromatic ? 8 : 0) + molecule.neighbors[$0.offset].count
        }
        var result = Fingerprint(), path: [Int] = []
        func walk(_ hash: Int) {
            result.paths += 1;
            result.bits.insert(hash % 1024)
            if path.count == 6 {
                return
            }
            let a = path.last!
            for (b, edge) in molecule.neighbors[a] where !path.contains(b) {
                let h = ((hash * 31 + molecule.bonds[edge].kind) % 1000003 * 31 + codes[b]) % 1000003
                path.append(b);
                walk(h);
                path.removeLast()
            }
        }
        for i in molecule.atoms.indices {
            path = [i];
            walk(codes[i])
        }
        return result
    }
    static func similarity(_ a: Fingerprint, _ b: Fingerprint) -> (Int, Int) {
        let common = a.bits.intersection(b.bits).count
        return (common, a.bits.count + b.bits.count - common)
    }
}
