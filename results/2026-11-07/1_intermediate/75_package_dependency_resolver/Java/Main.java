import java.io.*;
import java.util.*;

public class Main {
    static class Problem extends RuntimeException {
        Problem(String message) {
            super("error: " + message);
        }
    }

    static void fail(String message) {
        throw new Problem(message);
    }

    static boolean number(String text) {
        return text.matches("0|[1-9][0-9]{0,3}");
    }

    static boolean digits(String text) {
        return text.matches("[0-9]+");
    }

    static class Version implements Comparable<Version> {
        int[] core;
        List<String> prerelease;
        String text;
        Version(int[] core, List<String> prerelease) {
            this.core = core;
            this.prerelease = prerelease;
            text = core[0] + "." + core[1] + "." + core[2] + (prerelease.isEmpty() ? "" : "-" + String.join(".", prerelease));
        }
        String coreText() {
            return core[0] + "." + core[1] + "." + core[2];
        }
        boolean stable() {
            return prerelease.isEmpty();
        }
        public int compareTo(Version other) {
            for (int i = 0; i < 3; i++) if (core[i] != other.core[i]) return Integer.compare(core[i], other.core[i]);
            if (stable() || other.stable()) return Boolean.compare(stable(), other.stable());
            for (int i = 0; i < Math.min(prerelease.size(), other.prerelease.size()); i++) {
                String a = prerelease.get(i), b = other.prerelease.get(i);
                boolean an = digits(a), bn = digits(b);
                int order = an && bn ? Integer.compare(Integer.parseInt(a), Integer.parseInt(b)) : an != bn ? (an ? -1 : 1) : a.compareTo(b);
                if (order != 0) return order;
            }
            return Integer.compare(prerelease.size(), other.prerelease.size());
        }
    }

    static Version parseVersion(String text) {
        String[] halves = text.split("-", -1);
        if (halves.length > 2) return null;
        String[] parts = halves[0].split("\\.", -1);
        if (parts.length != 3 || Arrays.stream(parts).anyMatch(p -> !number(p))) return null;
        List<String> pre = new ArrayList<>();
        if (halves.length == 2) for (String p : halves[1].split("\\.", -1)) {
            if (!p.matches("[a-z0-9]+") || (digits(p) && !number(p))) return null;
            pre.add(p);
        }
        return new Version(Arrays.stream(parts).mapToInt(Integer::parseInt).toArray(), pre);
    }

    static Version checkedVersion(String text) {
        Version result = parseVersion(text);
        if (result == null) fail("invalid version '" + text + "'");
        return result;
    }

    record ComparatorTerm(String operator, Version version) {
        boolean matches(Version value) {
            int c = value.compareTo(version);
            return switch (operator) {
                case "=" -> c == 0;
                case ">" -> c > 0;
                case ">=" -> c >= 0;
                case "<" -> c < 0;
                default -> c <= 0;
            };
        }
        public String toString() {
            return operator + version.text;
        }
    }

    static class Alternative {
        List<ComparatorTerm> comparators = new ArrayList<>();
        Set<String> prereleaseCores = new HashSet<>();
        void add(String operator, Version version) {
            comparators.add(new ComparatorTerm(operator, version));
        }
        boolean matches(Version v) {
            return (v.stable() || prereleaseCores.contains(v.coreText())) && comparators.stream().allMatch(c -> c.matches(v));
        }
        String normal() {
            return comparators.isEmpty() ? "*" : String.join(" ", comparators.stream().map(Object::toString).toList());
        }
    }

    static class Constraint {
        List<Alternative> alternatives = new ArrayList<>();
        boolean matches(Version v) {
            return alternatives.stream().anyMatch(a -> a.matches(v));
        }
        String normal() {
            return String.join(" || ", alternatives.stream().map(Alternative::normal).toList());
        }
    }

