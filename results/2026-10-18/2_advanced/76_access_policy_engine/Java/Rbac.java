import java.nio.file.*;
import java.util.*;
final class Rbac {
    record Permission(String action, String type) {}
    record Grant(String role, String action, String type) {}
    record Constraint(String name, int cardinality, Set<String> roles) {}
    record Assignment(String user, String role, int first, int last) {}
    record Diagnostic(int line, String keyword, String message) {}
    record Line(int number, String[] fields) {}
    Set<String> roles = new TreeSet<>();
    Map<String, Set<String>> inherits = new HashMap<>();
    Map<String, Set<Permission>> permissions = new HashMap<>();
    List<Constraint> ssd = new ArrayList<>(), dsd = new ArrayList<>();
    List<Assignment> assignments = new ArrayList<>();
    List<Diagnostic> diagnostics = new ArrayList<>();
    Set<Grant> grants = new TreeSet<>(
        Comparator.comparing(Grant::role).thenComparing(Grant::action).thenComparing(Grant::type));
    Rbac() throws Exception {
        List<Line> lines = new ArrayList<>();
        for (String line : Files.readAllLines(Path.of("input", "rbac.txt")))
            lines.add(new Line(lines.size() + 1, line.split(" ")));
        for (String keyword : List.of("ROLE", "INHERITS", "PERMIT", "SSD", "DSD", "ASSIGN"))
            for (Line line : lines)
                if (line.fields()[0].equals(keyword)) {
                    String error =
                        accept(keyword, Arrays.copyOfRange(line.fields(), 1, line.fields().length));
                    if (error != null)
                        diagnostics.add(new Diagnostic(line.number(), keyword, error));
                }
        diagnostics.sort(Comparator.comparingInt(Diagnostic::line));
    }
    Set<String> closure(Collection<String> initial) {
        Set<String> reached = new TreeSet<>(initial);
        Deque<String> pending = new ArrayDeque<>(initial);
        while (!pending.isEmpty())
            for (String junior : inherits.get(pending.removeLast()))
                if (reached.add(junior))
                    pending.add(junior);
        return reached;
    }
    List<String> path(String start, String finish, Set<String> failed) {
        if (start.equals(finish))
            return new ArrayList<>(List.of(start));
        if (failed.contains(start))
            return null;
        for (String junior : new TreeSet<>(inherits.get(start))) {
            List<String> suffix = path(junior, finish, failed);
            if (suffix != null) {
                suffix.addFirst(start);
                return suffix;
            }
        }
        failed.add(start);
        return null;
    }
    Set<String> assigned(String user, int day) {
        Set<String> result = new TreeSet<>();
        for (Assignment assignment : assignments)
            if (assignment.user().equals(user) && assignment.first() <= day &&
                day <= assignment.last())
                result.add(assignment.role());
        return result;
    }
    Set<String> authorized(String user, int day) { return closure(assigned(user, day)); }
    String accept(String keyword, String[] f) {
        String role = f[0];
        switch (keyword) {
        case "ROLE":
            if (roles.contains(role))
                return "duplicate role " + role;
            roles.add(role);
            inherits.put(role, new TreeSet<>());
            permissions.put(role, new HashSet<>());
            break;
        case "INHERITS": {
            String senior = f[0], junior = f[1];
            for (String name : List.of(senior, junior))
                if (!roles.contains(name))
                    return "unknown role " + name;
            if (inherits.get(senior).contains(junior))
                return "duplicate inheritance " + senior + " " + junior;
            if (closure(List.of(junior)).contains(senior)) {
                List<String> cycle = path(junior, senior, new HashSet<>());
                cycle.addFirst(senior);
                return "cycle " + String.join(" > ", cycle);
            }
            inherits.get(senior).add(junior);
            break;
        }
        case "PERMIT":
            if (!roles.contains(role))
                return "unknown role " + role;
            Permission permission = new Permission(f[1], f[2]);
            if (!permissions.get(role).add(permission))
                return "duplicate permission " + String.join(" ", f);
            grants.add(new Grant(role, f[1], f[2]));
            break;
        case "SSD", "DSD": {
            List<Constraint> constraints = keyword.equals("SSD") ? ssd : dsd;
            for (Constraint constraint : constraints)
                if (constraint.name().equals(f[0]))
                    return "duplicate constraint " + f[0];
            String[] names = f[2].split(",");
            for (String name : names)
                if (!roles.contains(name))
                    return "unknown role " + name;
            int cardinality = Integer.parseInt(f[1]);
            if (cardinality < 2 || cardinality > names.length)
                return "bad cardinality " + f[0] + " " + cardinality;
            constraints.add(new Constraint(f[0], cardinality, new TreeSet<>(Arrays.asList(names))));
            break;
        }
        default: {
            String user = f[0];
            role = f[1];
            if (!roles.contains(role))
                return "unknown role " + role;
            int first = Integer.parseInt(f[2]), last = Integer.parseInt(f[3]);
            if (first < 1 || first > last || last > 365)
                return "bad range " + first + " " + last;
            for (Constraint constraint : ssd)
                for (int day = first; day <= last; day++) {
                    Set<String> assigned = assigned(user, day);
                    assigned.add(role);
                    Set<String> intersection = closure(assigned);
                    intersection.retainAll(constraint.roles());
                    if (intersection.size() >= constraint.cardinality())
                        return "ssd " + constraint.name() + " day " + day + " roles " +
                            String.join(",", intersection);
                }
            assignments.add(new Assignment(user, role, first, last));
        }
        }
        return null;
    }
}
