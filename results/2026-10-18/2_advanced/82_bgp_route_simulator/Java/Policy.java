import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
final class Policy {
    record Community(int first, int second) implements Comparable<Community> {
        public int compareTo(Community other) {
            int c = Integer.compare(first, other.first);
            return c != 0 ? c : Integer.compare(second, other.second);
        }
        public String toString() { return equals(NO_EXPORT) ? "NO_EXPORT" : first + ":" + second; }
    }
    static final Community NO_EXPORT = new Community(65535, 65281);
    static Community community(String text) {
        if (text.equals("NO_EXPORT"))
            return NO_EXPORT;
        String[] f = text.split(":");
        return new Community(Integer.parseInt(f[0]), Integer.parseInt(f[1]));
    }
    static List<Community> communities(List<String> values) {
        Set<Community> result = new TreeSet<>();
        for (String value : values)
            result.add(community(value));
        return List.copyOf(result);
    }
    static String communityText(List<Community> values) {
        return values.isEmpty() ? "-"
                                : String.join(",", values.stream().map(Object::toString).toList());
    }
    record Entry(boolean permit, Topology.Prefix base, int low, int high) {}
    record Condition(String kind, String text, int low, int high, Community community) {}
    record Action(String kind, int value, Community community) {}
    static final class Rule {
        String name, direction, target;
        boolean active;
        int owner, hits;
        List<Condition> conditions;
        List<Action> actions;
        Rule(String[] f, List<Condition> conditions, List<Action> actions) {
            name = f[1];
            active = f[2].equals("ON");
            owner = Integer.parseInt(f[3]);
            direction = f[4];
            target = f[5];
            this.conditions = conditions;
            this.actions = actions;
        }
        boolean has(String kind) {
            for (Action action : actions)
                if (action.kind().equals(kind))
                    return true;
            return false;
        }
        int value(String kind, int fallback) {
            for (Action action : actions)
                if (action.kind().equals(kind))
                    return action.value();
            return fallback;
        }
    }
    Map<String, List<Entry>> lists = new HashMap<>();
    List<Rule> rules = new ArrayList<>();
    Map<String, Rule> byName = new HashMap<>();
    Policy() throws Exception {
        for (String line :
             Files.readAllLines(Path.of("input/policies.txt"), StandardCharsets.US_ASCII)) {
            String[] f = line.split(" ");
            if (f[0].equals("PLIST")) {
                Topology.Prefix p = Topology.prefix(f[3]);
                int low = p.length(), high = p.length();
                    for (int i = 4; i < f.length; i += 2)
                    if (f[i].equals("GE")) {
                        low = Integer.parseInt(f[i + 1]);
                            high = 32;
                    }
                for (int i = 4; i < f.length; i += 2)
                    if (f[i].equals("LE"))
                        high = Integer.parseInt(f[i + 1]);
                lists.computeIfAbsent(f[1], k -> new ArrayList<>())
                    .add(new Entry(f[2].equals("PERMIT"), p, low, high));
                continue;
            }
            int separator = Arrays.asList(f).indexOf("THEN");
            List<Condition> conditions = new ArrayList<>();
            for (int i = 6; i < separator; i += 2) {
                String kind = f[i], value = f[i + 1];
                int low = 0, high = 0;
                Community comm = null;
                if (kind.equals("CONTAINS") || kind.equals("ORIGINAS"))
                    low = Integer.parseInt(value);
                else if (kind.equals("LENGTH")) {
                    String[] bounds = value.split("-");
                    low = Integer.parseInt(bounds[0]);
                    high = Integer.parseInt(bounds[1]);
                } else if (kind.equals("COMMUNITY"))
                    comm = community(value);
                conditions.add(new Condition(kind, value, low, high, comm));
            }
            List<Action> actions = new ArrayList<>();
            for (int i = separator + 1; i < f.length;) {
                String kind = f[i++];
                int value = 0;
                Community comm = null;
                if (!kind.equals("DENY") && !kind.equals("ALLOW")) {
                    String text = f[i++];
                    if (kind.equals("ADD") || kind.equals("REMOVE"))
                        comm = community(text);
                    else
                        value = Integer.parseInt(text);
                }
                actions.add(new Action(kind, value, comm));
            }
            Rule rule = new Rule(f, conditions, actions);
            rules.add(rule);
            byName.put(rule.name, rule);
        }
    }
    boolean permitted(String name, Topology.Prefix prefix) {
        for (Entry entry : lists.get(name))
            if (entry.low() <= prefix.length() && prefix.length() <= entry.high() &&
                entry.base().contains(prefix.address()))
                return entry.permit();
        return false;
    }
    boolean matches(Rule rule, int owner, Topology.Link link, Topology.Prefix prefix,
                    List<Integer> path, List<Community> communities) {
        if (!rule.active || rule.owner != owner)
            return false;
        if (!rule.target.equals("*") && !rule.target.equals(Integer.toString(link.other(owner))) &&
            !rule.target.equals(link.name))
            return false;
        for (Condition c : rule.conditions) {
            boolean match = switch (c.kind()) {
                case "PREFIX" -> permitted(c.text(), prefix);
                case "CONTAINS" -> path.contains(c.low());
                case "ORIGINAS" -> (path.isEmpty() ? owner : path.getLast()) == c.low();
                case "LENGTH" -> c.low() <= path.size() && path.size() <= c.high();
                default -> communities.contains(c.community());
            };
            if (!match)
                return false;
        }
        return true;
    }
    Rule applied(String direction, int owner, Topology.Link link, Topology.Prefix prefix,
                 List<Integer> path, List<Community> communities) {
        for (Rule rule : rules)
            if (rule.direction.equals(direction) &&
                matches(rule, owner, link, prefix, path, communities))
                return rule;
        return null;
    }
    static List<Community> edit(List<Community> communities, Rule rule) {
        Set<Community> result = new TreeSet<>(communities);
        for (Action action : rule.actions)
            if (action.kind().equals("ADD"))
                result.add(action.community());
            else if (action.kind().equals("REMOVE"))
                result.remove(action.community());
        return List.copyOf(result);
    }
}
