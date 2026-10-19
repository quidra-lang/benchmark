"""Six combining algorithms with exact stopping and applicability checks."""


NA = "NOT_APPLICABLE"
IP, ID, IDP = "INDETERMINATE{P}", "INDETERMINATE{D}", "INDETERMINATE{DP}"


def combine(algorithm, children, evaluate, target):
    states = [None] * len(children)
    if algorithm == "only-one-applicable":
        matched = None
        for index, child in enumerate(children):
            result, reason = target(child)
            states[index] = "checked", (result, reason)
            if result == "INDETERMINATE":
                return IDP, reason, states
            if result == "MATCH":
                if matched is not None:
                    return IDP, f"multiple applicable {children[matched].identifier} {child.identifier}", states
                matched = index
        if matched is None:
            return NA, None, states
        result = evaluate(children[matched])
        states[matched] = "evaluated", result
        return result.decision, result.reason, states
    decisions, first_error = set(), None
    for index, child in enumerate(children):
        result = evaluate(child)
        states[index] = "evaluated", result
        decision = result.decision
        decisions.add(decision)
        if decision.startswith("INDETERMINATE") and first_error is None:
            first_error = result.reason
        if algorithm == "first-applicable" and decision != NA:
            return decision, result.reason, states
        if algorithm in ("deny-overrides", "permit-unless-deny") and decision == "DENY":
            return "DENY", None, states
        if algorithm in ("permit-overrides", "deny-unless-permit") and decision == "PERMIT":
            return "PERMIT", None, states
    if algorithm == "deny-unless-permit":
        return "DENY", None, states
    if algorithm == "permit-unless-deny":
        return "PERMIT", None, states
    if algorithm == "first-applicable":
        return NA, None, states
    if algorithm == "deny-overrides":
        if IDP in decisions or ID in decisions and (IP in decisions or "PERMIT" in decisions):
            decision = IDP
        elif ID in decisions:
            decision = ID
        elif "PERMIT" in decisions:
            decision = "PERMIT"
        elif IP in decisions:
            decision = IP
        else:
            decision = NA
    else:
        if IDP in decisions or IP in decisions and (ID in decisions or "DENY" in decisions):
            decision = IDP
        elif IP in decisions:
            decision = IP
        elif "DENY" in decisions:
            decision = "DENY"
        elif ID in decisions:
            decision = ID
        else:
            decision = NA
    return decision, first_error if decision.startswith("INDETERMINATE") else None, states
