import java.util.*;
import java.util.function.*;
final class Combining {
    static final String NA = "NOT_APPLICABLE", IP = "INDETERMINATE{P}", ID = "INDETERMINATE{D}",
                        IDP = "INDETERMINATE{DP}";
    record State(Main.Evaluation evaluated, Main.Target checked) {}
    record Result(String decision, String reason, List<State> states) {}
    static Result combine(String algorithm, List<PolicyParser.Element> children,
                          Function<PolicyParser.Element, Main.Evaluation> evaluate,
                          Function<PolicyParser.Element, Main.Target> target) {
        List<State> states = new ArrayList<>(Collections.nCopies(children.size(), null));
        if (algorithm.equals("only-one-applicable")) {
            int matched = -1;
            for (int i = 0; i < children.size(); i++) {
                PolicyParser.Element child = children.get(i);
                Main.Target result = target.apply(child);
                states.set(i, new State(null, result));
                if (result.result().equals("INDETERMINATE"))
                    return new Result(IDP, result.reason(), states);
                if (result.result().equals("MATCH")) {
                    if (matched >= 0)
                        return new Result(IDP,
                                          "multiple applicable " +
                                              children.get(matched).identifier + " " +
                                              child.identifier,
                                          states);
                    matched = i;
                }
            }
            if (matched < 0)
                return new Result(NA, null, states);
            Main.Evaluation result = evaluate.apply(children.get(matched));
            states.set(matched, new State(result, null));
            return new Result(result.decision, result.reason, states);
        }
        Set<String> decisions = new HashSet<>();
        String firstError = null;
        for (int i = 0; i < children.size(); i++) {
            Main.Evaluation result = evaluate.apply(children.get(i));
            states.set(i, new State(result, null));
            String decision = result.decision;
            decisions.add(decision);
            if (decision.startsWith("INDETERMINATE") && firstError == null)
                firstError = result.reason;
            if (algorithm.equals("first-applicable") && !decision.equals(NA))
                return new Result(decision, result.reason, states);
            if ((algorithm.equals("deny-overrides") || algorithm.equals("permit-unless-deny")) &&
                decision.equals("DENY"))
                return new Result("DENY", null, states);
            if ((algorithm.equals("permit-overrides") || algorithm.equals("deny-unless-permit")) &&
                decision.equals("PERMIT"))
                return new Result("PERMIT", null, states);
        }
        String decision = switch (algorithm) {
            case "deny-unless-permit" -> "DENY";
            case "permit-unless-deny" -> "PERMIT";
            case "first-applicable" -> NA;
            case "deny-overrides" ->
                decisions.contains(IDP) || decisions.contains(ID) && (decisions.contains(IP) ||
                                                                      decisions.contains("PERMIT"))
                    ? IDP
                : decisions.contains(ID)       ? ID
                : decisions.contains("PERMIT") ? "PERMIT"
                : decisions.contains(IP)       ? IP
                                               : NA;
            default ->
                decisions.contains(IDP) || decisions.contains(IP) && (decisions.contains(ID) ||
                                                                      decisions.contains("DENY"))
                    ? IDP
                : decisions.contains(IP)     ? IP
                : decisions.contains("DENY") ? "DENY"
                : decisions.contains(ID)     ? ID
                                             : NA;
        };
        return new Result(decision, decision.startsWith("INDETERMINATE") ? firstError : null,
                          states);
    }
}
