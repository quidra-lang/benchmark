enum Charset {
    static func letter(_ c: Int) -> Bool {
        (65...90).contains(c) || (97...122).contains(c)
    }
    static func digit(_ c: Int) -> Bool {
        (48...57).contains(c)
    }
    static func word(_ c: Int) -> Bool {
        letter(c) || digit(c) || c == 95
    }
    static func swap(_ c: Int) -> Int {
        (97...122).contains(c) ? c - 32 : (65...90).contains(c) ? c + 32 : c
    }
    static func equal(_ a: Int, _ b: Int, _ flags: Flags) -> Bool {
        a == b || flags.i && letter(a) && swap(a) == b
    }
    static func base(_ c: Int) -> Set<Int> {
        let lower = (65...90).contains(c) ? c + 32 : c
        let set = Set((0..<128).filter {
            lower == 100 ? digit($0) : lower == 119 ? word($0) : [9, 10, 11, 12, 13, 32].contains($0)
        });
        return (65...90).contains(c) ? Set(0..<128).subtracting(set) : set
    }
    static func classMatches(_ c: Int, _ set: Set<Int>, _ negated: Bool, _ flags: Flags) -> Bool {
        (set.contains(c) || flags.i && letter(c) && set.contains(swap(c))) != negated
    }
    static func assertion(_ kind: String, _ subject: [Int], _ q: Int, _ flags: Flags) -> Bool {
        if kind == "BOL" {
            return q == 0 || flags.m && subject[q - 1] == 10
        }
        if kind == "EOL" {
            return q == subject.count || flags.m && subject[q] == 10
        }
        let left = q > 0 && word(subject[q - 1]), right = q < subject.count && word(subject[q]);
        return (left != right) == (kind == "WORD")
    }
}
