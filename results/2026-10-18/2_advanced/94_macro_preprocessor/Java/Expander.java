import java.util.*;
final class Expander {
    @FunctionalInterface
    interface Diagnostic {
        void record(Definitions.Position position, String kind, String message);
    }
    Map<String, Definitions.Macro> macros;
    Diagnostic diagnostic;
    int counter;
    Map<String, Integer> builtinCounts = new HashMap<>();
    Expander(Map<String, Definitions.Macro> macros, Diagnostic diagnostic) {
        this.macros = macros;
        this.diagnostic = diagnostic;
    }
    void error(Main.Inclusion context, Lexer.Token token, String message) {
        diagnostic.record(context.position(token.line()), "error", message);
    }
    Lexer.Token builtin(Lexer.Token token, Main.Inclusion context) {
        builtinCounts.merge(token.spelling(), 1, Integer::sum);
        String kind = "number", spelling;
        if (token.spelling().equals("__FILE__")) {
            kind = "string";
            spelling = "\"" + context.displayFile + "\"";
        } else if (token.spelling().equals("__LINE__"))
            spelling = Integer.toString(context.position(token.line()).line());
        else
            spelling = Integer.toString(counter++);
        return new Lexer.Token(kind, spelling, token.line(), token.space());
    }
    record Collected(Map<String, List<Lexer.Token>> raw, int consumed, Lexer.Token closing) {}
    Collected collect(Deque<Lexer.Token> pending, Definitions.Macro macro, Lexer.Token token,
                      Main.Inclusion context) {
        List<List<Lexer.Token>> arguments = new ArrayList<>();
        arguments.add(new ArrayList<>());
        List<Lexer.Token> separators = new ArrayList<>();
        int nesting = 0, index = 0, consumed = 0;
        Lexer.Token closing = null;
        for (Lexer.Token current : pending) {
            if (index++ == 0)
                continue;
            if (current.spelling().equals(")") && nesting == 0) {
                closing = current;
                consumed = index;
                break;
            }
            if (current.spelling().equals(",") && nesting == 0) {
                separators.add(current);
                arguments.add(new ArrayList<>());
            } else {
                if (current.spelling().equals("("))
                    nesting++;
                else if (current.spelling().equals(")"))
                    nesting--;
                arguments.getLast().add(current);
            }
        }
        if (closing == null) {
            error(context, token,
                  "unterminated argument list invoking macro \"" + macro.name + "\"");
            return null;
        }
        int count = arguments.size(), fixed = macro.parameters.size() - (macro.variadic ? 1 : 0);
        String message = null;
        if (!macro.variadic && fixed == 0 && (count != 1 || !arguments.getFirst().isEmpty()))
            message =
                "macro \"" + macro.name + "\" passed " + count + " arguments, but takes just 0";
        else if (count < fixed)
            message = "macro \"" + macro.name + "\" requires " + fixed + " arguments, but only " +
                      count + " given";
        else if (count > fixed && !macro.variadic)
            message = "macro \"" + macro.name + "\" passed " + count +
                      " arguments, but takes just " + fixed;
        if (message != null) {
            error(context, token, message);
            return null;
        }
        Map<String, List<Lexer.Token>> raw = new HashMap<>();
        for (int i = 0; i < fixed; i++)
            raw.put(macro.parameters.get(i), arguments.get(i));
        if (macro.variadic) {
            List<Lexer.Token> variable = new ArrayList<>();
            for (int i = fixed; i < count; i++) {
                if (i > fixed)
                    variable.add(separators.get(i - 1));
                variable.addAll(arguments.get(i));
            }
            raw.put(Definitions.VARIADIC, variable);
        }
        return new Collected(raw, consumed, closing);
    }
    Lexer.Token stringize(List<Lexer.Token> tokens, Lexer.Token sharp) {
        StringBuilder text = new StringBuilder("\"");
        for (int i = 0; i < tokens.size(); i++) {
            Lexer.Token token = tokens.get(i);
            if (i > 0 && token.space())
                text.append(' ');
            String spelling = token.spelling();
            if (token.kind().equals("string") || token.kind().equals("character"))
                spelling = spelling.replace("\\", "\\\\").replace("\"", "\\\"");
            text.append(spelling);
        }
        text.append('"');
        return new Lexer.Token("string", text.toString(), sharp.line(), sharp.space());
    }
    List<Lexer.Token> paste(Lexer.Token left, Lexer.Token right, Lexer.Token token,
                            Main.Inclusion context) {
        if (left.kind().equals("placemarker"))
            return List.of(right.spaced(left.space()));
        if (right.kind().equals("placemarker"))
            return List.of(left);
        String spelling = left.spelling() + right.spelling(), kind = Lexer.singleToken(spelling);
        if (kind != null) {
            Set<String> hide = new HashSet<>(left.hide());
            hide.retainAll(right.hide());
            return List.of(new Lexer.Token(kind, spelling, left.line(), left.space(), hide));
        }
        error(context, token,
              "pasting \"" + left.spelling() + "\" and \"" + right.spelling() +
                  "\" does not give a valid preprocessing token");
        return List.of(left, right.spaced(false));
    }
    sealed interface Item permits Tokens, Paste {}
    record Tokens(List<Lexer.Token> tokens) implements Item {}
    record Paste(Lexer.Token token) implements Item {}
    List<Lexer.Token> substitute(Definitions.Macro macro, Map<String, List<Lexer.Token>> raw,
                                 Lexer.Token token, Set<String> hide, Main.Inclusion context) {
        List<Lexer.Token> replacement = macro.replacement;
        List<Item> items = new ArrayList<>();
        Map<String, List<Lexer.Token>> expanded = new HashMap<>();
        int index = 0;
        while (index < replacement.size()) {
            Lexer.Token current = replacement.get(index);
            if (current.spelling().equals("#") && macro.parameters != null) {
                items.add(new Tokens(
                    List.of(stringize(raw.get(replacement.get(index + 1).spelling()), current))));
                index += 2;
                continue;
            }
            if (current.spelling().equals("##"))
                items.add(new Paste(current));
            else if (current.kind().equals("identifier") && raw.containsKey(current.spelling())) {
                boolean adjacent =
                    index > 0 && replacement.get(index - 1).spelling().equals("##") ||
                    index + 1 < replacement.size() &&
                        replacement.get(index + 1).spelling().equals("##");
                List<Lexer.Token> sequence;
                if (adjacent)
                    sequence = raw.get(current.spelling());
                else {
                    if (!expanded.containsKey(current.spelling()))
                        expanded.put(current.spelling(),
                                     expand(raw.get(current.spelling()), context));
                    sequence = expanded.get(current.spelling());
                }
                if (sequence.isEmpty())
                    items.add(new Tokens(List.of(
                        new Lexer.Token("placemarker", "", current.line(), current.space()))));
                else {
                    List<Lexer.Token> copy = new ArrayList<>(sequence);
                    copy.set(0, copy.getFirst().spaced(current.space()));
                    items.add(new Tokens(copy));
                }
            } else
                items.add(new Tokens(List.of(current)));
            index++;
        }
        List<Lexer.Token> pasted = new ArrayList<>();
        index = 0;
        while (index < items.size()) {
            Item item = items.get(index);
            if (item instanceof Paste) {
                Lexer.Token left = pasted.removeLast();
                Item following = items.get(index + 1);
                List<Lexer.Token> right = following instanceof Paste paste
                                              ? List.of(paste.token())
                                              : ((Tokens)following).tokens();
                pasted.addAll(paste(left, right.getFirst(), token, context));
                pasted.addAll(right.subList(1, right.size()));
                index += 2;
            } else {
                pasted.addAll(((Tokens)item).tokens());
                index++;
            }
        }
        List<Lexer.Token> result = new ArrayList<>();
        boolean carry = false;
        for (Lexer.Token current : pasted)
            if (current.kind().equals("placemarker"))
                carry |= current.space();
            else {
                Set<String> combined = new HashSet<>(current.hide());
                combined.addAll(hide);
                result.add(current.substituted(token.line(), current.space() || carry, combined));
                carry = false;
            }
        if (!result.isEmpty())
            result.set(0, result.getFirst().spaced(token.space()));
        return result;
    }
    List<Lexer.Token> expand(List<Lexer.Token> sequence, Main.Inclusion context) {
        Deque<Lexer.Token> pending = new ArrayDeque<>(sequence);
        List<Lexer.Token> result = new ArrayList<>();
        while (!pending.isEmpty()) {
            Lexer.Token token = pending.removeFirst();
            if (!token.kind().equals("identifier") || token.hide().contains(token.spelling())) {
                result.add(token);
                continue;
            }
            if (Definitions.BUILTINS.contains(token.spelling())) {
                result.add(builtin(token, context));
                continue;
            }
            Definitions.Macro macro = macros.get(token.spelling());
            if (macro == null ||
                macro.parameters != null &&
                    (pending.isEmpty() || !pending.peekFirst().spelling().equals("("))) {
                result.add(token);
                continue;
            }
            Map<String, List<Lexer.Token>> raw = Map.of();
            Set<String> hide = new HashSet<>(token.hide());
            if (macro.parameters != null) {
                Collected collected = collect(pending, macro, token, context);
                if (collected == null) {
                    result.add(token);
                    continue;
                }
                raw = collected.raw();
                for (int i = 0; i < collected.consumed(); i++)
                    pending.removeFirst();
                hide.retainAll(collected.closing().hide());
            }
            hide.add(macro.name);
            List<Lexer.Token> replacement = substitute(macro, raw, token, hide, context);
            macro.expanded++;
            if (replacement.isEmpty() && token.space() && !pending.isEmpty())
                pending.addFirst(pending.removeFirst().spaced(true));
            for (int i = replacement.size() - 1; i >= 0; i--)
                pending.addFirst(replacement.get(i));
        }
        return result;
    }
}
