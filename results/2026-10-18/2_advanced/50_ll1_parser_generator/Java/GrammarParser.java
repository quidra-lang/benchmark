import java.util.*;

final class GrammarParser {
    static final class Grammar {
        List<String> order = new ArrayList<>();
        Map<String, List<List<String>>> rules = new LinkedHashMap<>();
        String start;
        Set<String> declared = new HashSet<>();
        boolean hasDeclaration;
        Map<String, Integer> words = new HashMap<>();
        List<String> diagnostics = new ArrayList<>();
    }
    record Token(String kind, String value, int start, int end) {}
    record Parsed(String kind, String lhs, List<List<String>> alternatives, List<String> words, int error) {}
    static boolean nonterminal(String symbol) {
        return symbol.startsWith("<") && symbol.endsWith(">");
    }
    static boolean letter(char c) {
        return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z';
    }
    static boolean word(char c) {
        return letter(c) || c >= '0' && c <= '9' || c == '_';
    }
    static List<Token> lex(String line) {
        List<Token> tokens = new ArrayList<>();
        int i = 0;
        while (i < line.length()) {
            char c = line.charAt(i);
            if (c == ' ') {
                i++;
                continue;
            }
            if (c == '#')
                break;
            int start = i;
            String kind = "invalid", value = Character.toString(c);
            if (c == '<') {
                int j = i + 1;
                if (j < line.length() && letter(line.charAt(j))) {
                    j++;
                    while (j < line.length() && word(line.charAt(j)))
                        j++;
                    if (j < line.length() && line.charAt(j) == '>') {
                        kind = "nonterminal";
                        i = j + 1;
                        value = line.substring(start, i);
                    }
                }
            } else if (c == '"') {
                int j = i + 1;
                while (j < line.length() && line.charAt(j) != ' ' && line.charAt(j) != '"')
                    j++;
                if (j > i + 1 && j < line.length() && line.charAt(j) == '"') {
                    kind = "terminal";
                    value = line.substring(i + 1, j);
                    i = j + 1;
                }
            } else if (letter(c)) {
                int j = i + 1;
                while (j < line.length() && word(line.charAt(j)))
                    j++;
                kind = "word";
                i = j;
                value = line.substring(start, i);
            } else if (line.startsWith("::=", i)) {
                kind = "definition";
                value = "::=";
                i += 3;
            } else if (c == '|') {
                kind = "separator";
                value = "|";
                i++;
            } else if (c == '%') {
                int j = i + 1;
                while (j < line.length() && letter(line.charAt(j)))
                    j++;
                String directive = line.substring(i + 1, j);
                if (List.of("empty", "start", "token").contains(directive)) {
                    kind = "directive";
                    value = "%" + directive;
                    i = j;
                }
            }
            if (kind.equals("invalid"))
                i = start + 1;
            tokens.add(new Token(kind, value, start + 1, i));
            if (kind.equals("invalid"))
                break;
        }
        return tokens;
    }
    static int error(List<Token> tokens, int cursor) {
        return cursor < tokens.size() ? tokens.get(cursor).start() : tokens.getLast().end() + 1;
    }
    static Parsed bad(List<Token> tokens, int cursor) {
        return new Parsed("", null, null, null, error(tokens, cursor));
    }
    static boolean symbol(Token token) {
        return List.of("nonterminal", "terminal", "word").contains(token.kind());
    }
    static Parsed alternatives(List<Token> tokens, int cursor, String kind, String lhs) {
        List<List<String>> alternatives = new ArrayList<>();
        while (true) {
            if (cursor >= tokens.size())
                return bad(tokens, cursor);
            Token first = tokens.get(cursor);
            List<String> alternative = new ArrayList<>();
            if (first.kind().equals("directive") && first.value().equals("%empty")) {
                cursor++;
                if (cursor < tokens.size() && !tokens.get(cursor).kind().equals("separator"))
                    return bad(tokens, cursor);
            } else if (symbol(first)) {
                while (cursor < tokens.size() && symbol(tokens.get(cursor)))
                    alternative.add(tokens.get(cursor++).value());
            } else
                return bad(tokens, cursor);
            alternatives.add(alternative);
            if (cursor >= tokens.size())
                return new Parsed(kind, lhs, alternatives, null, 0);
            if (!tokens.get(cursor).kind().equals("separator"))
                return bad(tokens, cursor);
            cursor++;
        }
    }
    static Parsed line(List<Token> tokens) {
        if (tokens.isEmpty())
            return new Parsed("blank", null, null, null, 0);
        Token first = tokens.get(0);
        if (first.kind().equals("nonterminal")) {
            if (tokens.size() < 2)
                return bad(tokens, tokens.size());
            if (!tokens.get(1).kind().equals("definition"))
                return bad(tokens, 1);
            return alternatives(tokens, 2, "rule", first.value());
        }
        if (first.kind().equals("separator"))
            return alternatives(tokens, 1, "continuation", null);
        if (first.kind().equals("directive") && first.value().equals("%start")) {
            if (tokens.size() < 2)
                return bad(tokens, tokens.size());
            if (!tokens.get(1).kind().equals("nonterminal"))
                return bad(tokens, 1);
            if (tokens.size() > 2)
                return bad(tokens, 2);
            return new Parsed("start", tokens.get(1).value(), null, null, 0);
        }
        if (first.kind().equals("directive") && first.value().equals("%token")) {
            if (tokens.size() < 2)
                return bad(tokens, tokens.size());
            List<String> words = new ArrayList<>();
            for (int i = 1; i < tokens.size(); i++) {
                if (!tokens.get(i).kind().equals("word"))
                    return bad(tokens, i);
                words.add(tokens.get(i).value());
            }
            return new Parsed("declaration", null, null, words, 0);
        }
        return bad(tokens, 0);
    }
    static String notation(List<String> symbols) {
        return symbols.isEmpty() ? "%empty" : String.join(" ", symbols);
    }
    static String production(String lhs, List<String> rhs) {
        return lhs + " -> " + notation(rhs);
    }
    static Grammar parse(List<String> lines) {
        Grammar grammar = new Grammar();
        String attachment = null;
        for (int i = 0; i < lines.size(); i++) {
            int number = i + 1;
            List<Token> tokens = lex(lines.get(i));
            Parsed parsed = line(tokens);
            if (parsed.error() > 0) {
                grammar.diagnostics.add("line " + number + ": syntax error at column " + parsed.error());
                attachment = null;
                continue;
            }
            if (parsed.kind().equals("blank"))
                continue;
            String lhs = parsed.lhs();
            if (parsed.kind().equals("rule")) {
                attachment = lhs;
                if (!grammar.rules.containsKey(lhs)) {
                    grammar.order.add(lhs);
                    grammar.rules.put(lhs, new ArrayList<>());
                }
            } else if (parsed.kind().equals("continuation")) {
                if (attachment == null) {
                    grammar.diagnostics.add("line " + number + ": continuation without a rule");
                    continue;
                }
                lhs = attachment;
            } else if (parsed.kind().equals("start")) {
                attachment = null;
                if (grammar.start == null)
                    grammar.start = lhs;
                else
                    grammar.diagnostics.add("line " + number + ": duplicate %start");
            } else {
                attachment = null;
                grammar.hasDeclaration = true;
                grammar.declared.addAll(parsed.words());
            }
            if (parsed.kind().equals("rule") || parsed.kind().equals("continuation")) {
                for (Token token : tokens)
                    if (token.kind().equals("word"))
                        grammar.words.putIfAbsent(token.value(), number);
                for (List<String> alternative : parsed.alternatives()) {
                    if (grammar.rules.get(lhs).contains(alternative))
                        grammar.diagnostics.add("line " + number + ": duplicate alternative " +
                                                production(lhs, alternative));
                    else
                        grammar.rules.get(lhs).add(alternative);
                }
            }
        }
        if (grammar.start == null)
            grammar.start = grammar.order.get(0);
        return grammar;
    }
    static Grammar copy(Grammar original) {
        Grammar result = new Grammar();
        result.order.addAll(original.order);
        result.start = original.start;
        for (String lhs : original.order) {
            List<List<String>> alternatives = new ArrayList<>();
            for (List<String> rhs : original.rules.get(lhs))
                alternatives.add(new ArrayList<>(rhs));
            result.rules.put(lhs, alternatives);
        }
        return result;
    }
}
