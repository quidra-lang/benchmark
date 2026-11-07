struct NamingCondition {
    let feature: Int
    let greater: Bool
    let threshold: Double

    func holds(_ center: Point) -> Bool {
        greater ? center[feature] > threshold : center[feature] < threshold
    }
}

struct NamingRule {
    let name: String
    let conditions: [NamingCondition]
}

func readRules(_ path: String) throws -> [NamingRule] {
    try readLines(path).map { line in
        let words = line.split(separator: " ").map(String.init)
        let conditions = stride(from: 1, to: words.count, by: 3).map { index in
            NamingCondition(feature: featureNames.firstIndex(of: words[index])!, greater: words[index + 1] == ">",
                threshold: Double(words[index + 2])!)
        }
        return NamingRule(name: words[0], conditions: conditions)
    }
}

func ruleNumber(_ rules: [NamingRule], _ center: Point) -> Int {
    rules.firstIndex { rule in rule.conditions.allSatisfy { $0.holds(center) } }!
}

func originalScale(_ center: Point, _ means: Point, _ sds: Point) -> Point {
    center.enumerated().map { feature, component in
        let value = means[feature] + sds[feature] * component
        return sqrtFeatures[feature] ? value * value : value
    }
}
