import java.util.*;
final class Analysis {
    record Domain(String name, List<Object> values) {}
    static List<Map<String, Object>> points(List<Domain> domains) {
        List<Map<String, Object>> points = new ArrayList<>();
        points.add(new LinkedHashMap<>());
        for (Domain domain : domains) {
            List<Map<String, Object>> following = new ArrayList<>();
            for (Map<String, Object> point : points)
                for (Object value : domain.values()) {
                    Map<String, Object> next = new LinkedHashMap<>(point);
                    next.put(domain.name(), value);
                    following.add(next);
                }
            points = following;
        }
        return points;
    }
    static String dayNotation(Collection<Integer> days) {
        List<Integer> ordered = new ArrayList<>(new TreeSet<>(days));
        int first = ordered.getFirst(), last = first;
        List<String> runs = new ArrayList<>();
        for (int i = 1; i < ordered.size(); i++) {
            int day = ordered.get(i);
            if (day != last + 1) {
                runs.add(first + "-" + last);
                first = day;
            }
            last = day;
        }
        runs.add(first + "-" + last);
        return String.join(",", runs);
    }
    static String blocker(PolicyParser.Element rule, Map<String, String> standalone) {
        for (PolicyParser.Element earlier : rule.parent.children) {
            if (earlier == rule)
                break;
            if (!standalone.get(earlier.identifier).equals(Combining.NA))
                return earlier.identifier;
        }
        return null;
    }
    static String conflictWinner(PolicyParser.Element policy, PolicyParser.Element earlier,
                                 PolicyParser.Element later) {
        if (policy.behavior.equals("first-applicable"))
            return earlier.identifier;
        String effect = Set.of("deny-overrides", "permit-unless-deny").contains(policy.behavior)
                            ? "DENY"
                            : "PERMIT";
        return earlier.behavior.equals(effect) ? earlier.identifier : later.identifier;
    }
}