    static Constraint parseConstraint(String text) {
        Constraint result = new Constraint();
        for (String branch : text.split(" \\|\\| ", -1)) {
            Alternative a = new Alternative();
            for (String term : branch.split(" ", -1)) {
                if (term.isEmpty()) return null;
                String operator = "", pattern = term;
                for (String op : List.of(">=", "<=", ">", "<", "=", "^", "~")) if (term.startsWith(op)) {
                    operator = op;
                    pattern = term.substring(op.length());
                    break;
                }
                Version lower = parseVersion(pattern);
                int count;
                if (lower != null && !lower.stable()) {
                    count = 3;
                    a.prereleaseCores.add(lower.coreText());
                } else {
                    String[] parts = pattern.split("\\.", -1);
                    if (parts.length < 1 || parts.length > 3) return null;
                    int[] core = new int[3];
                    count = 0;
                    boolean wildcard = false;
                    for (int i = 0; i < parts.length; i++) {
                        if (parts[i].equals("x") || parts[i].equals("*")) wildcard = true;
                        else {
                            if (wildcard || !number(parts[i])) return null;
                            core[i] = Integer.parseInt(parts[i]);
                            count++;
                        }
                    }
                    lower = new Version(core, List.of());
                }
                if (count == 0) {
                    if (operator.equals(">") || operator.equals("<")) a.add("<", new Version(new int[]{0, 0, 0}, List.of("0")));
                    continue;
                }
                Version[] upper = new Version[3];
                for (int i = 0; i < 3; i++) {
                    int[] core = lower.core.clone();
                    core[i]++;
                    for (int j = i + 1; j < 3; j++) core[j] = 0;
                    upper[i] = new Version(core, List.of());
                }
                switch (operator) {
                    case "", "=" -> {
                        if (count == 3) a.add("=", lower);
                        else {
                            a.add(">=", lower);
                            a.add("<", upper[count - 1]);
                        }
                    }
                    case ">" -> a.add(count == 3 ? ">" : ">=", count == 3 ? lower : upper[count - 1]);
                    case "<=" -> a.add(count == 3 ? "<=" : "<", count == 3 ? lower : upper[count - 1]);
                    case ">=", "<" -> a.add(operator, lower);
                    case "~" -> {
                        a.add(">=", lower);
                        a.add("<", upper[count == 1 ? 0 : 1]);
                    }
                    case "^" -> {
                        int i = lower.core[0] != 0 || count == 1 ? 0 : lower.core[1] != 0 || count == 2 ? 1 : 2;
                        a.add(">=", lower);
                        a.add("<", upper[i]);
                    }
                }
            }
            result.alternatives.add(a);
        }
        return result;
    }

    static Constraint checkedConstraint(String text) {
        Constraint result = parseConstraint(text);
        if (result == null) fail("invalid constraint '" + text + "'");
        return result;
    }

    record Clause(String name, String text, Constraint constraint) { }

    static Clause clause(String name, String text) {
        return new Clause(name, text, checkedConstraint(text));
    }

    static class PackageVersion {
        String name;
        Version version;
        List<Clause> dependencies = new ArrayList<>(), conflicts = new ArrayList<>();
        boolean yanked;
        PackageVersion(String name, Version version) {
            this.name = name;
            this.version = version;
        }
        public String toString() {
            return name + "@" + version.text;
        }
    }

    record Requirement(Clause clause, PackageVersion origin, Requirement parent) {
        String line() {
            return origin == null ? "requested " + clause.name + " " + clause.text : origin + " requires " + clause.name + " " + clause.text;
        }
        List<String> chain() {
            List<String> result = parent == null ? new ArrayList<>() : parent.chain();
            result.add(line());
            return result;
        }
    }

    record Snapshot(List<Clause> requests, TreeMap<String, PackageVersion> installed) { }

    TreeMap<String, List<PackageVersion>> registry = new TreeMap<>();
    List<Clause> requests = new ArrayList<>();
    TreeMap<String, PackageVersion> installed = new TreeMap<>();
    Set<String> held = new TreeSet<>();
    TreeMap<String, Clause> advisories = new TreeMap<>();
    ArrayDeque<Snapshot> history = new ArrayDeque<>();

    List<PackageVersion> versions(String name) {
        return registry.getOrDefault(name, List.of());
    }

    PackageVersion registered(String name, String version) {
        return versions(name).stream().filter(p -> p.version.text.equals(version)).findFirst().orElse(null);
    }

    PackageVersion checkedPackage(String name, String version) {
        PackageVersion p = registered(name, version);
        if (p == null) fail(name + "@" + version + " is not registered");
        return p;
    }

