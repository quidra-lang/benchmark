enum Simplex {
    static func phase(_ tableau: inout Tableau, _ costs: [F], _ candidates: [Int], _ columns: [String], _ rows: [String], _ constant: F, _ sign: F, _ level: Int, _ log: inout [String]) -> (Int, Int?) {
        var iterations = 0
        while true {
            let reduced = tableau.reduced(costs)
            guard let q = candidates.first(where: {
                reduced[$0] < F(0)
            }) else {
                return (iterations, nil)
            }
            let p = tableau.t.indices.filter {
                tableau.t[$0][q] > F(0)
            }.min {
                let a = tableau.beta[$0] / tableau.t[$0][q], b = tableau.beta[$1] / tableau.t[$1][q]
                return a == b ? tableau.basis[$0] < tableau.basis[$1] : a < b
            }
            guard let p else {
                return (iterations, q)
            }
            let leaving = tableau.basis[p], ratio = tableau.beta[p] / tableau.t[p][q], value = reduced[q]
            tableau.pivot(p, q);
            iterations += 1
            if level >= 1 {
                log.append("PIVOT \(iterations) enter \(columns[q]) reduced \(value) leave \(columns[leaving]) row \(rows[p]) ratio \(ratio) objective \(constant + sign * tableau.value(costs))")
            }
        }
    }
}
