import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

public class Main {
    record Token(String kind, String text, int line) { }

    record Primitive(String name, String inputs, boolean function) { }

    static class LogoError extends RuntimeException {
        final int line;
        final String reason;
        final List<String> stack;

        LogoError(int line, String reason) {
            this(line, reason, List.of());
        }

        LogoError(int line, String reason, List<String> stack) {
            this.line = line;
            this.reason = reason;
            this.stack = stack;
        }
    }

    static class Flow extends RuntimeException {
        final Long value;

        Flow(Long value) {
            this.value = value;
        }
    }

    static class Expression {
        Token token;
        String kind;
        List<Expression> arguments = new ArrayList<>();

        Expression(Token token, String kind) {
            this.token = token;
            this.kind = kind;
        }
    }

    record PrintItem(String word, Expression expression) { }

    static class Command {
        Token token;
        String name, quoted;
        List<Expression> expressions = new ArrayList<>();
        List<List<Command>> blocks = new ArrayList<>();
        List<PrintItem> prints = new ArrayList<>();

        Command(Token token, String name) {
            this.token = token;
            this.name = name;
        }
    }

    static class Procedure {
        Token token;
        List<String> parameters = new ArrayList<>();
        List<Token> tokens = new ArrayList<>();
        List<Command> commands;

        Procedure(Token token) {
            this.token = token;
        }
    }
    static final Map<String, Primitive> PRIMITIVES = new HashMap<>();

    static {
        register("FD", "E", false, "FORWARD");
        register("BK", "E", false, "BACK");
        register("RT", "E", false, "RIGHT");
        register("LT", "E", false, "LEFT");
        register("SETH", "E", false, "SETHEADING");
        register("PU", "", false, "PENUP");
        register("PD", "", false, "PENDOWN");
        register("PE", "", false, "PENERASE");
        register("SETPEN", "E", false);
        register("SETXY", "EE", false);
        register("SETX", "E", false);
        register("SETY", "E", false);
        register("HOME", "", false);
        register("CS", "", false, "CLEARSCREEN");
        register("CLEAN", "", false);
        register("FILL", "", false);
        register("LABEL", "P", false);
        register("SNAPSHOT", "", false);
        register("REPEAT", "EL", false);
        register("FOR", "QEEL", false);
        register("WHILE", "EL", false);
        register("IF", "EL", false);
        register("IFELSE", "ELL", false);
        register("TEST", "E", false);
        register("IFTRUE", "L", false, "IFT");
        register("IFFALSE", "L", false, "IFF");
        register("STOP", "", false);
        register("OUTPUT", "E", false, "OP");
        register("MAKE", "QE", false);
        register("LOCAL", "Q", false);
        register("LOCALMAKE", "QE", false);
        register("TRACE", "Q", false);
        register("UNTRACE", "Q", false);
        register("SEED", "E", false);
        register("PRINT", "P", false, "PR");
        register("XCOR", "", true);
        register("YCOR", "", true);
        register("HEADING", "", true);
        register("REPCOUNT", "", true);
        register("RANDOM", "E", true);
        register("ABS", "E", true);
        register("NOT", "E", true);
        register("AND", "EE", true);
        register("OR", "EE", true);
        register("MAX", "EE", true);
        register("MIN", "EE", true);
        register("TO", "", false);
        register("END", "", false);
        register("MOD", "", false);
    }

    static void register(String name, String inputs, boolean function, String... aliases) {
        Primitive primitive = new Primitive(name, inputs, function);
        PRIMITIVES.put(name, primitive);
        for (String alias : aliases) PRIMITIVES.put(alias, primitive);
    }