    boolean vulnerable(PackageVersion p) {
        return advisories.values().stream().anyMatch(a -> a.name.equals(p.name) && a.constraint.matches(p.version));
    }

    String display(PackageVersion p) {
        boolean current = installed.get(p.name) == p;
        return p + (p.yanked ? current ? " (yanked, installed)" : " (yanked)" : current ? " (installed)" : "");
    }
    class Resolution {
        TreeMap<String, PackageVersion> selected = new TreeMap<>();
        Map<String, Requirement> reasons = new HashMap<>();
        Set<String> preferred;
        boolean audit;
        int failureDepth = -1;
        List<String> failure;
        Resolution(Set<String> preferred, boolean audit) {
            this.preferred = preferred;
            this.audit = audit;
        }
        boolean usable(PackageVersion p) {
            return (!p.yanked || installed.get(p.name) == p) && (!audit || !vulnerable(p));
        }
        void record(Requirement r, String reason, Requirement other) {
            if (selected.size() <= failureDepth) return;
            failureDepth = selected.size();
            failure = new ArrayList<>(List.of("UNSATISFIABLE"));
            for (String line : r.chain()) failure.add("  " + line);
            failure.add("  " + reason);
            if (other != null) for (String line : other.chain()) failure.add("    " + line);
        }
        boolean search(List<Requirement> pending) {
            if (pending.isEmpty()) return true;
            Requirement r = pending.getFirst();
            Clause clause = r.clause;
            String name = clause.name;
            List<Requirement> rest = pending.subList(1, pending.size());
            if (selected.containsKey(name)) {
                PackageVersion p = selected.get(name);
                if (clause.constraint.matches(p.version)) return search(rest);
                record(r, p + " was selected by:", reasons.get(name));
                return false;
            }
            List<PackageVersion> candidates = new ArrayList<>();
            if (held.contains(name)) {
                PackageVersion p = installed.get(name);
                if (!clause.constraint.matches(p.version) || !usable(p)) {
                    record(r, p + " is held", null);
                    return false;
                }
                candidates.add(p);
            } else {
                for (PackageVersion p : versions(name)) if (clause.constraint.matches(p.version) && usable(p)) candidates.add(p);
                PackageVersion current = installed.get(name);
                if (preferred.contains(name) && candidates.remove(current)) candidates.addFirst(current);
                if (candidates.isEmpty()) {
                    record(r, "no version of " + name + " matches " + clause.text, null);
                    return false;
                }
            }
            for (PackageVersion p : candidates) {
                PackageVersion conflict = null;
                for (PackageVersion q : selected.values()) {
                    if (p.conflicts.stream().anyMatch(d -> d.name.equals(q.name) && d.constraint.matches(q.version)) || q.conflicts.stream().anyMatch(d -> d.name.equals(name) && d.constraint.matches(p.version))) {
                        conflict = q;
                        break;
                    }
                }
                if (conflict != null) {
                    record(r, p + " conflicts with " + conflict + ", which was selected by:", reasons.get(conflict.name));
                    continue;
                }
                selected.put(name, p);
                reasons.put(name, r);
                List<Requirement> next = new ArrayList<>();
                for (Clause d : p.dependencies) next.add(new Requirement(d, p, r));
                next.addAll(rest);
                if (search(next)) return true;
                selected.remove(name);
                reasons.remove(name);
            }
            return false;
        }
        boolean solve(List<Clause> list) {
            return search(list.stream().map(c -> new Requirement(c, null, null)).toList());
        }
    }

    List<String> plan(TreeMap<String, PackageVersion> next) {
        List<String> out = new ArrayList<>();
        int[] counts = new int[4];
        Set<String> arranged = new HashSet<>();
        while (arranged.size() < next.size()) {
            String name = next.keySet().stream().filter(n -> !arranged.contains(n) && next.get(n).dependencies.stream().allMatch(d -> arranged.contains(d.name))).findFirst().orElseThrow();
            arranged.add(name);
            PackageVersion p = next.get(name), old = installed.get(name);
            if (old == null) {
                out.add("install " + p);
                counts[0]++;
            } else if (old != p) {
                boolean newer = p.version.compareTo(old.version) > 0;
                out.add((newer ? "upgrade " : "downgrade ") + name + " " + old.version.text + " -> " + p.version.text);
                counts[newer ? 1 : 2]++;
            }
        }
        TreeSet<String> removed = new TreeSet<>(installed.keySet());
        removed.removeAll(next.keySet());
        while (!removed.isEmpty()) {
            String name = removed.stream().filter(n -> removed.stream().noneMatch(q -> installed.get(q).dependencies.stream().anyMatch(d -> d.name.equals(n)))).findFirst().orElseThrow();
            out.add("remove " + installed.get(name));
            counts[3]++;
            removed.remove(name);
        }
        if (out.isEmpty()) out.add("no changes");
        else out.add(counts[0] + " installed, " + counts[1] + " upgraded, " + counts[2] + " downgraded, " + counts[3] + " removed");
        return out;
    }

