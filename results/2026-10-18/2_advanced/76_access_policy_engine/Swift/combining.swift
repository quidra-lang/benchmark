import Foundation

enum Decision: String, Hashable {
    case permit = "PERMIT"
    case deny = "DENY"
    case notApplicable = "NOT_APPLICABLE"
    case indeterminateP = "INDETERMINATE{P}"
    case indeterminateD = "INDETERMINATE{D}"
    case indeterminateDP = "INDETERMINATE{DP}"

    var definite: Bool { self == .permit || self == .deny }
    var indeterminate: Bool { !definite && self != .notApplicable }
}

enum ChildState {
    case skipped
    case checked(TargetResult)
    case evaluated(Evaluation)
}

func combine(_ algorithm: String, children: [Element], evaluate: (Element) -> Evaluation,
             target: (Element) -> TargetResult) -> (Decision, String?, [ChildState]) {
    var states = Array(repeating: ChildState.skipped, count: children.count)
    if algorithm == "only-one-applicable" {
        var matched: Int?
        for (index, child) in children.enumerated() {
            let result = target(child)
            states[index] = .checked(result)
            if result.kind == .indeterminate { return (.indeterminateDP, result.reason, states) }
            if result.kind == .match {
                if let matched {
                    return (.indeterminateDP, "multiple applicable \(children[matched].identifier) \(child.identifier)", states)
                }
                matched = index
            }
        }
        guard let matched else { return (.notApplicable, nil, states) }
        let result = evaluate(children[matched])
        states[matched] = .evaluated(result)
        return (result.decision, result.reason, states)
    }
    var decisions: Set<Decision> = [], firstError: String?
    for (index, child) in children.enumerated() {
        let result = evaluate(child), decision = result.decision
        states[index] = .evaluated(result)
        decisions.insert(decision)
        if decision.indeterminate && firstError == nil { firstError = result.reason }
        if algorithm == "first-applicable" && decision != .notApplicable { return (decision, result.reason, states) }
        if ["deny-overrides", "permit-unless-deny"].contains(algorithm) && decision == .deny { return (.deny, nil, states) }
        if ["permit-overrides", "deny-unless-permit"].contains(algorithm) && decision == .permit { return (.permit, nil, states) }
    }
    if algorithm == "deny-unless-permit" { return (.deny, nil, states) }
    if algorithm == "permit-unless-deny" { return (.permit, nil, states) }
    if algorithm == "first-applicable" { return (.notApplicable, nil, states) }
    let result: Decision
    if algorithm == "deny-overrides" {
        if decisions.contains(.indeterminateDP) || (decisions.contains(.indeterminateD)
            && (decisions.contains(.indeterminateP) || decisions.contains(.permit))) { result = .indeterminateDP }
        else if decisions.contains(.indeterminateD) { result = .indeterminateD }
        else if decisions.contains(.permit) { result = .permit }
        else if decisions.contains(.indeterminateP) { result = .indeterminateP }
        else { result = .notApplicable }
    } else {
        if decisions.contains(.indeterminateDP) || (decisions.contains(.indeterminateP)
            && (decisions.contains(.indeterminateD) || decisions.contains(.deny))) { result = .indeterminateDP }
        else if decisions.contains(.indeterminateP) { result = .indeterminateP }
        else if decisions.contains(.deny) { result = .deny }
        else if decisions.contains(.indeterminateD) { result = .indeterminateD }
        else { result = .notApplicable }
    }
    return (result, result.indeterminate ? firstError : nil, states)
}
