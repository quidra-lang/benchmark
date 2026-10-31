import java.util.*;

final class FirstFollow {
    static List<String> terminalOrder(Collection<String> terminals) {
        List<String> result = new ArrayList<>();
        boolean end = false;
        for (String terminal : terminals)
            if (terminal.equals("$"))
                end = true;
            else
                result.add(terminal);
        Collections.sort(result);
        if (end)
            result.add("$");
        return result;
    }
    static Set<String> terminals(GrammarParser.Grammar grammar) {
        Set<String> result = new HashSet<>();
        for (String lhs : grammar.order)
            for (List<String> rhs : grammar.rules.get(lhs))
                for (String symbol : rhs)
                    if (!GrammarParser.nonterminal(symbol))
                        result.add(symbol);
        return result;
    }
    record Sequence(Set<String> first, boolean empty) {}
    static final class Sets {
        Map<String, Boolean> nullable = new HashMap<>();
        Map<String, Set<String>> first = new HashMap<>(), follow = new HashMap<>();
        int nullablePasses, firstPasses, followPasses;
        List<String> terminals;
    }
    static Sequence sequence(List<String> rhs, Sets sets) {
        Set<String> result = new HashSet<>();
        for (String symbol : rhs) {
            if (!GrammarParser.nonterminal(symbol)) {
                result.add(symbol);
                return new Sequence(result, false);
            }
            result.addAll(sets.first.get(symbol));
            if (!sets.nullable.get(symbol))
                return new Sequence(result, false);
        }
        return new Sequence(result, true);
    }
    static Sets analyze(GrammarParser.Grammar grammar) {
        Sets sets = new Sets();
        for (String lhs : grammar.order) {
            sets.nullable.put(lhs, false);
            sets.first.put(lhs, new HashSet<>());
            sets.follow.put(lhs, new HashSet<>());
        }
        sets.follow.get(grammar.start).add("$");
        boolean changed;
        do {
            sets.nullablePasses++;
            changed = false;
            for (String lhs : grammar.order)
                if (!sets.nullable.get(lhs))
                    for (List<String> rhs : grammar.rules.get(lhs)) {
                        boolean empty = true;
                        for (String symbol : rhs)
                            if (!GrammarParser.nonterminal(symbol) || !sets.nullable.get(symbol))
                                empty = false;
                        if (empty) {
                            sets.nullable.put(lhs, true);
                            changed = true;
                            break;
                        }
                    }
        } while (changed);
        do {
            sets.firstPasses++;
            changed = false;
            for (String lhs : grammar.order)
                for (List<String> rhs : grammar.rules.get(lhs))
                    if (sets.first.get(lhs).addAll(sequence(rhs, sets).first()))
                        changed = true;
        } while (changed);
        do {
            sets.followPasses++;
            changed = false;
            for (String lhs : grammar.order)
                for (List<String> rhs : grammar.rules.get(lhs))
                    for (int i = 0; i < rhs.size(); i++) {
                        String symbol = rhs.get(i);
                        if (!GrammarParser.nonterminal(symbol))
                            continue;
                        Sequence suffix = sequence(rhs.subList(i + 1, rhs.size()), sets);
                        Set<String> more = new HashSet<>(suffix.first());
                        if (suffix.empty())
                            more.addAll(sets.follow.get(lhs));
                        if (sets.follow.get(symbol).addAll(more))
                            changed = true;
                    }
        } while (changed);
        sets.terminals = terminalOrder(terminals(grammar));
        return sets;
    }
}
