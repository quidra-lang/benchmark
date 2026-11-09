import java.util.*;
final class Dfg {
    record Pair(String first, String second) {}
    record Trace(List<String> activities, long weight) {}
    static long count(Map<Pair, Long> counts, String first, String second) {
        return counts.getOrDefault(new Pair(first, second), 0L);
    }
    static Map<Pair, Long> counts(List<Trace> log) {
        Map<Pair, Long> result = new HashMap<>();
        for (Trace trace : log)
            for (int i = 1; i < trace.activities().size(); i++)
                result.merge(new Pair(trace.activities().get(i - 1), trace.activities().get(i)),
                             trace.weight(), Long::sum);
        return result;
    }
    static String basic(Map<Pair, Long> counts, String first, String second) {
        boolean forward = count(counts, first, second) > 0, reverse =
                                                                count(counts, second, first) > 0;
        return forward && !reverse ? "->" : reverse && !forward ? "<-" : forward ? "||" : "#";
    }
    static int compare(Pair a, Pair b) {
        int order = a.first().compareTo(b.first());
        return order != 0 ? order : a.second().compareTo(b.second());
    }
    static List<String> table(List<List<String>> cells, int width) {
        List<String> lines = new ArrayList<>();
        String header = "    ";
        for (int i = 1; i <= cells.size(); i++)
            header += String.format(Locale.ROOT, "%" + width + "s", i);
        lines.add(header);
        for (int i = 0; i < cells.size(); i++) {
            String line = String.format(Locale.ROOT, "%4s", i + 1);
            for (String cell : cells.get(i))
                line += String.format(Locale.ROOT, "%" + width + "s", cell);
            lines.add(line);
        }
        return lines;
    }
    static List<String> footprint(List<String> names, String[][] relation) {
        List<String> lines = new ArrayList<>();
        List<List<String>> rows = new ArrayList<>();
        for (int i = 0; i < names.size(); i++) {
            lines.add("ACTIVITY " + (i + 1) + " " + names.get(i));
            rows.add(Arrays.asList(relation[i]));
        }
        lines.addAll(table(rows, 4));
        return lines;
    }
}
