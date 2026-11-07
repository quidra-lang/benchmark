import Foundation

struct Factor {
    let name: String
    let column: String
    let power: Int
    let categorical: Bool

    init(_ name: String) {
        self.name = name
        categorical = name.hasPrefix("C(")
        if categorical {
            column = String(name.dropFirst(2).dropLast())
            power = 1
        } else if name.hasPrefix("I(") {
            let parts = name.dropFirst(2).dropLast().split(separator: "^")
            column = String(parts[0])
            power = Int(parts[1])!
        } else { column = name; power = 1 }
    }

    func value(_ row: Record, level: String?) -> Double {
        if categorical { return row[column]!.labelValue! == level! ? 1 : 0 }
        let value = row[column]!.numericValue!
        if power == 2 { return value * value }
        if power == 3 { return value * value * value }
        return value
    }

    func components(_ levels: [String: [String]]) -> [FactorComponent] {
        if categorical { return levels[column]!.dropFirst().map { FactorComponent(factor: self, name: name + $0, level: $0) } }
        return [FactorComponent(factor: self, name: name, level: nil)]
    }
}

struct FactorComponent {
    let factor: Factor
    let name: String
    let level: String?
}

struct Term {
    let factors: [Factor]
    var name: String { factors.map { $0.name }.joined(separator: ":") }
    var factorNames: Set<String> { Set(factors.map { $0.name }) }
    func contained(in other: Term) -> Bool { factorNames.isStrictSubset(of: other.factorNames) }
}

func combinations(_ count: Int, _ size: Int) -> [[Int]] {
    var result: [[Int]] = []
    func visit(_ chosen: [Int], _ start: Int) {
        if chosen.count == size { result.append(chosen); return }
        if start >= count { return }
        for index in start..<count { visit(chosen + [index], index + 1) }
    }
    visit([], 0)
    return result
}

struct Model {
    let original: String
    let response: String
    let weight: String?
    let terms: [Term]
    let factorColumns: [String]
    let categoricalColumns: [String]
    let variables: Set<String>

    init(_ line: String) {
        let pieces = line.components(separatedBy: " weights=")
        let original = pieces[0]
        let weight = pieces.count == 2 ? pieces[1] : nil
        let halves = original.components(separatedBy: " ~ ")
        let response = halves[0]
        var terms: [Term] = []
        var seen: Set<Set<String>> = []
        for expression in halves[1].components(separatedBy: " + ") {
            let expanded: [[Factor]]
            if expression.contains("*") {
                let factors = expression.components(separatedBy: "*").map(Factor.init)
                expanded = (1...factors.count).flatMap { size in combinations(factors.count, size).map { $0.map { factors[$0] } } }
            } else { expanded = [expression.components(separatedBy: ":").map(Factor.init)] }
            for factors in expanded {
                let term = Term(factors: factors)
                if seen.insert(term.factorNames).inserted { terms.append(term) }
            }
        }
        var factorColumns: [String] = []
        var categoricalColumns: [String] = []
        for term in terms {
            for factor in term.factors {
                if !factorColumns.contains(factor.column) { factorColumns.append(factor.column) }
                if factor.categorical && !categoricalColumns.contains(factor.column) { categoricalColumns.append(factor.column) }
            }
        }
        var variables = Set(factorColumns + [response])
        if let weight { variables.insert(weight) }
        self.original = original
        self.response = response
        self.weight = weight
        self.terms = terms
        self.factorColumns = factorColumns
        self.categoricalColumns = categoricalColumns
        self.variables = variables
    }

    func format(_ selected: [Int]) -> String {
        let names = selected.sorted().map { terms[$0].name }
        return response + " ~ " + (names.isEmpty ? "1" : names.joined(separator: " + "))
    }

    func removable(_ selected: [Int]) -> [Int] {
        selected.sorted().filter { index in !selected.contains { terms[index].contained(in: terms[$0]) } }
    }

    func candidates(_ selected: [Int]) -> [Int] {
        let selected = Set(selected)
        return terms.indices.filter { index in
            !selected.contains(index) && terms.indices.allSatisfy { !terms[$0].contained(in: terms[index]) || selected.contains($0) }
        }
    }

    func hierarchical(_ selected: [Int]) -> Bool {
        let included = Set(selected)
        return selected.allSatisfy { index in terms.indices.allSatisfy { !terms[$0].contained(in: terms[index]) || included.contains($0) } }
    }
}

struct DesignColumn {
    let termIndex: Int?
    let components: [FactorComponent]
    var name: String { components.isEmpty ? "(Intercept)" : components.map { $0.name }.joined(separator: ":") }

    func value(_ row: Record) -> Double {
        guard let first = components.first else { return 1 }
        var value = first.factor.value(row, level: first.level)
        for component in components.dropFirst() { value *= component.factor.value(row, level: component.level) }
        return value
    }
}

struct Design {
    let model: Model
    let rowNumbers: [Int]
    let rows: [Record]
    let levels: [String: [String]]
    let columns: [DesignColumn]
    let matrix: [[Double]]
    let response: [Double]
    let weights: [Double]

    init(_ model: Model, _ data: DataFrame) {
        let used = data.rows.enumerated().filter { item in model.variables.allSatisfy { !item.element[$0]!.isMissing } }
        let rows = used.map { $0.element }
        let levels = Dictionary(uniqueKeysWithValues: model.categoricalColumns.map { column in
            (column, Set(rows.map { $0[column]!.labelValue! }).sorted())
        })
        var columns = [DesignColumn(termIndex: nil, components: [])]
        for (index, term) in model.terms.enumerated() {
            let components = term.factors.map { $0.components(levels) }
            let count = components.reduce(1) { $0 * $1.count }
            for ordinal in 0..<count {
                var remaining = ordinal
                let choices = components.map { options -> FactorComponent in
                    let choice = options[remaining % options.count]
                    remaining /= options.count
                    return choice
                }
                columns.append(DesignColumn(termIndex: index, components: choices))
            }
        }
        self.model = model
        rowNumbers = used.map { $0.offset + 1 }
        self.rows = rows
        self.levels = levels
        self.columns = columns
        matrix = rows.map { row in columns.map { $0.value(row) } }
        response = rows.map { $0[model.response]!.numericValue! }
        weights = rows.map { row in model.weight.map { row[$0]!.numericValue! } ?? 1 }
    }

    func values(_ row: Record) -> [Double] { columns.map { $0.value(row) } }

    func subsetMatrix(_ selected: [Int]) -> [[Double]] {
        let selected = Set(selected)
        let indices = columns.indices.filter { columns[$0].termIndex == nil || selected.contains(columns[$0].termIndex!) }
        return matrix.map { row in indices.map { row[$0] } }
    }

    func predictable(_ row: Record) -> Bool {
        for column in model.factorColumns {
            guard let value = row[column], !value.isMissing else { return false }
            if let available = levels[column], !available.contains(value.labelValue!) { return false }
        }
        return true
    }
}
