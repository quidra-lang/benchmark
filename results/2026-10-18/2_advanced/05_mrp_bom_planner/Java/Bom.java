import java.io.IOException;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

record Edge(String parent, String child, long quantity, long scrap) { long need(long units) { return (units * quantity * (100 + scrap) + 99) / 100; } }
final class Bom {
    final Map<String, List<Edge>> children = new TreeMap<>(), parents = new TreeMap<>();
    boolean manufactured(String item) { return !children.get(item).isEmpty(); }
    boolean topLevel(String item) { return manufactured(item) && parents.get(item).isEmpty(); }
    private List<String> path(String start, String goal, Set<String> visited) {
        if (start.equals(goal)) return new ArrayList<>(List.of(start)); visited.add(start);
        for (Edge edge : children.get(start)) if (!visited.contains(edge.child())) { List<String> rest = path(edge.child(), goal, visited); if (rest != null) { rest.addFirst(start); return rest; } }
        return null;
    }
    int lowLevel(String item, Map<String, Integer> codes) {
        if (codes.containsKey(item)) return codes.get(item); int code = 0;
        for (Edge edge : parents.get(item)) code = Math.max(code, lowLevel(edge.parent(), codes) + 1); codes.put(item, code); return code;
    }
    int cumulative(String item, Map<String, Item> items, Map<String, Integer> times) {
        if (times.containsKey(item)) return times.get(item); int longest = 0;
        for (Edge edge : children.get(item)) longest = Math.max(longest, cumulative(edge.child(), items, times)); int value = items.get(item).lead() + longest; times.put(item, value); return value;
    }
    static Bom read(Map<String, Item> items, List<String> errors) throws IOException {
        Bom bom = new Bom(); for (String id : items.keySet()) { bom.children.put(id, new ArrayList<>()); bom.parents.put(id, new ArrayList<>()); }
        for (Main.Row row : Main.rows("bom.csv")) {
            String[] f = row.fields(); Edge edge = new Edge(f[0], f[1], Long.parseLong(f[2]), Long.parseLong(f[3])); String error = "";
            if (!items.containsKey(edge.parent())) error = "unknown item " + edge.parent();
            else if (!items.containsKey(edge.child())) error = "unknown item " + edge.child();
            else if (edge.quantity() < 1) error = "bad quantity " + edge.quantity();
            else if (edge.scrap() > 50) error = "bad scrap " + edge.scrap();
            else if (edge.parent().equals(edge.child())) error = "cycle " + edge.parent() + " -> " + edge.parent();
            else if (bom.children.get(edge.parent()).stream().anyMatch(e -> e.child().equals(edge.child()))) error = "duplicate " + edge.parent() + " -> " + edge.child();
            else { List<String> path = bom.path(edge.child(), edge.parent(), new HashSet<>()); if (path != null) error = "cycle " + edge.parent() + " -> " + String.join(" -> ", path); }
            if (!error.isEmpty()) { Main.error(errors, "bom.csv", row.line(), error); continue; }
            bom.children.get(edge.parent()).add(edge); bom.children.get(edge.parent()).sort(Comparator.comparing(Edge::child)); bom.parents.get(edge.child()).add(edge); bom.parents.get(edge.child()).sort(Comparator.comparing(Edge::parent));
        }
        return bom;
    }
}
