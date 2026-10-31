struct Tableau {
    var t: [[F]], beta: [F], basis: [Int]
    func reduced(_ costs: [F]) -> [F] {
        costs.indices.map {
            k in costs[k] - t.indices.reduce(F(0)) {
                $0 + costs[basis[$1]] * t[$1][k]
            }
        }
    }
    func value(_ costs: [F]) -> F {
        t.indices.reduce(F(0)) {
            $0 + costs[basis[$1]] * beta[$1]
        }
    }
    mutating func pivot(_ p: Int, _ q: Int) {
        let value = t[p][q]
        t[p] = t[p].map {
            $0 / value
        };
        beta[p] = beta[p] / value
        let row = t[p], pivotBeta = self.beta[p]
        for i in t.indices where i != p {
            let factor = t[i][q]
            for k in row.indices {
                t[i][k] = t[i][k] - factor * row[k]
            }
            self.beta[i] = self.beta[i] - factor * pivotBeta
        }
        basis[p] = q
    }
    func display(_ heading: String, _ columns: [String], _ rows: [String], _ costs: [F], _ constant: F, _ sign: F) -> [String] {
        var lines = ["TABLEAU \(heading)", "COLUMNS " + columns.joined(separator: " ")]
        for i in t.indices {
            lines.append("ROW \(rows[i]) \(columns[basis[i]]) " + t[i].map(\.description).joined(separator: " ") + " | \(beta[i])")
        }
        lines.append("COST " + reduced(costs).map(\.description).joined(separator: " ") + " | \(constant + sign * value(costs))")
        return lines
    }
}
