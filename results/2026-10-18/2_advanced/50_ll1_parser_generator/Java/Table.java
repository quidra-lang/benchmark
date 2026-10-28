import java.util.*;

final class Table {
    static final class Production {
        int number;
        String lhs;
        List<String> rhs;
        Map<String, String> predict = new HashMap<>();
        Production(int number, String lhs, List<String> rhs) {
            this.number = number;
            this.lhs = lhs;
            this.rhs = rhs;
        }
        String notation() {
            return GrammarParser.production(lhs, rhs);
        }
    }
    record Cell(String lhs, String terminal) {}
    record Conflict(Cell cell, String kind, int chosen) {}
    static final class Result {
        List<Production> productions = new ArrayList<>();
        Map<Cell, List<Integer>> cells = new HashMap<>();
        Map<Cell, Integer> choices = new HashMap<>();
        List<Conflict> conflicts = new ArrayList<>();
    }
    static Result build(GrammarParser.Grammar grammar, FirstFollow.Sets sets) {
        Result result = new Result();
        for (String lhs : grammar.order)
            for (List<String> rhs : grammar.rules.get(lhs))
                result.productions.add(new Production(result.productions.size() + 1, lhs, rhs));
        List<String> terminals = new ArrayList<>(sets.terminals);
        terminals.add("$");
        for (String lhs : grammar.order)
            for (String terminal : terminals)
                result.cells.put(new Cell(lhs, terminal), new ArrayList<>());
        for (Production production : result.productions) {
            FirstFollow.Sequence direct = FirstFollow.sequence(production.rhs, sets);
            for (String terminal : direct.first())
                production.predict.put(terminal, "FIRST");
            if (direct.empty())
                for (String terminal : sets.follow.get(production.lhs))
                    production.predict.putIfAbsent(terminal, "FOLLOW");
            for (String terminal : FirstFollow.terminalOrder(production.predict.keySet()))
                result.cells.get(new Cell(production.lhs, terminal)).add(production.number);
        }
        for (String lhs : grammar.order)
            for (String terminal : terminals) {
                Cell cell = new Cell(lhs, terminal);
                List<Integer> entries = result.cells.get(cell);
                if (entries.isEmpty())
                    continue;
                int chosen = entries.get(0);
                boolean first = false, follow = false;
                for (int number : entries) {
                    String reason = result.productions.get(number - 1).predict.get(terminal);
                    if (reason.equals("FIRST")) {
                        if (!first)
                            chosen = number;
                        first = true;
                    } else
                        follow = true;
                }
                result.choices.put(cell, chosen);
                if (entries.size() > 1)
                    result.conflicts.add(new Conflict(cell,
                                                      first && follow ? "FIRST/FOLLOW"
                                                      : first         ? "FIRST/FIRST"
                                                                      : "FOLLOW/FOLLOW",
                                                      chosen));
            }
        return result;
    }
}
