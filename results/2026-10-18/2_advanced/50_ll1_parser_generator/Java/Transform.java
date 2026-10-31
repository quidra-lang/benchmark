import java.util.*;

final class Transform {
    record Result(GrammarParser.Grammar grammar, List<String> log) {}
    static String fresh(String lhs, GrammarParser.Grammar grammar) {
        String name = lhs.substring(0, lhs.length() - 1) + "'>";
        while (grammar.rules.containsKey(name))
            name = name.substring(0, name.length() - 1) + "'>";
        return name;
    }
    static boolean reaches(GrammarParser.Grammar grammar, String source, String target) {
        Set<String> seen = new HashSet<>();
        Deque<String> queue = new ArrayDeque<>();
        seen.add(source);
        queue.add(source);
        while (!queue.isEmpty()) {
            String current = queue.removeFirst();
            for (List<String> rhs : grammar.rules.get(current))
                if (!rhs.isEmpty() && GrammarParser.nonterminal(rhs.get(0))) {
                    String next = rhs.get(0);
                    if (next.equals(target))
                        return true;
                    if (seen.add(next))
                        queue.add(next);
                }
        }
        return false;
    }
    static List<List<String>> unique(List<List<String>> alternatives) {
        List<List<String>> result = new ArrayList<>();
        for (List<String> rhs : alternatives)
            if (!result.contains(rhs))
                result.add(rhs);
        return result;
    }
    static List<String> concatenate(List<String> a, List<String> b) {
        List<String> result = new ArrayList<>(a);
        result.addAll(b);
        return result;
    }
    static Result eliminate(GrammarParser.Grammar source) {
        GrammarParser.Grammar grammar = GrammarParser.copy(source);
        List<String> original = new ArrayList<>(grammar.order), log = new ArrayList<>();
        for (int i = 0; i < original.size(); i++) {
            String lhs = original.get(i);
            for (int j = 0; j < i; j++) {
                String earlier = original.get(j);
                boolean needed = false;
                for (List<String> rhs : grammar.rules.get(lhs))
                    if (!rhs.isEmpty() && rhs.get(0).equals(earlier))
                        needed = true;
                if (!needed || !reaches(grammar, earlier, lhs))
                    continue;
                List<List<String>> replacements = new ArrayList<>();
                for (List<String> rhs : grammar.rules.get(lhs))
                    if (!rhs.isEmpty() && rhs.get(0).equals(earlier)) {
                        for (List<String> delta : grammar.rules.get(earlier))
                            replacements.add(concatenate(delta, rhs.subList(1, rhs.size())));
                    } else
                        replacements.add(rhs);
                grammar.rules.put(lhs, unique(replacements));
                log.add("substitute " + earlier + " into " + lhs);
            }
            List<List<String>> recursive = new ArrayList<>(), nonrecursive = new ArrayList<>();
            for (List<String> rhs : grammar.rules.get(lhs)) {
                if (rhs.size() == 1 && rhs.get(0).equals(lhs)) {
                    log.add("remove cycle " + GrammarParser.production(lhs, rhs));
                    continue;
                }
                if (!rhs.isEmpty() && rhs.get(0).equals(lhs))
                    recursive.add(new ArrayList<>(rhs.subList(1, rhs.size())));
                else
                    nonrecursive.add(rhs);
            }
            if (recursive.isEmpty()) {
                grammar.rules.put(lhs, nonrecursive);
                continue;
            }
            String created = fresh(lhs, grammar);
            List<List<String>> left = new ArrayList<>(), right = new ArrayList<>();
            for (List<String> rhs : nonrecursive)
                left.add(concatenate(rhs, List.of(created)));
            for (List<String> rhs : recursive)
                right.add(concatenate(rhs, List.of(created)));
            right.add(new ArrayList<>());
            grammar.rules.put(lhs, left);
            grammar.rules.put(created, right);
            grammar.order.add(grammar.order.indexOf(lhs) + 1, created);
            log.add("eliminate left recursion in " + lhs + " with " + created);
        }
        return new Result(grammar, log);
    }
    static Result factor(GrammarParser.Grammar source) {
        GrammarParser.Grammar grammar = GrammarParser.copy(source);
        List<String> log = new ArrayList<>();
        for (int position = 0; position < grammar.order.size(); position++) {
            String lhs = grammar.order.get(position);
            List<List<String>> current = grammar.rules.get(lhs);
            List<String> insertions = new ArrayList<>();
            int index = 0;
            while (index < current.size()) {
                List<String> row = current.get(index);
                if (row.isEmpty()) {
                    index++;
                    continue;
                }
                List<Integer> group = new ArrayList<>();
                for (int i = 0; i < current.size(); i++)
                    if (!current.get(i).isEmpty() && current.get(i).get(0).equals(row.get(0)))
                        group.add(i);
                if (group.size() == 1) {
                    index++;
                    continue;
                }
                int length = row.size();
                for (int i : group)
                    length = Math.min(length, current.get(i).size());
                int prefix = 0;
                while (prefix < length) {
                    boolean same = true;
                    for (int i : group)
                        if (!current.get(i).get(prefix).equals(row.get(prefix)))
                            same = false;
                    if (!same)
                        break;
                    prefix++;
                }
                List<String> common = new ArrayList<>(row.subList(0, prefix));
                String created = fresh(lhs, grammar);
                List<List<String>> suffixes = new ArrayList<>();
                for (int i : group)
                    suffixes.add(new ArrayList<>(current.get(i).subList(prefix, current.get(i).size())));
                grammar.rules.put(created, suffixes);
                List<List<String>> replacement = new ArrayList<>();
                for (int i = 0; i < current.size(); i++)
                    if (i == group.get(0))
                        replacement.add(concatenate(common, List.of(created)));
                    else if (!group.contains(i))
                        replacement.add(current.get(i));
                grammar.rules.put(lhs, replacement);
                current = replacement;
                insertions.add(created);
                log.add("left factor " + lhs + " on " + GrammarParser.notation(common) + " with " + created);
                index = group.get(0) + 1;
            }
            grammar.order.addAll(position + 1, insertions);
        }
        return new Result(grammar, log);
    }
}
