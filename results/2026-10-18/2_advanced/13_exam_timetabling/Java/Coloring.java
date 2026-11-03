import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.BiFunction;

record Chosen(String course, int saturation) {}

final class Attempt {
    final List<String> courses;
    final ConflictGraph graph;
    final int limit;
    final BiFunction<String, Map<String, Integer>, List<Integer>> candidateSlots;
    final List<Chosen> chosen = new ArrayList<>();
    int deadEnds;
    String deadEndCourse;
    boolean aborted;

    Attempt(List<String> courses, ConflictGraph graph, int limit,
            BiFunction<String, Map<String, Integer>, List<Integer>> candidateSlots) {
        this.courses = courses;
        this.graph = graph;
        this.limit = limit;
        this.candidateSlots = candidateSlots;
    }

    int saturation(String id, Map<String, Integer> assignment) {
        Set<Integer> slots = new HashSet<>();
        for (String other : graph.neighbours(id).keySet())
            if (assignment.containsKey(other)) slots.add(assignment.get(other));
        return slots.size();
    }

    boolean search(Map<String, Integer> assignment) {
        Comparator<String> order = Comparator.<String>comparingInt(id -> saturation(id, assignment))
            .reversed().thenComparing(Comparator.<String>comparingInt(graph::degree).reversed())
            .thenComparing(Comparator.naturalOrder());
        String id = courses.stream().filter(course -> !assignment.containsKey(course))
            .min(order).orElse(null);
        if (id == null) return true;
        chosen.add(new Chosen(id, saturation(id, assignment)));
        for (int slot : candidateSlots.apply(id, assignment)) {
            assignment.put(id, slot);
            if (search(assignment)) return true;
            assignment.remove(id);
            if (aborted) return false;
        }
        chosen.removeLast();
        deadEnds++;
        deadEndCourse = id;
        aborted = deadEnds > limit;
        return false;
    }
}

final class Coloring {
    static int greedyNumbering(List<String> order, ConflictGraph graph) {
        Map<String, Integer> numbers = new HashMap<>();
        int maximum = 0;
        for (String id : order) {
            Set<Integer> taken = new HashSet<>();
            for (String other : graph.neighbours(id).keySet())
                if (numbers.containsKey(other)) taken.add(numbers.get(other));
            int number = 1;
            while (taken.contains(number)) number++;
            numbers.put(id, number);
            maximum = Math.max(maximum, number);
        }
        return maximum;
    }
}
