import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;

final class Matcher {
    static boolean wildcard(String e) { return e.equals("*") || e.equals("#") || e.charAt(0) == '@'; }
    static List<List<String>> match(List<String> pattern, List<String> words, Map<String, Set<String>> groups) {
        List<List<String>> bindings = new ArrayList<>();
        return visit(pattern, words, groups, 0, 0, bindings) ? bindings : null;
    }
    private static boolean visit(List<String> pattern, List<String> words, Map<String, Set<String>> groups, int position, int start, List<List<String>> bindings) {
        if (position == pattern.size()) return start == words.size();
        String e = pattern.get(position); int low = start, high = words.size();
        if (!e.equals("*")) {
            if (start == words.size()) return false;
            boolean fits = e.equals("#") || e.equals(words.get(start));
            if (e.charAt(0) == '@') fits = groups.getOrDefault(e.substring(1), Set.of()).contains(words.get(start));
            if (!fits) return false;
            low = high = start + 1;
        }
        for (int end = low; end <= high; end++) {
            if (wildcard(e)) bindings.add(new ArrayList<>(words.subList(start, end)));
            if (visit(pattern, words, groups, position + 1, end, bindings)) return true;
            if (wildcard(e)) bindings.removeLast();
        }
        return false;
    }
    private static boolean one(String a, String b, Map<String, Set<String>> groups) {
        if (a.equals("#")) return !b.equals("*");
        if (a.charAt(0) != '@') return a.equals(b);
        Set<String> members = groups.get(a.substring(1));
        return b.charAt(0) == '@' ? members.containsAll(groups.get(b.substring(1))) : members.contains(b);
    }
    static boolean covers(List<String> earlier, List<String> later, Map<String, Set<String>> groups) { return covering(earlier, later, groups, 0, 0); }
    private static boolean covering(List<String> earlier, List<String> later, Map<String, Set<String>> groups, int position, int start) {
        if (position == earlier.size()) return start == later.size();
        if (earlier.get(position).equals("*")) {
            for (int end = start; end <= later.size(); end++) if (covering(earlier, later, groups, position + 1, end)) return true;
            return false;
        }
        return start < later.size() && one(earlier.get(position), later.get(start), groups) && covering(earlier, later, groups, position + 1, start + 1);
    }
}
