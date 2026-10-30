import java.util.*;
final class Lexer {
    record Token(String kind, String value, int column) {}
    record Symbol(String display, String type) {}
    static final Set<String> GREEK = Set.of(
        "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi pi rho sigma tau upsilon phi chi psi omega Gamma Delta Theta Lambda Xi Pi Sigma Upsilon Phi Psi Omega"
            .split(" "));
    static final Set<String> FUNCTIONS =
                                 Set.of("sin cos tan log ln exp det lim max min".split(" ")),
                             LARGE = Set.of("sum", "prod", "int"),
                             ACCENTS = Set.of("overline", "hat", "vec", "dot", "tilde", "overbrace",
                                              "underbrace"),
                             CONSTRUCTS = Set.of("frac", "binom", "overset", "underset", "sqrt",
                                                 "left", "right"),
                             RAW = Set.of("text", "begin", "end", "tag", "label", "eqref"),
                             ENVIRONMENTS =
                                 Set.of("matrix", "pmatrix", "bmatrix", "vmatrix", "cases");
    static final Map<String, Symbol> SYMBOL_COMMANDS = symbols();
    static final Set<String> COMMAND_NAMES = commandNames();
    static Map<String, Symbol> symbols() {
        Map<String, Symbol> result = new HashMap<>();
        for (String name : GREEK)
            result.put("\\" + name, new Symbol(name, "ordinary"));
        for (Set<String> names : List.of(FUNCTIONS, LARGE))
            for (String name : names)
                result.put("\\" + name, new Symbol(name, "operator"));
        String[][] entries = {
            {"cdot", "*", "binary"},     {"times", "x", "binary"},     {"pm", "+-", "binary"},
            {"mp", "-+", "binary"},      {"leq", "<=", "relation"},    {"geq", ">=", "relation"},
            {"neq", "!=", "relation"},   {"approx", "~=", "relation"}, {"to", "->", "relation"},
            {"infty", "oo", "ordinary"}, {"ldots", "...", "ordinary"}, {"cdots", "...", "ordinary"},
            {"quad", "  ", "ordinary"},  {",", " ", "ordinary"},       {"{", "{", "open"},
            {"}", "}", "close"}};
        for (String[] entry : entries)
            result.put("\\" + entry[0], new Symbol(entry[1], entry[2]));
        return Map.copyOf(result);
    }
    static Set<String> commandNames() {
        Set<String> result = new HashSet<>();
        for (String value : SYMBOL_COMMANDS.keySet())
            if (letter(value.charAt(1)))
                result.add(value.substring(1));
        return Set.copyOf(result);
    }
    static final class FormulaError extends RuntimeException {
        int column;
        FormulaError(int column, String message) {
            super(message);
            this.column = column;
        }
    }
    static boolean letter(char c) { return c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z'; }
    static boolean digit(char c) { return c >= '0' && c <= '9'; }
    static List<Token> tokenize(String line) {
        List<Token> tokens = new ArrayList<>();
        int position = 0, length = line.length();
        while (position < length) {
            char c = line.charAt(position);
            int column = position + 1;
            if (c == ' ') {
                position++;
                continue;
            }
            if (letter(c) || digit(c)) {
                int end = position + 1;
                if (letter(c))
                    while (end < length && letter(line.charAt(end)))
                        end++;
                else {
                    while (end < length && digit(line.charAt(end)))
                        end++;
                    if (end + 1 < length && line.charAt(end) == '.' &&
                        digit(line.charAt(end + 1))) {
                        end += 2;
                        while (end < length && digit(line.charAt(end)))
                            end++;
                    }
                }
                tokens.add(new Token(letter(c) ? "identifier" : "number",
                                     line.substring(position, end), column));
                position = end;
                continue;
            }
            if ("+-*/=<>:()[],;.!|'{}^_&".indexOf(c) >= 0) {
                tokens.add(new Token("{}^_&".indexOf(c) >= 0 ? String.valueOf(c) : "symbol",
                                     String.valueOf(c), column));
                position++;
                continue;
            }
            if (c != '\\')
                throw new FormulaError(column, "invalid character " + c);
            position++;
            if (position < length && "\\{},".indexOf(line.charAt(position)) >= 0) {
                char escaped = line.charAt(position++);
                tokens.add(
                    new Token(escaped == '\\' ? "newline" : "command", "\\" + escaped, column));
                continue;
            }
            int start = position;
            while (position < length && letter(line.charAt(position)))
                position++;
            String name = line.substring(start, position);
            if (name.isEmpty())
                throw new FormulaError(column, "invalid command");
            if (RAW.contains(name)) {
                while (position < length && line.charAt(position) == ' ')
                    position++;
                if (position == length || line.charAt(position) != '{')
                    throw new FormulaError(position + 1, "expected {");
                int end = line.indexOf('}', position + 1);
                if (end < 0)
                    throw new FormulaError(column, "unterminated argument");
                String argument = line.substring(position + 1, end);
                if ((name.equals("begin") || name.equals("end")) &&
                    !ENVIRONMENTS.contains(argument))
                    throw new FormulaError(column, "unknown environment \"" + argument + "\"");
                tokens.add(new Token(name, argument, column));
                position = end + 1;
            } else if (SYMBOL_COMMANDS.containsKey("\\" + name))
                tokens.add(new Token("command", "\\" + name, column));
            else if (ACCENTS.contains(name))
                tokens.add(new Token("accent", name, column));
            else if (CONSTRUCTS.contains(name))
                tokens.add(new Token(name, name, column));
            else
                throw new FormulaError(column, "unknown command \\" + name);
        }
        tokens.add(new Token("eof", "", length + 1));
        return tokens;
    }
}