    static boolean name(String value) {
        if (value.isEmpty() || value.charAt(0) < 'A' || value.charAt(0) > 'Z') return false;
        for (int i = 1; i < value.length(); i++) {
            char c = value.charAt(i);
            if (!(c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_')) return false;
        }
        return true;
    }

    static List<Token> lex(String source, int line) {
        int comment = source.indexOf(';');
        if (comment >= 0) source = source.substring(0, comment);
        StringBuilder upper = new StringBuilder();
        for (char c : source.toCharArray()) upper.append(c >= 'a' && c <= 'z' ? (char)(c - 'a' + 'A') : c);
        String text = upper.toString();
        List<Token> tokens = new ArrayList<>();
        for (int i = 0; i < text.length();) {
            char c = text.charAt(i);
            if (c == ' ') {
                i++;
                continue;
            }
            if ("[]()+*/=".indexOf(c) >= 0) {
                tokens.add(new Token("symbol", Character.toString(c), line));
                i++;
            } else if (c == '<' || c == '>') {
                int length = i + 1 < text.length() && (text.charAt(i + 1) == '=' || c == '<' && text.charAt(i + 1) == '>') ? 2 : 1;
                tokens.add(new Token("symbol", text.substring(i, i + length), line));
                i += length;
            } else if (c == '-') {
                boolean sign = (i == 0 || " [(".indexOf(text.charAt(i - 1)) >= 0) && i + 1 < text.length() && text.charAt(i + 1) != ' ';
                tokens.add(new Token(sign ? "sign" : "minus", "-", line));
                i++;
            } else {
                int start = i;
                while (i < text.length() && " []()+-*/=<>".indexOf(text.charAt(i)) < 0) i++;
                String word = text.substring(start, i);
                String kind;
                if (word.chars().allMatch(x -> x >= '0' && x <= '9')) kind = "number";
                else if (word.startsWith(":") && name(word.substring(1))) kind = "variable";
                else if (word.startsWith("\"") && name(word.substring(1))) kind = "quoted";
                else if (name(word)) kind = "word";
                else throw new LogoError(line, "bad token '" + word + "'");
                tokens.add(new Token(kind, word, line));
            }
        }
        return tokens;
    }

    static class Parser {
        final List<Token> tokens;
        final Map<String, Procedure> procedures;
        final boolean inside;
        int position;

        Parser(List<Token> tokens, Map<String, Procedure> procedures, boolean inside) {
            this.tokens = tokens;
            this.procedures = procedures;
            this.inside = inside;
        }

        Token peek() {
            return position < tokens.size() ? tokens.get(position) : null;
        }

        boolean is(String text) {
            return peek() != null && peek().text.equals(text);
        }

        boolean unknown(Token token) {
            return token.kind.equals("word") && !PRIMITIVES.containsKey(token.text) && !procedures.containsKey(token.text);
        }

        Token input(Token owner) {
            Token next = peek();
            if (next == null || next.text.equals("]") || next.text.equals(")")) throw new LogoError(owner.line, "not enough inputs to " + owner.text);
            if (unknown(next)) throw new LogoError(next.line, "I don't know how to " + next.text);
            return next;
        }

        void reject(Token owner, Token next) {
            throw new LogoError(next.line, owner.text + " doesn't like " + next.text + " as input");
        }

        List<Command> sequence() {
            List<Command> result = new ArrayList<>();
            while (peek() != null) {
                if (is("]")) throw new LogoError(peek().line, "unexpected ]");
                result.add(command());
            }
            return result;
        }

        List<Command> block(Token owner) {
            Token opener = input(owner);
            if (!opener.text.equals("[")) reject(owner, opener);
            position++;
            List<Command> result = new ArrayList<>();
            while (peek() != null && !is("]")) result.add(command());
            if (peek() == null) throw new LogoError(opener.line, "missing ]");
            position++;
            return result;
        }

        String quoted(Token owner) {
            Token next = input(owner);
            if (!next.kind.equals("quoted")) reject(owner, next);
            position++;
            return next.text.substring(1);
        }

        PrintItem printItem(Token owner) {
            Token next = input(owner);
            if (next.kind.equals("quoted")) {
                position++;
                return new PrintItem(next.text.substring(1), null);
            }
            return new PrintItem(null, expression(owner));
        }

        Command command() {
            Token token = tokens.get(position++);
            if (token.text.equals("(") && peek() != null && peek().kind.equals("word") && (is("PRINT") || is("PR"))) {
                Token print = tokens.get(position++);
                Command command = new Command(print, "MULTIPRINT");
                while (!is(")")) {
                    if (peek() == null || is("]")) throw new LogoError(token.line, "missing )");
                    command.prints.add(printItem(print));
                }
                position++;
                return command;
            }
            if (token.kind.equals("word") && (token.text.equals("TO") || token.text.equals("END"))) throw new LogoError(token.line, "misplaced " + token.text);
            Primitive primitive = token.kind.equals("word") ? PRIMITIVES.get(token.text) : null;
            if (primitive != null && !primitive.function && !primitive.name.equals("MOD")) {
                if (!inside && Set.of("STOP", "OUTPUT", "LOCAL", "LOCALMAKE").contains(primitive.name)) throw new LogoError(token.line, "can only use " + token.text + " inside a procedure");
                Command command = new Command(token, primitive.name);
                for (char kind : primitive.inputs.toCharArray()) switch (kind) {
                    case 'E' -> command.expressions.add(expression(token));
                    case 'L' -> command.blocks.add(block(token));
                    case 'Q' -> command.quoted = quoted(token);
                    case 'P' -> command.prints.add(printItem(token));
                    default -> throw new IllegalStateException();
                }
                if ((primitive.name.equals("TRACE") || primitive.name.equals("UNTRACE")) && !procedures.containsKey(command.quoted)) {
                    Token word = tokens.get(position - 1);
                    throw new LogoError(word.line, "I don't know how to " + command.quoted);
                }
                return command;
            }
            if (token.kind.equals("word") && procedures.containsKey(token.text)) {
                Command command = new Command(token, "CALL");
                for (int i = 0; i < procedures.get(token.text).parameters.size(); i++) command.expressions.add(expression(token));
                return command;
            }
            if (unknown(token)) throw new LogoError(token.line, "I don't know how to " + token.text);
            throw new LogoError(token.line, "you don't say what to do with " + token.text);
        }

        Expression expression(Token owner) {
            return comparison(owner);
        }

        Expression binary(Expression left, Token operator, Expression right) {
            Expression result = new Expression(operator, "binary");
            result.arguments.add(left);
            result.arguments.add(right);
            return result;
        }

        Expression comparison(Token owner) {
            Expression result = sum(owner);
            while (peek() != null && List.of("=", "<>", "<", ">", "<=", ">=").contains(peek().text)) {
                Token operator = tokens.get(position++);
                result = binary(result, operator, sum(operator));
            }
            return result;
        }

        Expression sum(Token owner) {
            Expression result = product(owner);
            while (peek() != null && (is("+") || is("-") && peek().kind.equals("minus"))) {
                Token operator = tokens.get(position++);
                result = binary(result, operator, product(operator));
            }
            return result;
        }

        Expression product(Token owner) {
            Expression result = term(owner);
            while (peek() != null && (is("*") || is("/") || is("MOD"))) {
                Token operator = tokens.get(position++);
                result = binary(result, operator, term(operator));
            }
            return result;
        }

        Expression term(Token owner) {
            Token token = input(owner);
            position++;
            if (token.kind.equals("number") || token.kind.equals("variable")) return new Expression(token, token.kind);
            if (token.text.equals("-")) {
                Expression result = new Expression(token, "negate");
                result.arguments.add(term(token));
                return result;
            }
            if (token.text.equals("(")) {
                Expression result = expression(token);
                if (!is(")")) throw new LogoError(token.line, "missing )");
                position++;
                return result;
            }
            if (token.kind.equals("word")) {
                Primitive primitive = PRIMITIVES.get(token.text);
                if (primitive != null && primitive.function || procedures.containsKey(token.text)) {
                    Expression result = new Expression(token, primitive != null ? "function" : "call");
                    int count = primitive != null ? primitive.inputs.length() : procedures.get(token.text).parameters.size();
                    for (int i = 0; i < count; i++) result.arguments.add(expression(token));
                    return result;
                }
            }
            reject(owner, token);
            return null;
        }
    }

    record Point(int x, int y) { }

    static class Environment {
        Procedure procedure;
        Map<String, Long> variables = new HashMap<>();
        Boolean test;

        Environment(Procedure procedure) {
            this.procedure = procedure;
        }
    }

    static class Runner {
        final Map<String, Procedure> procedures;
        final Map<Point, Character> canvas = new HashMap<>();
        final List<Environment> environments = new ArrayList<>();
        final List<Long> repetitions = new ArrayList<>();
        final Set<String> traced = new HashSet<>();
        int x, y, heading;
        String pen = "DOWN";
        char penCharacter = '*';
        long random = 1;
        static final int[] DX = {0, 1, 1, 1, 0, -1, -1, -1}, DY = {1, 1, 0, -1, -1, -1, 0, 1};

        Runner(Map<String, Procedure> procedures) {
            this.procedures = procedures;
            environments.add(new Environment(null));
        }

        void error(Token token, String reason) {
            List<String> stack = new ArrayList<>();
            for (int i = environments.size() - 1; i > 0; i--) stack.add(environments.get(i).procedure.token.text);
            throw new LogoError(token.line, reason, stack);
        }

        long variable(Token token) {
            String name = token.text.substring(1);
            for (int i = environments.size() - 1; i >= 0; i--) if (environments.get(i).variables.containsKey(name)) return environments.get(i).variables.get(name);
            error(token, name + " has no value");
            return 0;
        }

        void make(String name, long value) {
            for (int i = environments.size() - 1; i > 0; i--) if (environments.get(i).variables.containsKey(name)) {
                environments.get(i).variables.put(name, value);
                return;
            }
            environments.get(0).variables.put(name, value);
        }

        long evaluate(Expression expression) {
            Token token = expression.token;
            switch (expression.kind) {
                case "number":
                    return Long.parseLong(token.text);
                case "variable":
                    return variable(token);
                case "negate":
                    return -evaluate(expression.arguments.get(0));
                case "binary":
                    {
                        long a = evaluate(expression.arguments.get(0)), b = evaluate(expression.arguments.get(1));
                        if ((token.text.equals("/") || token.text.equals("MOD")) && b == 0) error(token, token.text + " doesn't like 0 as input");
                        return switch (token.text) {
                            case "+" -> a + b;
                            case "-" -> a - b;
                            case "*" -> a * b;
                            case "/" -> a / b;
                            case "MOD" -> a % b;
                            case "=" -> a == b ? 1 : 0;
                            case "<>" -> a != b ? 1 : 0;
                            case "<" -> a < b ? 1 : 0;
                            case ">" -> a > b ? 1 : 0;
                            case "<=" -> a <= b ? 1 : 0;
                            case ">=" -> a >= b ? 1 : 0;
                            default -> throw new IllegalStateException();
                        };
                    }
                default:
                    {
                        List<Long> values = new ArrayList<>();
                        for (Expression argument : expression.arguments) values.add(evaluate(argument));
                        if (expression.kind.equals("call")) {
                            Long value = call(token, values);
                            if (value == null) error(token, token.text + " did not output");
                            return value;
                        }
                        long a = values.isEmpty() ? 0 : values.get(0), b = values.size() < 2 ? 0 : values.get(1);
                        return switch (token.text) {
                            case "XCOR" -> x;
                            case "YCOR" -> y;
                            case "HEADING" -> heading;
                            case "REPCOUNT" -> {
                                if (repetitions.isEmpty()) error(token, "REPCOUNT outside REPEAT");
                                yield repetitions.getLast();
                            }
                            case "RANDOM" -> {
                                if (a < 1) error(token, "RANDOM doesn't like " + a + " as input");
                                random = random * 48271 % 2147483647;
                                yield random % a;
                            }
                            case "ABS" -> Math.abs(a);
                            case "NOT" -> a == 0 ? 1 : 0;
                            case "AND" -> a != 0 && b != 0 ? 1 : 0;
                            case "OR" -> a != 0 || b != 0 ? 1 : 0;
                            case "MAX" -> Math.max(a, b);
                            case "MIN" -> Math.min(a, b);
                            default -> throw new IllegalStateException();
                        };
                    }
            }
        }

        Long call(Token token, List<Long> values) {
            int depth = environments.size() - 1;
            if (depth == 100) error(token, "recursion too deep");
            Procedure procedure = procedures.get(token.text);
            boolean trace = traced.contains(token.text);
            String indent = "  ".repeat(depth);
            if (trace) {
                List<String> parts = new ArrayList<>();
                parts.add(token.text);
                for (long value : values) parts.add(Long.toString(value));
                System.out.println(indent + "( " + String.join(" ", parts) + " )");
            }
            Environment environment = new Environment(procedure);
            for (int i = 0; i < values.size(); i++) environment.variables.put(procedure.parameters.get(i), values.get(i));
            environments.add(environment);
            Long result = null;
            try {
                execute(procedure.commands);
            } catch (Flow flow) {
                result = flow.value;
            }
            environments.removeLast();
            if (trace) System.out.println(indent + token.text + (result == null ? " stops" : " outputs " + result));
            return result;
        }

        void apply(int x, int y) {
            Point point = new Point(x, y);
            if (pen.equals("DOWN")) canvas.put(point, penCharacter);
            else if (pen.equals("ERASE")) canvas.remove(point);
        }

        void forward(long n) {
            int dx = DX[heading / 45], dy = DY[heading / 45];
            if (n < 0) {
                dx = -dx;
                dy = -dy;
                n = -n;
            }
            apply(x, y);
            for (long i = 0; i < n; i++) {
                x += dx;
                y += dy;
                apply(x, y);
            }
        }

        void move(int targetX, int targetY) {
            int oldX = x, oldY = y, dx = targetX - x, dy = targetY - y, steps = Math.max(Math.abs(dx), Math.abs(dy));
            if (steps == 0) apply(x, y);
            else for (int i = 0; i <= steps; i++) apply(oldX + (int)Math.floorDiv(2L * i * dx + steps, 2L * steps), oldY + (int)Math.floorDiv(2L * i * dy + steps, 2L * steps));
            x = targetX;
            y = targetY;
        }

        void fill() {
            if (canvas.isEmpty() || canvas.containsKey(new Point(x, y))) return;
            int x1 = canvas.keySet().stream().mapToInt(Point::x).min().orElseThrow(), x2 = canvas.keySet().stream().mapToInt(Point::x).max().orElseThrow(), y1 = canvas.keySet().stream().mapToInt(Point::y).min().orElseThrow(), y2 = canvas.keySet().stream().mapToInt(Point::y).max().orElseThrow();
            if (x < x1 || x > x2 || y < y1 || y > y2) return;
            int[] dx = {-1, 1, 0, 0}, dy = {0, 0, -1, 1};
            ArrayDeque<Point> queue = new ArrayDeque<>();
            Point first = new Point(x, y);
            canvas.put(first, penCharacter);
            queue.add(first);
            while (!queue.isEmpty()) {
                Point point = queue.remove();
                for (int d = 0; d < 4; d++) {
                    Point next = new Point(point.x + dx[d], point.y + dy[d]);
                    if (next.x >= x1 && next.x <= x2 && next.y >= y1 && next.y <= y2 && !canvas.containsKey(next)) {
                        canvas.put(next, penCharacter);
                        queue.add(next);
                    }
                }
            }
        }

        String item(PrintItem item) {
            return item.word != null ? item.word : Long.toString(evaluate(item.expression));
        }

        void picture() {
            if (canvas.isEmpty()) {
                System.out.println("CANVAS 0 0 0");
                return;
            }
            int x1 = canvas.keySet().stream().mapToInt(Point::x).min().orElseThrow(), x2 = canvas.keySet().stream().mapToInt(Point::x).max().orElseThrow(), y1 = canvas.keySet().stream().mapToInt(Point::y).min().orElseThrow(), y2 = canvas.keySet().stream().mapToInt(Point::y).max().orElseThrow();
            System.out.println("CANVAS " + (x2 - x1 + 1) + " " + (y2 - y1 + 1) + " " + canvas.size());
            for (int yy = y2; yy >= y1; yy--) {
                StringBuilder row = new StringBuilder();
                for (int xx = x1; xx <= x2; xx++) row.append(canvas.getOrDefault(new Point(xx, yy), ' '));
                int end = row.length();
                while (end > 0 && row.charAt(end - 1) == ' ') end--;
                System.out.println(row.substring(0, end));
            }
        }

        void execute(List<Command> commands) {
            for (Command command : commands) execute(command);
        }

        void execute(Command command) {
            Token token = command.token;
            String name = command.name;
            if (name.equals("WHILE")) { while (evaluate(command.expressions.get(0)) != 0) execute(command.blocks.get(0));
                return;
            }
            List<Long> values = new ArrayList<>();
            for (Expression expression : command.expressions) values.add(evaluate(expression));
            long a = values.isEmpty() ? 0 : values.get(0), b = values.size() < 2 ? 0 : values.get(1);
            Environment current = environments.getLast();
            switch (name) {
                case "FD" -> forward(a);
                case "BK" -> forward(-a);
                case "RT", "LT", "SETH" -> {
                    if (a % 45 != 0) error(token, token.text + " doesn't like " + a + " as input");
                    long angle = name.equals("SETH") ? a : name.equals("RT") ? heading + a : heading - a;
                    heading = (int)((angle % 360 + 360) % 360);
                }
                case "PU" -> pen = "UP";
                case "PD" -> pen = "DOWN";
                case "PE" -> pen = "ERASE";
                case "SETPEN" -> {
                    if (a < 33 || a > 126) error(token, "SETPEN doesn't like " + a + " as input");
                    penCharacter = (char)a;
                }
                case "SETXY" -> move((int)a, (int)b);
                case "SETX" -> move((int)a, y);
                case "SETY" -> move(x, (int)a);
                case "HOME" -> {
                    move(0, 0);
                    heading = 0;
                }
                case "CS" -> {
                    canvas.clear();
                    x = y = heading = 0;
                }
                case "CLEAN" -> canvas.clear();
                case "FILL" -> fill();
                case "LABEL" -> {
                    String text = item(command.prints.get(0));
                    int dx = DX[heading / 45], dy = DY[heading / 45];
                    for (int i = 0; i < text.length(); i++) canvas.put(new Point(x + i * dx, y + i * dy), text.charAt(i));
                }
                case "SNAPSHOT" -> picture();
                case "REPEAT" -> {
                    if (!command.blocks.get(0).isEmpty()) for (long i = 1; i <= a; i++) {
                        repetitions.add(i);
                        try {
                            execute(command.blocks.get(0));
                        } finally {
                            repetitions.removeLast();
                        }
                    }
                }
                case "FOR" -> {
                    List<Command> body = command.blocks.get(0);
                    if (body.isEmpty()) make(command.quoted, b);
                    else for (long i = a;; i += a <= b ? 1 : -1) {
                        make(command.quoted, i);
                        execute(body);
                        if (i == b) break;
                    }
                }
                case "IF" -> {
                    if (a != 0) execute(command.blocks.get(0));
                }
                case "IFELSE" -> execute(command.blocks.get(a != 0 ? 0 : 1));
                case "TEST" -> current.test = a != 0;
                case "IFTRUE", "IFFALSE" -> {
                    if (current.test == null) error(token, token.text + " without TEST");
                    if (current.test == name.equals("IFTRUE")) execute(command.blocks.get(0));
                }
                case "STOP" -> throw new Flow(null);
                case "OUTPUT" -> throw new Flow(a);
                case "MAKE" -> make(command.quoted, a);
                case "LOCAL" -> current.variables.put(command.quoted, 0L);
                case "LOCALMAKE" -> current.variables.put(command.quoted, a);
                case "TRACE" -> traced.add(command.quoted);
                case "UNTRACE" -> traced.remove(command.quoted);
                case "SEED" -> {
                    if (a < 1) error(token, "SEED doesn't like " + a + " as input");
                    random = a;
                }
                case "PRINT", "MULTIPRINT" -> {
                    List<String> items = new ArrayList<>();
                    for (PrintItem item : command.prints) items.add(item(item));
                    System.out.println(String.join(" ", items));
                }
                case "CALL" -> {
                    Long result = call(token, values);
                    if (result != null) error(token, "you don't say what to do with " + result);
                }
                default -> throw new IllegalStateException();
            }
        }
    }

    static void run(String name, List<String> source, int firstLine) {
        System.out.println("PROGRAM " + name);
        try {
            LinkedHashMap<String, Procedure> procedures = new LinkedHashMap<>();
            List<Token> top = new ArrayList<>();
            Procedure current = null;
            for (int i = 0; i < source.size(); i++) {
                int line = firstLine + i;
                List<Token> tokens = lex(source.get(i), line);
                if (tokens.isEmpty()) continue;
                Token first = tokens.get(0);
                if (first.kind.equals("word") && first.text.equals("TO")) {
                    if (current != null) throw new LogoError(line, "TO inside definition of " + current.token.text);
                    if (tokens.size() < 2 || !tokens.get(1).kind.equals("word")) throw new LogoError(line, "bad procedure header");
                    Token procedureName = tokens.get(1);
                    if (PRIMITIVES.containsKey(procedureName.text)) throw new LogoError(line, procedureName.text + " is a primitive");
                    if (procedures.containsKey(procedureName.text)) throw new LogoError(line, procedureName.text + " is already defined");
                    Procedure procedure = new Procedure(procedureName);
                    Set<String> seen = new HashSet<>();
                    for (int j = 2; j < tokens.size(); j++) {
                        Token input = tokens.get(j);
                        if (!input.kind.equals("variable")) throw new LogoError(line, "bad procedure header");
                        if (!seen.add(input.text.substring(1))) throw new LogoError(line, "duplicate input " + input.text);
                        procedure.parameters.add(input.text.substring(1));
                    }
                    procedures.put(procedureName.text, procedure);
                    current = procedure;
                } else if (tokens.size() == 1 && first.kind.equals("word") && first.text.equals("END")) {
                    if (current == null) throw new LogoError(line, "END without TO");
                    current = null;
                } else if (current != null) current.tokens.addAll(tokens);
                else top.addAll(tokens);
            }
            if (current != null) throw new LogoError(current.token.line, "missing END for " + current.token.text);
            for (Procedure procedure : procedures.values()) procedure.commands = new Parser(procedure.tokens, procedures, true).sequence();
            List<Command> commands = new Parser(top, procedures, false).sequence();
            Runner runner = new Runner(procedures);
            runner.execute(commands);
            System.out.println("TURTLE " + runner.x + " " + runner.y + " " + runner.heading + " " + runner.pen + " " + runner.penCharacter);
            runner.picture();
        } catch (LogoError error) {
            System.out.println("ERROR line " + error.line + ": " + error.reason);
            for (int i = 0; i < error.stack.size();) {
                String procedure = error.stack.get(i);
                int end = i + 1;
                while (end < error.stack.size() && error.stack.get(end).equals(procedure)) end++;
                System.out.println("  in " + procedure + (end - i == 1 ? "" : " x" + (end - i)));
                i = end;
            }
        }
    }
    public static void main(String[] args) throws Exception {
        BufferedReader reader = new BufferedReader(new InputStreamReader(System.in));
        List<String> lines = new ArrayList<>();
        String line;
        while ((line = reader.readLine()) != null) lines.add(line);
        for (int i = 0; i < lines.size() && !lines.get(i).equals("#EOF");) {
            String name = lines.get(i).substring(9);
            int first = ++i;
            List<String> source = new ArrayList<>();
            while (!lines.get(i).equals("#EOF") && !lines.get(i).startsWith("#PROGRAM ")) source.add(lines.get(i++));
            run(name, source, first + 1);
        }
    }
}
