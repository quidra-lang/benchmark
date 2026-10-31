import java.util.*;
final class Definitions {
    static final Set<String> BUILTINS = Set.of("__LINE__", "__FILE__", "__COUNTER__");
    static final String VARIADIC = "__VA_ARGS__",
                        VARIADIC_ERROR =
                            "\"__VA_ARGS__\" can only appear in the expansion of a variadic macro";
    record Position(String file, int line) {
        public String toString() { return file + ":" + line; }
    }
    static final class DefinitionError extends RuntimeException {
        DefinitionError(String message) { super(message); }
    }
    static final class Macro {
        String name;
        List<String> parameters;
        boolean variadic, mainFile;
        List<Lexer.Token> replacement;
        Position position;
        int expanded, tested;
        Macro(String name, List<String> parameters, boolean variadic, List<Lexer.Token> replacement,
              Position position, boolean mainFile) {
            this.name = name;
            this.parameters = parameters == null ? null : List.copyOf(parameters);
            this.variadic = variadic;
            this.replacement = List.copyOf(replacement);
            this.position = position;
            this.mainFile = mainFile;
        }
        String signature() {
            if (parameters == null)
                return name;
            List<String> names = new ArrayList<>(parameters);
            if (variadic)
                names.set(names.size() - 1, "...");
            return name + "(" + String.join(", ", names) + ")";
        }
        boolean identical(Macro other) {
            if (!Objects.equals(parameters, other.parameters) || variadic != other.variadic ||
                replacement.size() != other.replacement.size())
                return false;
            for (int i = 0; i < replacement.size(); i++) {
                Lexer.Token a = replacement.get(i), b = other.replacement.get(i);
                if (!a.spelling().equals(b.spelling()) || a.space() != b.space())
                    return false;
            }
            return true;
        }
    }
    static String checkName(List<Lexer.Token> tokens, String directive) {
        if (tokens.isEmpty())
            return "no macro name given in #" + directive + " directive";
        if (!tokens.getFirst().kind().equals("identifier"))
            return "macro names must be identifiers";
        String name = tokens.getFirst().spelling();
        if (name.equals("defined"))
            return "\"defined\" cannot be used as a macro name";
        if (BUILTINS.contains(name))
            return "cannot " + (directive.equals("define") ? "redefine" : "undefine") +
                " builtin macro \"" + name + "\"";
        return null;
    }
    static Macro parse(List<Lexer.Token> tokens, Position position, boolean mainFile) {
        String error = checkName(tokens, "define");
        if (error != null)
            throw new DefinitionError(error);
        String name = tokens.getFirst().spelling();
        if (name.equals(VARIADIC))
            throw new DefinitionError(VARIADIC_ERROR);
        List<String> parameters = null;
        boolean variadic = false;
        int index = 1;
        if (tokens.size() > 1 && tokens.get(1).spelling().equals("(") && !tokens.get(1).space()) {
            parameters = new ArrayList<>();
            index = 2;
            if (index == tokens.size())
                throw new DefinitionError("missing ')' in macro parameter list");
            if (tokens.get(index).spelling().equals(")"))
                index++;
            else
                while (true) {
                    if (index == tokens.size())
                        throw new DefinitionError("missing ')' in macro parameter list");
                    Lexer.Token token = tokens.get(index);
                    if (token.spelling().equals("...")) {
                        parameters.add(VARIADIC);
                        variadic = true;
                    } else if (token.kind().equals("identifier")) {
                        if (token.spelling().equals(VARIADIC))
                            throw new DefinitionError(VARIADIC_ERROR);
                        if (parameters.contains(token.spelling()))
                            throw new DefinitionError("duplicate macro parameter \"" +
                                                      token.spelling() + "\"");
                        parameters.add(token.spelling());
                    } else
                        throw new DefinitionError("expected parameter name, found \"" +
                                                  token.spelling() + "\"");
                    index++;
                    if (index == tokens.size())
                        throw new DefinitionError("missing ')' in macro parameter list");
                    String following = tokens.get(index++).spelling();
                    if (following.equals(")"))
                        break;
                    if (variadic)
                        throw new DefinitionError("expected ')' after \"...\", found \"" +
                                                  following + "\"");
                    if (!following.equals(","))
                        throw new DefinitionError("expected ',' or ')', found \"" + following +
                                                  "\"");
                }
        }
        List<Lexer.Token> replacement = new ArrayList<>(tokens.subList(index, tokens.size()));
        if (!replacement.isEmpty()) {
            replacement.set(0, replacement.getFirst().spaced(false));
            if (replacement.getFirst().spelling().equals("##") ||
                replacement.getLast().spelling().equals("##"))
                throw new DefinitionError("'##' cannot appear at either end of a macro expansion");
        }
        for (int i = 0; i < replacement.size(); i++) {
            Lexer.Token token = replacement.get(i);
            if (token.kind().equals("identifier") && token.spelling().equals(VARIADIC) && !variadic)
                throw new DefinitionError(VARIADIC_ERROR);
            if (token.spelling().equals("#") && parameters != null &&
                (i + 1 == replacement.size() ||
                 !replacement.get(i + 1).kind().equals("identifier") ||
                 !parameters.contains(replacement.get(i + 1).spelling())))
                throw new DefinitionError("'#' is not followed by a macro parameter");
        }
        return new Macro(name, parameters, variadic, replacement, position, mainFile);
    }
}
