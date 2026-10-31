import Foundation
struct Parsed {
    let molecule: Molecule, matchers: [Matcher]
}
enum SmilesParser {
    static func organic(_ text: [UInt8]) -> (String, Bool, Int)? {
        if text.starts(with: [67, 108]) {
            return ("Cl", false, 2)
        }
        if text.starts(with: [66, 114]) {
            return ("Br", false, 2)
        }
        guard let c = text.first else {
            return nil
        }
        if Array("BCNOPSFI".utf8).contains(c) {
            return (String(UnicodeScalar(c)), false, 1)
        }
        if Array("bcnops".utf8).contains(c) {
            return (String(UnicodeScalar(c - 32)), true, 1)
        }
        return nil
    }
    static func atom(_ text: [UInt8], _ column: Int, _ elements: Elements) throws -> (Atom, Int) {
        if text[0] != 91 {
            guard let (element, aromatic, n) = organic(text) else {
                throw MoleculeError("unexpected character", column)
            }
            return (Atom(element: element, aromatic: aromatic, mass: 0, charge: 0, hydrogens: 0, bracket: false, column: column), n)
        }
        guard let end = text.firstIndex(of: 93) else {
            throw MoleculeError("unclosed bracket", column)
        }
        let s = Array(text[1..<end])
        var i = 0
        while i < s.count && (48...57).contains(s[i]) {
            i += 1
        }
        if i >= 4 || i > 0 && s[0] == 48 {
            throw MoleculeError("bad bracket atom", column)
        }
        let mass = i == 0 ? 0 : Int(String(bytes: s[..<i], encoding: .ascii)!)!
        if i == s.count {
            throw MoleculeError("bad bracket atom", column)
        }
        let element: String, aromatic: Bool
        if Array("bcnops".utf8).contains(s[i]) {
            element = String(UnicodeScalar(s[i] - 32));
            aromatic = true;
            i += 1
        }
        else if (65...90).contains(s[i]) {
            let one = String(UnicodeScalar(s[i]))
            if i + 1 < s.count && (97...122).contains(s[i + 1]), let two = String(bytes: s[i...i + 1], encoding: .ascii), elements[two] != nil {
                element = two;
                i += 2
            }
            else if elements[one] != nil {
                element = one;
                i += 1
            }
            else {
                throw MoleculeError("unknown element", column)
            }
            aromatic = false
        } else {
            throw MoleculeError("bad bracket atom", column)
        }
        if i < s.count && s[i] == 64 {
            i += 1;
            if i < s.count && s[i] == 64 {
                i += 1
            }
        }
        var hydrogens = 0
        if i < s.count && s[i] == 72 {
            hydrogens = 1;
            i += 1;
            if i < s.count && (48...57).contains(s[i]) {
                hydrogens = Int(s[i] - 48);
                i += 1
            }
        }
        var charge = 0
        if i < s.count && (s[i] == 43 || s[i] == 45) {
            let sign = s[i] == 43 ? 1 : -1
            i += 1
            var amount = 1
            if i < s.count && (49...57).contains(s[i]) {
                amount = Int(s[i] - 48);
                i += 1
            }
            charge = sign * amount
        }
        if i != s.count {
            throw MoleculeError("bad bracket atom", column)
        }
        return (Atom(element: element, aromatic: aromatic, mass: mass, charge: charge, hydrogens: hydrogens, bracket: true, column: column), end + 1)
    }
    static func symbol(_ c: UInt8, _ pattern: Bool) -> Int? {
        switch c {
            case 45: return 1
            case 61: return 2
            case 35: return 3
            case 58: return 4
            case 126 where pattern: return 5
            case 47, 92: return pattern ? nil : 1
            default: return nil
        }
    }
    static func parse(_ text: String, _ elements: Elements, pattern: Bool = false) throws -> Parsed {
        let s = Array(text.utf8), molecule = Molecule()
        var matchers: [Matcher] = [], current: Int?, pending: (Int, Int)?, branches: [(Int, Int)] = []
        var rings: [Int: (Int, (Int, Int)?, Int)] = [:], i = 0
        func add(_ a: Int, _ b: Int, _ kind: Int) {
            molecule.bonds.append(Bond(a: min(a, b), b: max(a, b), kind: kind))
        }
        while i < s.count {
            let c = s[i], column = i + 1
            if let kind = symbol(c, pattern) {
                if current == nil || pending != nil {
                    throw MoleculeError("misplaced bond", column)
                }
                pending = (kind, column);
                i += 1
            } else if c == 40 {
                if current == nil || pending != nil || i > 0 && s[i - 1] == 40 {
                    throw MoleculeError("misplaced branch", column)
                }
                branches.append((current!, column));
                i += 1
            } else if c == 41 {
                if branches.isEmpty {
                    throw MoleculeError("unmatched parenthesis", column)
                }
                if let pending {
                    throw MoleculeError("dangling bond", pending.1)
                }
                if i > 0 && s[i - 1] == 40 {
                    throw MoleculeError("empty branch", column)
                }
                current = branches.removeLast().0;
                i += 1
            } else if (48...57).contains(c) || c == 37 {
                guard let atom = current else {
                    throw MoleculeError("misplaced ring closure", column)
                }
                let number: Int
                if c == 37 {
                    if i + 2 >= s.count || !(48...57).contains(s[i + 1]) || !(48...57).contains(s[i + 2]) {
                        throw MoleculeError("bad ring number", column)
                    }
                    number = Int(s[i + 1] - 48) * 10 + Int(s[i + 2] - 48);
                    i += 3
                } else {
                    number = Int(c - 48);
                    i += 1
                }
                let closing = pending
                pending = nil
                if let (opening, kind, _) = rings.removeValue(forKey: number) {
                    if opening == atom {
                        throw MoleculeError("self bond", column)
                    }
                    if let kind, let closing, kind.0 != closing.0 {
                        throw MoleculeError("ring bond mismatch", column)
                    }
                    if molecule.bonds.contains(where: {
                        $0.a == min(opening, atom) && $0.b == max(opening, atom)
                    }) {
                        throw MoleculeError("duplicate bond", column)
                    }
                    add(opening, atom, (closing ?? kind)?.0 ?? 0)
                } else {
                    rings[number] = (atom, closing, column)
                }
            } else {
                let parsedAtom: (Atom, Int)
                if pattern {
                    let (matcher, n) = try Search.patternAtom(Array(s[i...]), column)
                    matchers.append(matcher)
                    parsedAtom = (Atom(element: "", aromatic: false, mass: 0, charge: 0, hydrogens: 0, bracket: false, column: column), n)
                } else {
                    parsedAtom = try self.atom(Array(s[i...]), column, elements)
                }
                let (atom, length) = parsedAtom
                let next = molecule.atoms.count
                molecule.atoms.append(atom)
                if let current {
                    add(current, next, pending?.0 ?? 0)
                }
                current = next;
                pending = nil;
                i += length
            }
        }
        if let pending {
            throw MoleculeError("dangling bond", pending.1)
        }
        if let branch = branches.first {
            throw MoleculeError("unmatched parenthesis", branch.1)
        }
        if let column = rings.values.map({
            $0.2
        }).min() {
            throw MoleculeError("unclosed ring", column)
        }
        molecule.rebuild()
        return Parsed(molecule: molecule, matchers: matchers)
    }
}