    void update(List<Clause> list, TreeMap<String, PackageVersion> next) {
        history.push(new Snapshot(new ArrayList<>(requests), new TreeMap<>(installed)));
        requests = new ArrayList<>(list);
        installed = new TreeMap<>(next);
        held.retainAll(installed.keySet());
    }

    List<String> resolve(List<Clause> list, Set<String> preferred, boolean audit, boolean change) {
        Resolution r = new Resolution(preferred, audit);
        if (!r.solve(list)) return r.failure;
        List<String> result = plan(r.selected);
        if (change) update(list, r.selected);
        return result;
    }

    Clause request(String name) {
        return requests.stream().filter(r -> r.name.equals(name)).findFirst().orElse(null);
    }

    String requiredBy(String name) {
        return installed.keySet().stream().filter(n -> installed.get(n).dependencies.stream().anyMatch(d -> d.name.equals(name))).findFirst().orElseThrow();
    }

    Set<String> reachable(List<Clause> list) {
        Set<String> seen = new TreeSet<>();
        ArrayDeque<String> queue = new ArrayDeque<>();
        for (Clause c : list) if (seen.add(c.name)) queue.add(c.name);
        while (!queue.isEmpty()) for (Clause d : installed.get(queue.remove()).dependencies) if (seen.add(d.name)) queue.add(d.name);
        return seen;
    }

    void tree(String name, String constraint, String prefix, String indent, Set<String> seen, List<String> out) {
        PackageVersion p = installed.get(name);
        String body = prefix + p + (constraint == null ? "" : " [" + constraint + "]");
        if (!seen.add(name)) {
            out.add(body + " (*)");
            return;
        }
        out.add(body);
        for (int i = 0; i < p.dependencies.size(); i++) {
            Clause d = p.dependencies.get(i);
            boolean last = i + 1 == p.dependencies.size();
            tree(d.name, d.text, indent + (last ? "`-- " : "|-- "), indent + (last ? "    " : "|   "), seen, out);
        }
    }

