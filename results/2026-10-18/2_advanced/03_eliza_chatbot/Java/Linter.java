import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

final class Linter {
    private static final List<String> CODES = List.of("SYNTAX", "ORPHAN", "DUPLICATE", "KEY_NO_DECOMP", "KEY_UNREACHABLE", "SYNON_UNUSED", "PRE_CHAIN", "SYNON_UNKNOWN", "RULE_NO_REASM", "RULE_SHADOWED", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE");
    private static final Set<String> ERRORS = Set.of("SYNTAX", "ORPHAN", "DUPLICATE", "SYNON_UNKNOWN", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE");
    private static boolean move(Item item) { return item.kind().equals("GOTO") || item.kind().equals("RESTATE"); }
    private static boolean unknown(Rule rule, Script s) { return rule.pattern.stream().anyMatch(e -> e.charAt(0) == '@' && !s.groups.containsKey(e.substring(1))); }
    private static boolean reaches(Map<String, List<String>> graph, String start, String goal) {
        Set<String> seen = new HashSet<>(); ArrayDeque<String> pending = new ArrayDeque<>(); pending.push(start);
        while (!pending.isEmpty()) { String current = pending.pop(); if (current.equals(goal)) return true; if (!seen.add(current)) continue; for (String next : graph.get(current)) pending.push(next); }
        return false;
    }
    static List<Diagnostic> check(Script s) {
        List<Diagnostic> found = new ArrayList<>(s.diagnostics);
        Set<String> replacements = new HashSet<>(), targets = new HashSet<>(), used = new HashSet<>();
        Map<String, List<String>> graph = new LinkedHashMap<>();
        for (Substitution pre : s.pres) replacements.addAll(pre.replacement());
        for (Item item : s.items) if (move(item)) targets.add(item.arguments().getFirst());
        for (Rule rule : s.rules) for (String e : rule.pattern) if (e.charAt(0) == '@') used.add(e.substring(1));
        for (Keyword key : s.keywords) {
            List<String> edges = new ArrayList<>();
            for (Rule rule : key.decomps) for (Item item : rule.items) if (move(item) && s.keywordMap.containsKey(item.arguments().getFirst())) edges.add(item.arguments().getFirst());
            graph.put(key.word, edges);
        }
        for (Keyword key : s.keywords) {
            if (key.decomps.isEmpty()) found.add(new Diagnostic(key.line, "KEY_NO_DECOMP", "keyword " + key.word + " has no DECOMP"));
            if (s.pre.containsKey(key.word) && !replacements.contains(key.word) && !targets.contains(key.word)) found.add(new Diagnostic(key.line, "KEY_UNREACHABLE", "keyword " + key.word + " is replaced by PRE"));
        }
        for (Group group : s.groupList) if (!used.contains(group.name())) found.add(new Diagnostic(group.line(), "SYNON_UNUSED", "group " + group.name() + " is never used"));
        for (Substitution pre : s.pres) for (String word : pre.replacement()) if (s.pre.containsKey(word)) found.add(new Diagnostic(pre.line(), "PRE_CHAIN", "replacement " + word + " is itself replaced by PRE"));
        for (Keyword key : s.keywords) for (List<Rule> rules : List.of(key.memories, key.decomps)) for (int p = 0; p < rules.size(); p++) {
            Rule rule = rules.get(p);
            for (String e : rule.pattern) if (e.charAt(0) == '@' && !s.groups.containsKey(e.substring(1))) found.add(new Diagnostic(rule.line, "SYNON_UNKNOWN", "unknown group " + e.substring(1)));
            if (rule.items.isEmpty()) found.add(new Diagnostic(rule.line, "RULE_NO_REASM", "rule has no reassembly"));
            if (!unknown(rule, s)) for (Rule earlier : rules.subList(0, p)) if (!unknown(earlier, s) && Matcher.covers(earlier.pattern, rule.pattern, s.groups)) { found.add(new Diagnostic(rule.line, "RULE_SHADOWED", "pattern is shadowed by line " + earlier.line)); break; }
            int wildcards = (int) rule.pattern.stream().filter(Matcher::wildcard).count();
            for (Item item : rule.items) {
                List<Integer> refs = new ArrayList<>();
                if (item.kind().equals("REASM")) for (int i = 0; i + 3 <= item.text().length(); i++) if (ScriptLoader.reference(item.text().substring(i, i + 3))) refs.add(item.text().charAt(i + 1) - '0');
                if (item.kind().equals("RESTATE")) for (String a : item.arguments().subList(1, item.arguments().size())) if (ScriptLoader.reference(a)) refs.add(a.charAt(1) - '0');
                for (int n : refs) if (n == 0 || n > wildcards) found.add(new Diagnostic(item.line(), "REF_UNBOUND", "reference (" + n + ") is not bound"));
                if (!move(item)) continue;
                String target = item.arguments().getFirst();
                if (!s.keywordMap.containsKey(target)) found.add(new Diagnostic(item.line(), "TARGET_UNDEFINED", "target " + target + " is not a keyword"));
                else if (reaches(graph, target, key.word)) found.add(new Diagnostic(item.line(), "TARGET_CYCLE", "edge " + key.word + " -> " + target + " is on a cycle"));
            }
        }
        found.sort(Comparator.comparingInt(Diagnostic::line).thenComparingInt(d -> CODES.indexOf(d.code()))); return found;
    }
    static List<String> lines(List<Diagnostic> diagnostics) {
        if (diagnostics.isEmpty()) return List.of("OK");
        List<String> result = new ArrayList<>(); int errors = 0;
        for (Diagnostic d : diagnostics) { result.add(d.line() + " " + d.code() + " " + d.message()); if (ERRORS.contains(d.code())) errors++; }
        result.add("TOTAL " + diagnostics.size() + " errors=" + errors + " warnings=" + (diagnostics.size() - errors)); return result;
    }
}
