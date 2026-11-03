import java.util.ArrayList;
import java.util.Collection;
import java.util.Comparator;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

record Edge(String first, String second, int shared) {}

final class ConflictGraph {
    final List<String> vertices;
    final Map<String, Map<String, Integer>> shared = new TreeMap<>();

    ConflictGraph(List<String> vertices, Collection<List<String>> students) {
        this.vertices = vertices.stream().sorted().toList();
        for (String vertex : vertices) shared.put(vertex, new TreeMap<>());
        for (List<String> ids : students)
            for (int i = 0; i < ids.size(); i++)
                for (int j = i + 1; j < ids.size(); j++) {
                    String first = ids.get(i), second = ids.get(j);
                    shared.get(first).merge(second, 1, Integer::sum);
                    shared.get(second).merge(first, 1, Integer::sum);
                }
    }

    Map<String, Integer> neighbours(String id) {
        return shared.getOrDefault(id, Map.of());
    }

    int degree(String id) {
        return neighbours(id).size();
    }

    int sharedTotal(String id) {
        return neighbours(id).values().stream().mapToInt(Integer::intValue).sum();
    }

    List<Edge> edges() {
        List<Edge> result = new ArrayList<>();
        for (String first : vertices)
            for (var entry : neighbours(first).entrySet())
                if (first.compareTo(entry.getKey()) < 0)
                    result.add(new Edge(first, entry.getKey(), entry.getValue()));
        return result;
    }

    List<List<String>> components() {
        Set<String> seen = new HashSet<>();
        List<List<String>> result = new ArrayList<>();
        for (String vertex : vertices) {
            if (!seen.add(vertex)) continue;
            List<String> component = new ArrayList<>(List.of(vertex));
            for (int i = 0; i < component.size(); i++)
                for (String neighbour : neighbours(component.get(i)).keySet())
                    if (seen.add(neighbour)) component.add(neighbour);
            component.sort(String::compareTo);
            result.add(component);
        }
        result.sort(Comparator.<List<String>>comparingInt(List::size).reversed()
            .thenComparing(component -> component.getFirst()));
        return result;
    }

    List<String> greedyClique(List<String> initial) {
        List<String> candidates = new ArrayList<>(initial), result = new ArrayList<>();
        Comparator<String> order = Comparator.<String>comparingInt(this::degree).reversed()
            .thenComparing(Comparator.naturalOrder());
        while (!candidates.isEmpty()) {
            String chosen = candidates.stream().min(order).orElseThrow();
            result.add(chosen);
            candidates.removeIf(id -> !neighbours(chosen).containsKey(id));
        }
        return result;
    }

    List<String> kempeChain(Map<String, Integer> assignment, String start, int first, int second) {
        Set<String> seen = new HashSet<>(Set.of(start));
        List<String> chain = new ArrayList<>(List.of(start));
        for (int i = 0; i < chain.size(); i++)
            for (String neighbour : neighbours(chain.get(i)).keySet()) {
                Integer slot = assignment.get(neighbour);
                if (slot != null && (slot == first || slot == second) && seen.add(neighbour))
                    chain.add(neighbour);
            }
        chain.sort(String::compareTo);
        return chain;
    }

    static boolean reachable(Map<String, List<String>> arrows, String source, String target) {
        List<String> stack = new ArrayList<>(List.of(source));
        Set<String> seen = new HashSet<>(Set.of(source));
        while (!stack.isEmpty()) {
            String node = stack.removeLast();
            if (node.equals(target)) return true;
            for (String next : arrows.getOrDefault(node, List.of()))
                if (seen.add(next)) stack.add(next);
        }
        return false;
    }
}