    List<String> command(String line) {
        int space = line.indexOf(' ');
        String c = space < 0 ? line : line.substring(0, space), rest = space < 0 ? "" : line.substring(space + 1);
        String[] w = rest.split(" ", 3);
        List<String> out = new ArrayList<>();
        switch (c) {
            case "PKG" -> {
                String[] clauses = rest.split("; ", -1), header = clauses[0].split(" ");
                Version v = checkedVersion(header[1]);
                if (registered(header[0], header[1]) != null) fail(header[0] + "@" + header[1] + " is already registered");
                PackageVersion p = new PackageVersion(header[0], v);
                for (int i = 1; i < clauses.length; i++) {
                    String[] a = clauses[i].split(" ", 3);
                    Clause d = clause(a[1], a[2]);
                    (a[0].equals("DEP") ? p.dependencies : p.conflicts).add(d);
                }
                registry.computeIfAbsent(p.name, n -> new ArrayList<>()).add(p);
                registry.get(p.name).sort((a, b) -> b.version.compareTo(a.version));
                out.add("registered " + p);
            }
            case "YANK", "INFO" -> {
                PackageVersion p = checkedPackage(w[0], w[1]);
                if (c.equals("YANK")) {
                    if (p.yanked) fail(p + " is already yanked");
                    p.yanked = true;
                    out.add("yanked " + p);
                } else {
                    out.add(display(p));
                    for (Clause d : p.dependencies) out.add("  requires " + d.name + " " + d.text);
                    for (Clause d : p.conflicts) out.add("  conflicts with " + d.name + " " + d.text);
                    for (var a : advisories.entrySet()) if (a.getValue().name.equals(p.name) && a.getValue().constraint.matches(p.version)) out.add("  advisory " + a.getKey());
                }
            }
            case "VERSIONS", "INSTALL", "SIMULATE" -> {
                String name = w[0], text = rest.length() == name.length() ? null : rest.substring(name.length() + 1);
                Constraint constraint = text == null ? null : checkedConstraint(text);
                if (!registry.containsKey(name)) fail("unknown package " + name);
                if (c.equals("VERSIONS")) {
                    for (PackageVersion p : versions(name)) if (constraint == null || constraint.matches(p.version)) out.add(display(p));
                    if (out.isEmpty()) out.add("no matching versions");
                } else {
                    Clause requirement = text == null ? clause(name, "*") : new Clause(name, text, constraint);
                    List<Clause> list = new ArrayList<>(requests);
                    Clause old = request(name);
                    if (old == null) list.add(requirement);
                    else list.set(list.indexOf(old), requirement);
                    out = resolve(list, new HashSet<>(installed.keySet()), false, c.equals("INSTALL"));
                }
            }
            case "DEPENDENTS" -> {
                Version v = w.length > 1 ? checkedVersion(w[1]) : null;
                for (List<PackageVersion> list : registry.values()) for (PackageVersion p : list) for (Clause d : p.dependencies) if (d.name.equals(w[0]) && (v == null || d.constraint.matches(v))) out.add(p + " requires " + d.name + " " + d.text);
                if (out.isEmpty()) out.add("no dependents");
            }
            case "COMPARE" -> {
                Version a = checkedVersion(w[0]), b = checkedVersion(w[1]);
                out.add(w[0] + (a.compareTo(b) < 0 ? " < " : a.compareTo(b) > 0 ? " > " : " = ") + w[1]);
            }
            case "MATCH" -> {
                Version v = checkedVersion(w[0]);
                Constraint constraint = checkedConstraint(rest.substring(w[0].length() + 1));
                out.add(constraint.matches(v) ? "yes" : "no");
            }
            case "RANGE" -> out.add(checkedConstraint(rest).normal());
            case "REMOVE" -> {
                Clause old = request(rest);
                if (old == null) fail(installed.containsKey(rest) ? rest + " is required by " + requiredBy(rest) : rest + " is not installed");
                List<Clause> list = new ArrayList<>(requests);
                list.remove(old);
                Set<String> keep = reachable(list);
                if (keep.contains(rest)) {
                    out.add(installed.get(rest) + " is still required by " + requiredBy(rest));
                    update(list, installed);
                } else {
                    TreeMap<String, PackageVersion> next = new TreeMap<>(installed);
                    next.keySet().retainAll(keep);
                    out = plan(next);
                    update(list, next);
                }
            }
            case "UPGRADE" -> {
                if (!rest.isEmpty() && !installed.containsKey(rest)) fail(rest + " is not installed");
                Set<String> preferred = new HashSet<>();
                if (!rest.isEmpty()) {
                    preferred.addAll(installed.keySet());
                    preferred.remove(rest);
                }
                out = resolve(requests, preferred, false, true);
            }
            case "ROLLBACK" -> {
                if (history.isEmpty()) fail("nothing to roll back");
                Snapshot snapshot = history.pop();
                out = plan(snapshot.installed);
                requests = snapshot.requests;
                installed = snapshot.installed;
                held.retainAll(installed.keySet());
            }
            case "HOLD" -> {
                if (!installed.containsKey(rest)) fail(rest + " is not installed");
                if (!held.add(rest)) fail(rest + " is already held");
                out.add("held " + installed.get(rest));
            }
            case "UNHOLD" -> {
                if (!held.remove(rest)) fail(rest + " is not held");
                out.add("released " + rest);
            }
            case "WHY" -> {
                if (!installed.containsKey(rest)) fail(rest + " is not installed");
                if (request(rest) != null) out.add(installed.get(rest) + " is explicitly installed");
                else {
                    TreeSet<String> roots = new TreeSet<>();
                    for (Clause r : requests) roots.add(r.name);
                    Map<String, String> parent = new HashMap<>();
                    for (String root : roots) parent.put(root, null);
                    ArrayDeque<String> queue = new ArrayDeque<>(roots);
                    while (!queue.isEmpty()) {
                        String name = queue.remove();
                        List<String> children = installed.get(name).dependencies.stream().map(Clause::name).sorted().toList();
                        for (String child : children) if (!parent.containsKey(child)) {
                            parent.put(child, name);
                            queue.add(child);
                        }
                    }
                    List<String> path = new ArrayList<>();
                    for (String name = rest; name != null; name = parent.get(name)) path.add(installed.get(name).toString());
                    Collections.reverse(path);
                    out.add(String.join(" -> ", path));
                }
            }
            case "TREE" -> {
                if (!rest.isEmpty() && !installed.containsKey(rest)) fail(rest + " is not installed");
                Set<String> seen = new HashSet<>();
                List<String> roots = rest.isEmpty() ? requests.stream().map(Clause::name).sorted().toList() : List.of(rest);
                if (roots.isEmpty()) out.add("(empty)");
                for (String root : roots) {
                    Clause r = request(root);
                    tree(root, r == null ? null : r.text, "", "", seen, out);
                }
            }
            case "OUTDATED" -> {
                for (PackageVersion p : installed.values()) {
                    List<Constraint> relevant = new ArrayList<>();
                    Clause r = request(p.name);
                    if (r != null) relevant.add(r.constraint);
                    for (PackageVersion q : installed.values()) for (Clause d : q.dependencies) if (d.name.equals(p.name)) relevant.add(d.constraint);
                    PackageVersion wanted = versions(p.name).stream().filter(q -> (!q.yanked || q == p) && relevant.stream().allMatch(a -> a.matches(q.version))).findFirst().orElseThrow();
                    PackageVersion latest = versions(p.name).stream().filter(q -> !q.yanked && q.version.stable()).findFirst().orElse(null);
                    if (wanted != p || (latest != null && latest.version.compareTo(p.version) > 0)) out.add(p.name + " " + p.version.text + " " + wanted.version.text + " " + (latest == null ? "-" : latest.version.text));
                }
                if (out.isEmpty()) out.add("all packages are up to date");
            }
            case "LOCK" -> {
                for (PackageVersion p : installed.values()) out.add(p.toString());
                if (out.isEmpty()) out.add("(empty)");
            }
            case "STATUS" -> {
                for (Clause r : requests) out.add(r.name + " " + r.text + " -> " + installed.get(r.name).version.text);
                if (requests.isEmpty()) out.add("no requests");
                out.add(installed.size() + " installed, " + held.size() + " held, " + history.size() + " snapshots");
            }
            case "ADVISORY" -> {
                if (advisories.containsKey(w[0])) fail("advisory " + w[0] + " already exists");
                Clause a = clause(w[1], w[2]);
                advisories.put(w[0], a);
                out.add("advisory " + w[0] + " recorded");
            }
            case "AUDIT" -> {
                if (rest.equals("FIX")) out = resolve(requests, new HashSet<>(installed.keySet()), true, true);
                else {
                    for (PackageVersion p : installed.values()) {
                        List<String> ids = advisories.entrySet().stream().filter(e -> e.getValue().name.equals(p.name) && e.getValue().constraint.matches(p.version)).map(Map.Entry::getKey).toList();
                        if (ids.isEmpty()) continue;
                        PackageVersion fix = null;
                        for (PackageVersion q : versions(p.name)) if (q.version.compareTo(p.version) > 0 && q.version.stable() && !q.yanked && !vulnerable(q)) fix = q;
                        out.add(p + ": " + String.join(", ", ids) + (fix == null ? " (no fix)" : " (fix: " + fix.version.text + ")"));
                    }
                    if (out.isEmpty()) out.add("no known vulnerabilities");
                }
            }
            default -> throw new IllegalStateException();
        }
        return out;
    }

    public static void main(String[] args) throws IOException {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        Main manager = new Main();
        int n = Integer.parseInt(reader.readLine());
        for (int i = 0; i < n; i++) {
            try {
                for (String line : manager.command(reader.readLine())) System.out.println(line);
            } catch (Problem e) {
                System.out.println(e.getMessage());
            }
        }
    }
}
