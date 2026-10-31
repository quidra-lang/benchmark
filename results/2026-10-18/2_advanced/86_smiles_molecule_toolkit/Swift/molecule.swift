import Foundation
struct Element {
    let number: Int, mass: Int, valences: [Int]
}
typealias Elements = [String: Element]
func readElements() -> Elements {
    var table: Elements = [:]
    let text = try! String(contentsOfFile: "input/elements.txt", encoding: .ascii)
    for line in text.split(separator: "\n") where line.first != "#" {
        let a = line.split(separator: " ").map(String.init)
        table[a[0]] = Element(number: Int(a[1])!, mass: Int(a[2])!, valences: a[3].split(separator: ",").map {
            Int($0)!
        })
    }
    return table
}
struct Atom {
    let element: String, aromatic: Bool, mass: Int, charge: Int
    var hydrogens: Int
    let bracket: Bool, column: Int
}
struct Bond {
    var a: Int, b: Int, kind: Int, multiplicity = 0, ring = false
}
final class Molecule {
    var atoms: [Atom] = [], bonds: [Bond] = [], neighbors: [[(Int, Int)]] = [], rings: [[Int]] = []
    func rebuild() {
        bonds.sort {
            ($0.a, $0.b) < ($1.a, $1.b)
        }
        neighbors = Array(repeating: [], count: atoms.count)
        for (i, bond) in bonds.enumerated() {
            neighbors[bond.a].append((bond.b, i));
            neighbors[bond.b].append((bond.a, i))
        }
        for i in neighbors.indices {
            neighbors[i].sort {
                $0.0 < $1.0
            }
        }
    }
    func bond(_ a: Int, _ b: Int) -> Int? {
        neighbors[a].first {
            $0.0 == b
        }?.1
    }
    func base(_ i: Int) -> Int {
        neighbors[i].reduce(0) {
            $0 + (bonds[$1.1].kind == 4 ? 1 : bonds[$1.1].kind)
        }
    }
    func multiplicity(_ i: Int) -> Int {
        neighbors[i].reduce(0) {
            $0 + bonds[$1.1].multiplicity
        }
    }
    func needsPi(_ i: Int, _ elements: Elements, _ hydrogens: Bool) -> Bool {
        let atom = atoms[i], required = base(i) + (hydrogens ? atom.hydrogens : 0) + 1
        return atom.aromatic && elements[atom.element]!.valences[0] + atom.charge >= required
    }
    func organicHydrogens(_ i: Int, _ elements: Elements) -> Int? {
        let total = multiplicity(i)
        return elements[atoms[i].element]!.valences.first {
            $0 >= total
        }.map {
            $0 - total
        }
    }
}
struct MoleculeError: Error {
    let reason: String, column: Int;
    init(_ reason: String, _ column: Int) {
        self.reason = reason;
        self.column = column
    }
}
