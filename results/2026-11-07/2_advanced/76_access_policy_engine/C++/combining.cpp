#include "policy.hpp"
bool definite(Decision d) { return d == Decision::Permit || d == Decision::Deny; }
bool indeterminate(Decision d) {
    return d == Decision::IP || d == Decision::ID || d == Decision::IDP;
}
std::string decision_name(Decision d) {
    static const std::array<std::string, 6> names{"PERMIT",           "DENY",
                                                  "NOT_APPLICABLE",   "INDETERMINATE{P}",
                                                  "INDETERMINATE{D}", "INDETERMINATE{DP}"};
    return names[int(d)];
}
std::string notation(Decision d, const std::string &reason) {
    return decision_name(d) + (indeterminate(d) ? " (" + reason + ")" : "");
}
std::string target_name(TargetKind kind) {
    return kind == TargetKind::Match     ? "MATCH"
           : kind == TargetKind::NoMatch ? "NO_MATCH"
                                         : "INDETERMINATE";
}
Combined combine(const Element &e, const std::function<Eval(Element *)> &evaluate,
                 const std::function<TargetResult(Element *)> &target) {
    Combined out;
    out.children.resize(e.children.size());
    const std::string &algorithm = e.behavior;
    if (algorithm == "only-one-applicable") {
        int matched = -1;
        for (int i = 0; i < int(e.children.size()); ++i) {
            TargetResult checked = target(e.children[i]);
            out.children[i].kind = ChildState::Kind::Checked;
            out.children[i].checked = checked;
            if (checked.kind == TargetKind::Indeterminate) {
                out.decision = Decision::IDP;
                out.reason = checked.reason;
                return out;
            }
            if (checked.kind == TargetKind::Match) {
                if (matched >= 0) {
                    out.decision = Decision::IDP;
                    out.reason = "multiple applicable " + e.children[matched]->identifier + " " +
                                 e.children[i]->identifier;
                    return out;
                }
                matched = i;
            }
        }
        if (matched >= 0) {
            Eval result = evaluate(e.children[matched]);
            out.children[matched].kind = ChildState::Kind::Evaluated;
            out.children[matched].evaluation = result;
            out.decision = result->decision;
            out.reason = result->reason;
        }
        return out;
    }
    std::array<bool, 6> present{};
    std::string first_error;
    for (int i = 0; i < int(e.children.size()); ++i) {
        Eval result = evaluate(e.children[i]);
        out.children[i].kind = ChildState::Kind::Evaluated;
        out.children[i].evaluation = result;
        Decision d = result->decision;
        present[int(d)] = true;
        if (indeterminate(d) && first_error.empty())
            first_error = result->reason;
        bool stop = (algorithm == "first-applicable" && d != Decision::NA) ||
                    ((algorithm == "deny-overrides" || algorithm == "permit-unless-deny") &&
                     d == Decision::Deny) ||
                    ((algorithm == "permit-overrides" || algorithm == "deny-unless-permit") &&
                     d == Decision::Permit);
        if (stop) {
            out.decision = d;
            out.reason = result->reason;
            return out;
        }
    }
    auto has = [&](Decision d) { return present[int(d)]; };
    if (algorithm == "deny-unless-permit")
        out.decision = Decision::Deny;
    else if (algorithm == "permit-unless-deny")
        out.decision = Decision::Permit;
    else if (algorithm == "deny-overrides") {
        if (has(Decision::IDP) ||
            (has(Decision::ID) && (has(Decision::IP) || has(Decision::Permit))))
            out.decision = Decision::IDP;
        else if (has(Decision::ID))
            out.decision = Decision::ID;
        else if (has(Decision::Permit))
            out.decision = Decision::Permit;
        else if (has(Decision::IP))
            out.decision = Decision::IP;
    } else if (algorithm == "permit-overrides") {
        if (has(Decision::IDP) || (has(Decision::IP) && (has(Decision::ID) || has(Decision::Deny))))
            out.decision = Decision::IDP;
        else if (has(Decision::IP))
            out.decision = Decision::IP;
        else if (has(Decision::Deny))
            out.decision = Decision::Deny;
        else if (has(Decision::ID))
            out.decision = Decision::ID;
    }
    if (indeterminate(out.decision))
        out.reason = first_error;
    return out;
}
