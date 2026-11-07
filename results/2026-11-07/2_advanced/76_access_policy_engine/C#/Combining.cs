using System;
using System.Collections.Generic;
using System.Linq;
public static class Combining {
    public const string NA = "NOT_APPLICABLE", IP = "INDETERMINATE{P}", ID = "INDETERMINATE{D}",
                        IDP = "INDETERMINATE{DP}";
    public record State(Program.Evaluation evaluated, Program.Target checkedTarget);
    public record Result(string decision, string reason, List<State> states);
    public static Result Combine(string algorithm, List<PolicyParser.Element> children,
                                 Func<PolicyParser.Element, Program.Evaluation> evaluate,
                                 Func<PolicyParser.Element, Program.Target> target) {
        List<State> states = Enumerable.Repeat<State>(null, children.Count).ToList();
        if (algorithm == "only-one-applicable") {
            int matched = -1;
            for (int i = 0; i < children.Count; i++) {
                PolicyParser.Element child = children[i];
                Program.Target result = target(child);
                states[i] = new(null, result);
                if (result.result == "INDETERMINATE")
                    return new(IDP, result.reason, states);
                if (result.result == "MATCH") {
                    if (matched >= 0)
                        return new(IDP,
                                   "multiple applicable " + children[matched].identifier + " " +
                                       child.identifier,
                                   states);
                    matched = i;
                }
            }
            if (matched < 0)
                return new(NA, null, states);
            Program.Evaluation evaluated = evaluate(children[matched]);
            states[matched] = new(evaluated, null);
            return new(evaluated.decision, evaluated.reason, states);
        }
        HashSet<string> decisions = new();
        string firstError = null;
        for (int i = 0; i < children.Count; i++) {
            Program.Evaluation evaluated = evaluate(children[i]);
            states[i] = new(evaluated, null);
            string current = evaluated.decision;
            decisions.Add(current);
            if (current.StartsWith("INDETERMINATE") && firstError == null)
                firstError = evaluated.reason;
            if (algorithm == "first-applicable" && current != NA)
                return new(current, evaluated.reason, states);
            if ((algorithm == "deny-overrides" || algorithm == "permit-unless-deny") &&
                current == "DENY")
                return new("DENY", null, states);
            if ((algorithm == "permit-overrides" || algorithm == "deny-unless-permit") &&
                current == "PERMIT")
                return new("PERMIT", null, states);
        }
        string decision = algorithm switch {
            "deny-unless-permit" => "DENY", "permit-unless-deny" => "PERMIT",
            "first-applicable" => NA,
            "deny-overrides" => decisions.Contains(IDP) ||
                                        decisions.Contains(ID) &&
                                            (decisions.Contains(IP) || decisions.Contains("PERMIT"))
                                    ? IDP
                                : decisions.Contains(ID)       ? ID
                                : decisions.Contains("PERMIT") ? "PERMIT"
                                : decisions.Contains(IP)       ? IP
                                                               : NA,
            _ => decisions.Contains(IDP) || decisions.Contains(IP) && (decisions.Contains(ID) ||
                                                                       decisions.Contains("DENY"))
                     ? IDP
                 : decisions.Contains(IP)     ? IP
                 : decisions.Contains("DENY") ? "DENY"
                 : decisions.Contains(ID)     ? ID
                                              : NA
        };
        return new(decision, decision.StartsWith("INDETERMINATE") ? firstError : null, states);
    }
}
