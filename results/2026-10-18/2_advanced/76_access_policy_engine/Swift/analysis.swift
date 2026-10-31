import Foundation

func enumeratePoints(_ domains: [(String, [Value])], visit: ([String: Value]) -> Void) {
    func walk(_ index: Int, _ values: [String: Value]) {
        if index == domains.count { visit(values); return }
        let (reference, candidates) = domains[index]
        for candidate in candidates {
            var next = values
            next[reference] = candidate
            walk(index + 1, next)
        }
    }
    walk(0, [:])
}

func dayNotation(_ days: Set<Int>) -> String {
    let ordered = days.sorted()
    var first = ordered[0], last = ordered[0], runs: [String] = []
    for day in ordered.dropFirst() {
        if day != last + 1 { runs.append("\(first)-\(last)"); first = day }
        last = day
    }
    runs.append("\(first)-\(last)")
    return runs.joined(separator: ",")
}

func blocker(_ rule: Element, standalone: [String: Decision]) -> String? {
    for earlier in rule.parent!.children {
        if earlier === rule { break }
        if standalone[earlier.identifier] != .notApplicable { return earlier.identifier }
    }
    return nil
}

func conflictWinner(_ policy: Element, _ earlier: Element, _ later: Element) -> String {
    if policy.behavior == "first-applicable" { return earlier.identifier }
    let effect = ["deny-overrides", "permit-unless-deny"].contains(policy.behavior) ? "DENY" : "PERMIT"
    return earlier.behavior == effect ? earlier.identifier : later.identifier
}
