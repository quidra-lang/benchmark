import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.TreeMap;

public class Main {
    static final class CommandError extends RuntimeException {
        CommandError(String reason) { super(reason); }
    }

    static void require(boolean condition, String reason) {
        if (!condition) throw new CommandError(reason);
    }

    static boolean digit(char c) { return c >= '0' && c <= '9'; }
    static boolean lower(char c) { return c >= 'a' && c <= 'z'; }
    static boolean upper(char c) { return c >= 'A' && c <= 'Z'; }
    static boolean digits(String s) { return !s.isEmpty() && s.chars().allMatch(c -> digit((char)c)); }
    static boolean oneOf(char c, String set) { return set.indexOf(c) >= 0; }

    record Atom(char character, boolean matched) {}
    record Delimited(String text, List<Atom> atoms, int end) {}

    static Delimited delimited(String s, int position, char delimiter) {
        StringBuilder text = new StringBuilder();
        List<Atom> atoms = new ArrayList<>();
        while (position < s.length()) {
            char character = s.charAt(position++);
            if (character == delimiter) return new Delimited(text.toString(), List.copyOf(atoms), position);
            boolean escaped = character == '\\';
            if (escaped) {
                require(position < s.length(), "missing delimiter");
                character = s.charAt(position++);
            }
            text.append(character);
            atoms.add(new Atom(character, character == '&' && !escaped));
        }
        throw new CommandError("missing delimiter");
    }

    record Token(char kind, int number, char name, String search) {
        Token(char kind) { this(kind, 0, '\0', ""); }
        Token(char kind, int number) { this(kind, number, '\0', ""); }
    }
    record Lexed(List<Token> tokens, int end) {}

    static Lexed lexAddresses(String s) {
        List<Token> tokens = new ArrayList<>();
        int position = 0;
        while (position < s.length()) {
            char c = s.charAt(position);
            Token token;
            if (digit(c)) {
                int start = position;
                while (position < s.length() && digit(s.charAt(position))) position++;
                token = new Token('N', Integer.parseInt(s.substring(start, position)));
            } else if (c == '+' || c == '-') {
                int start = ++position;
                while (position < s.length() && digit(s.charAt(position))) position++;
                int value = position == start ? 1 : Integer.parseInt(s.substring(start, position));
                token = new Token('O', c == '-' ? -value : value);
            } else if (oneOf(c, ".$,;%")) {
                position++;
                token = new Token(c);
            } else if (c == '\'') {
                position++;
                char name = position < s.length() ? s.charAt(position++) : '\0';
                token = new Token(c, 0, name, "");
            } else if (c == '/' || c == '?') {
                Delimited search = delimited(s, position + 1, c);
                position = search.end;
                token = new Token(c, 0, '\0', search.text);
            } else break;
            tokens.add(token);
        }
        return new Lexed(tokens, position);
    }

    static boolean withText(String line) {
        try {
            String part = line.substring(lexAddresses(line).end);
            if (part.equals("a") || part.equals("i") || part.equals("c")) return true;
            if (part.length() >= 2 && oneOf(part.charAt(0), "gv") && !oneOf(part.charAt(1), " \\")) {
                int end = delimited(part, 2, part.charAt(1)).end;
                String rest = part.substring(end);
                return rest.equals("a") || rest.equals("i") || rest.equals("c");
            }
        } catch (CommandError ignored) {
            return false;
        }
        return false;
    }

    static boolean validAddress(List<Token> tokens) {
        for (int i = 0; i < tokens.size(); i++) {
            char kind = tokens.get(i).kind;
            if (kind != 'O' && (i != 0 || !oneOf(kind, "N.$'/?"))) return false;
        }
        return true;
    }

    record Addresses(int count, List<Token> left, List<Token> right, boolean semicolon) {
        static Addresses parse(List<Token> tokens) {
            if (tokens.isEmpty()) return new Addresses(0, List.of(), List.of(), false);
            if (tokens.size() == 1 && tokens.getFirst().kind == '%')
                return new Addresses(2, List.of(new Token('N', 1)), List.of(new Token('$')), false);
            int separator = -1;
            for (int i = 0; i < tokens.size(); i++) {
                if (oneOf(tokens.get(i).kind, ",;")) {
                    require(separator < 0, "bad address");
                    separator = i;
                }
            }
            List<Token> left = separator < 0 ? tokens : tokens.subList(0, separator);
            List<Token> right = separator < 0 ? List.of() : tokens.subList(separator + 1, tokens.size());
            require(validAddress(left) && validAddress(right), "bad address");
            return new Addresses(separator < 0 ? 1 : 2, left, right,
                separator >= 0 && tokens.get(separator).kind == ';');
        }
    }

    enum Kind {
        EMPTY, APPEND, INSERT, CHANGE, PRINT, NUMBER, LIST, EQUALS, COUNT, YANK, MARKS, HISTORY, FILES,
        DELETE, PUT, JOIN, JOIN_SPACE, PAGE, INDENT, UNINDENT, UNDO, REDO, CASE, READ, WRITE,
        WRITE_APPEND, EDIT, WRITE_PRINT, MARK, MOVE, COPY, SUBSTITUTE, GLOBAL, INVERSE, SORT
    }

    static char printSuffix(String s) {
        require(s.isEmpty() || s.length() == 1 && oneOf(s.charAt(0), "pnl"), "invalid suffix");
        return s.isEmpty() ? '\0' : s.charAt(0);
    }

    static int positive(String s) {
        if (s.isEmpty()) return 0;
        require(digits(s), "invalid suffix");
        int value = Integer.parseInt(s);
        require(value > 0, "invalid suffix");
        return value;
    }

    static String filename(String s) {
        require(s.length() >= 2 && s.length() <= 9 && s.charAt(0) == ' ', "invalid file name");
        String name = s.substring(1);
        require(name.chars().allMatch(c -> lower((char)c) || digit((char)c)), "invalid file name");
        return name;
    }

    static boolean sortForm(String s) { return s.equals("sort") || s.startsWith("sort "); }

    static final class Command {
        Kind kind = Kind.EMPTY;
        int number;
        char suffix, option;
        String name = "", search = "";
        List<Token> destination = List.of();
        List<Atom> replacement;
        boolean all, reverse, unique, insensitive, numeric;
        Command sub;

        static Command parse(String part) {
            Command c = new Command();
            if (sortForm(part)) {
                c.kind = Kind.SORT;
                require(!part.equals("sort "), "invalid suffix");
                String options = part.length() > 4 ? part.substring(5) : "";
                for (int i = 0; i < options.length(); i++) {
                    switch (options.charAt(i)) {
                        case 'r' -> { require(!c.reverse, "invalid suffix"); c.reverse = true; }
                        case 'u' -> { require(!c.unique, "invalid suffix"); c.unique = true; }
                        case 'i' -> { require(!c.insensitive, "invalid suffix"); c.insensitive = true; }
                        case 'n' -> { require(!c.numeric, "invalid suffix"); c.numeric = true; }
                        default -> throw new CommandError("invalid suffix");
                    }
                }
                require(!c.insensitive || !c.numeric, "invalid suffix");
                return c;
            }
            if (part.isEmpty()) return c;
            char first = part.charAt(0);
            String arg = part.substring(1);
            String simple = "aicpnl=#yKhf";
            Kind[] kinds = {Kind.APPEND, Kind.INSERT, Kind.CHANGE, Kind.PRINT, Kind.NUMBER, Kind.LIST,
                Kind.EQUALS, Kind.COUNT, Kind.YANK, Kind.MARKS, Kind.HISTORY, Kind.FILES};
            int index = simple.indexOf(first);
            if (index >= 0) {
                c.kind = kinds[index];
                require(arg.isEmpty(), "invalid suffix");
                return c;
            }
            switch (first) {
                case 'd', 'x', 'j', 'J' -> {
                    c.kind = switch (first) { case 'd' -> Kind.DELETE; case 'x' -> Kind.PUT;
                        case 'j' -> Kind.JOIN; default -> Kind.JOIN_SPACE; };
                    c.suffix = printSuffix(arg);
                }
                case 'z', '>', '<', 'u' -> {
                    c.kind = switch (first) { case 'z' -> Kind.PAGE; case '>' -> Kind.INDENT;
                        case '<' -> Kind.UNINDENT; default -> Kind.UNDO; };
                    c.number = positive(arg);
                }
                case '~' -> {
                    c.kind = Kind.CASE;
                    require(arg.isEmpty() || arg.equals("u") || arg.equals("l"), "invalid suffix");
                    c.option = arg.isEmpty() ? '\0' : arg.charAt(0);
                }
                case 'r' -> {
                    if (arg.isEmpty() || digits(arg)) { c.kind = Kind.REDO; c.number = positive(arg); }
                    else { c.kind = Kind.READ; c.name = filename(arg); }
                }
                case 'w', 'W', 'e' -> {
                    if (first == 'w' && arg.isEmpty()) c.kind = Kind.WRITE_PRINT;
                    else {
                        c.kind = first == 'w' ? Kind.WRITE : first == 'W' ? Kind.WRITE_APPEND : Kind.EDIT;
                        c.name = filename(arg);
                    }
                }
                case 'k' -> {
                    c.kind = Kind.MARK;
                    require(arg.length() == 1 && lower(arg.charAt(0)), "invalid mark");
                    c.option = arg.charAt(0);
                }
                case 'm', 't' -> {
                    c.kind = first == 'm' ? Kind.MOVE : Kind.COPY;
                    Lexed destination = lexAddresses(arg);
                    require(!destination.tokens.isEmpty() && validAddress(destination.tokens), "invalid destination");
                    c.destination = destination.tokens;
                    c.suffix = printSuffix(arg.substring(destination.end));
                }
                case 's' -> {
                    c.kind = Kind.SUBSTITUTE;
                    c.number = 1;
                    boolean repeated = arg.chars().allMatch(ch -> oneOf((char)ch, "gpnl") || digit((char)ch));
                    int position = 0;
                    if (!repeated) {
                        char delimiter = arg.charAt(0);
                        require(!oneOf(delimiter, " \\"), "missing delimiter");
                        Delimited search = delimited(arg, 1, delimiter);
                        Delimited replacement = delimited(arg, search.end, delimiter);
                        c.search = search.text;
                        if (!arg.substring(search.end, replacement.end - 1).equals("%")) c.replacement = replacement.atoms;
                        position = replacement.end;
                    }
                    boolean counted = false;
                    while (position < arg.length()) {
                        char flag = arg.charAt(position++);
                        if (flag == 'g') {
                            require(!c.all, "invalid suffix");
                            c.all = true;
                        } else if (oneOf(flag, "pnl")) {
                            require(c.suffix == '\0', "invalid suffix");
                            c.suffix = flag;
                        } else if (digit(flag)) {
                            require(!counted, "invalid suffix");
                            counted = true;
                            int start = position - 1;
                            while (position < arg.length() && digit(arg.charAt(position))) position++;
                            c.number = Integer.parseInt(arg.substring(start, position));
                            require(c.number > 0, "invalid suffix");
                        } else throw new CommandError("invalid suffix");
                    }
                }
                case 'g', 'v' -> {
                    c.kind = first == 'g' ? Kind.GLOBAL : Kind.INVERSE;
                    require(!arg.isEmpty() && !oneOf(arg.charAt(0), " \\"), "missing delimiter");
                    Delimited search = delimited(arg, 1, arg.charAt(0));
                    c.search = search.text;
                    String body = arg.substring(search.end);
                    if (body.isEmpty()) body = "p";
                    require(oneOf(body.charAt(0), "pnldmtjJs><~aicx") && !sortForm(body), "invalid global command");
                    c.sub = parse(body);
                }
                default -> throw new CommandError("unknown command");
            }
            return c;
        }

        int addressKind() {
            return switch (kind) {
                case UNDO, REDO, HISTORY, MARKS, FILES, EDIT -> 0;
                case APPEND, INSERT, PUT, EQUALS, READ, MARK, PAGE -> 1;
                default -> 2;
            };
        }

        boolean modifying() {
            return switch (kind) {
                case APPEND, INSERT, CHANGE, DELETE, PUT, JOIN, JOIN_SPACE, MOVE, COPY, SUBSTITUTE,
                    INDENT, UNINDENT, CASE, SORT, READ, EDIT -> true;
                case GLOBAL, INVERSE -> sub.modifying();
                default -> false;
            };
        }
    }

    record Line(long id, String text) {}
    record Snapshot(List<Line> buffer, int current) {}
    record HistoryRecord(String command, Snapshot state) {}
    record Range(int first, int last) {}

    static final class State {
        ArrayList<Line> buffer = new ArrayList<>();
        int current, display = 5;
        long[] marks = new long[26];
        List<String> cut = List.of();
        String pattern;
        List<Atom> replacement;
        ArrayList<HistoryRecord> undo = new ArrayList<>(), redo = new ArrayList<>();
        TreeMap<String, List<String>> files = new TreeMap<>();
        long nextId = 1;

        State copy() {
            State copy = new State();
            copy.buffer = new ArrayList<>(buffer);
            copy.current = current;
            copy.display = display;
            copy.marks = marks.clone();
            copy.cut = cut;
            copy.pattern = pattern;
            copy.replacement = replacement;
            copy.undo = new ArrayList<>(undo);
            copy.redo = new ArrayList<>(redo);
            copy.files = new TreeMap<>(files);
            copy.nextId = nextId;
            return copy;
        }

        Snapshot snapshot() { return new Snapshot(List.copyOf(buffer), current); }

        int locate(long id) {
            for (int i = 0; i < buffer.size(); i++) if (buffer.get(i).id == id) return i + 1;
            return 0;
        }

        String resolvePattern(String search) {
            if (!search.isEmpty()) pattern = search;
            require(pattern != null, "no previous pattern");
            return pattern;
        }

        int address(List<Token> tokens) {
            int value = current;
            for (Token token : tokens) {
                switch (token.kind) {
                    case 'O' -> value += token.number;
                    case 'N' -> value = token.number;
                    case '.' -> value = current;
                    case '$' -> value = buffer.size();
                    case '\'' -> {
                        require(lower(token.name), "invalid mark");
                        value = locate(marks[token.name - 'a']);
                        require(value != 0, "mark not set");
                    }
                    case '/', '?' -> {
                        String pattern = resolvePattern(token.search);
                        int size = buffer.size(), start = token.kind == '?' && current == 0 ? size + 1 : current;
                        value = 0;
                        for (int step = 1; step <= size; step++) {
                            int index = token.kind == '/' ? (start + step - 1) % size : Math.floorMod(start - step - 1, size);
                            if (buffer.get(index).text.contains(pattern)) { value = index + 1; break; }
                        }
                        require(value != 0, "no match");
                    }
                    default -> throw new AssertionError();
                }
            }
            return value;
        }

        Range evaluate(Addresses addresses) {
            if (addresses.count == 0) return new Range(0, 0);
            int a = addresses.left.isEmpty() ? (addresses.semicolon ? current : 1) : address(addresses.left);
            int b = 0;
            if (addresses.count == 2) {
                if (addresses.semicolon) {
                    require(a >= 0 && a <= buffer.size(), "address out of range");
                    current = a;
                }
                b = addresses.right.isEmpty() ? buffer.size() : address(addresses.right);
            }
            return new Range(a, b);
        }

        Range checkedRange(Command c, int count, Range values) {
            int size = buffer.size(), a = values.first, b = values.last;
            if (c.addressKind() == 0) return new Range(0, 0);
            if (c.addressKind() == 1) {
                if (count == 0) a = switch (c.kind) {
                    case EQUALS, READ -> size;
                    case PAGE -> current + 1;
                    default -> current;
                };
                int minimum = c.kind == Kind.MARK || c.kind == Kind.PAGE ? 1 : 0;
                require(a >= minimum && a <= size, "address out of range");
                return new Range(a, a);
            }
            if (count == 0) {
                switch (c.kind) {
                    case WRITE, WRITE_APPEND, WRITE_PRINT, COUNT -> { return new Range(1, size); }
                    case GLOBAL, INVERSE, SORT -> { a = 1; b = size; }
                    case JOIN, JOIN_SPACE -> { a = current; b = current + 1; }
                    default -> { a = current; b = current; }
                }
            } else if (count == 1) b = a;
            require(a >= 1 && a <= size && b >= 1 && b <= size, "address out of range");
            require(a <= b && (a != b || c.kind != Kind.JOIN && c.kind != Kind.JOIN_SPACE), "invalid range");
            return new Range(a, b);
        }

        void printLine(int number, char form, StringBuilder output) {
            String text = buffer.get(number - 1).text;
            if (form == 'n') emit(output, "%3d %s\n", number, text);
            else if (form == 'l') {
                String escaped = text.replace("\\", "\\\\") + "$";
                int position = 0;
                while (escaped.length() - position > 40) {
                    emit(output, "%s\\\n", escaped.substring(position, position + 39));
                    position += 39;
                }
                emit(output, "%s\n", escaped.substring(position));
            } else emit(output, "%s\n", text);
        }

        List<String> contents(Range range) {
            return buffer.subList(range.first - 1, range.last).stream().map(Line::text).toList();
        }

        void insert(int after, List<String> text) {
            List<Line> lines = new ArrayList<>();
            for (String value : text) lines.add(new Line(nextId++, value));
            buffer.addAll(after, lines);
        }

        void setText(int index, String text) { buffer.set(index, new Line(buffer.get(index).id, text)); }

        boolean substitute(Command c, Range range, StringBuilder output, boolean inGlobal) {
            String pattern = resolvePattern(c.search);
            List<Atom> used = c.replacement != null ? c.replacement : replacement;
            require(used != null, "no previous substitution");
            replacement = used;
            StringBuilder expanded = new StringBuilder();
            for (Atom atom : used) {
                if (atom.matched) expanded.append(pattern);
                else expanded.append(atom.character);
            }
            int last = 0;
            for (int i = range.first; i <= range.last; i++) {
                String old = buffer.get(i - 1).text;
                StringBuilder result = new StringBuilder();
                int position = 0, occurrence = 0, start;
                boolean changed = false;
                while ((start = old.indexOf(pattern, position)) >= 0) {
                    result.append(old, position, start);
                    occurrence++;
                    if (occurrence == c.number || c.all && occurrence > c.number) {
                        result.append(expanded);
                        changed = true;
                    } else result.append(pattern);
                    position = start + pattern.length();
                }
                result.append(old, position, old.length());
                if (changed) {
                    require(result.length() <= 80, "line too long");
                    require(!result.isEmpty() && result.charAt(result.length() - 1) != ' ', "bad line");
                    setText(i - 1, result.toString());
                    last = i;
                }
            }
            require(last != 0 || inGlobal, "no match");
            if (last != 0) {
                current = last;
                if (c.suffix != '\0') printLine(last, c.suffix, output);
            }
            return last != 0;
        }

        void sortLines(Command c, Range range) {
            List<Line> lines = new ArrayList<>(buffer.subList(range.first - 1, range.last));
            Comparator<Line> key = c.numeric
                ? Comparator.comparingLong((Line line) -> leadingInteger(line.text))
                : Comparator.comparing((Line line) -> c.insensitive ? line.text.toLowerCase(Locale.ROOT) : line.text);
            lines.sort(c.reverse ? key.reversed() : key);
            if (c.unique) {
                List<Line> unique = new ArrayList<>();
                for (Line line : lines)
                    if (unique.isEmpty() || key.compare(unique.getLast(), line) != 0) unique.add(line);
                lines = unique;
            }
            buffer.subList(range.first - 1, range.last).clear();
            buffer.addAll(range.first - 1, lines);
            current = range.first + lines.size() - 1;
        }

        void fileCommand(Command c, Range range, StringBuilder output) {
            List<String> file = files.get(c.name);
            if (c.kind == Kind.WRITE || c.kind == Kind.WRITE_APPEND) {
                List<String> changed = new ArrayList<>();
                if (c.kind == Kind.WRITE_APPEND && file != null) changed.addAll(file);
                changed.addAll(contents(range));
                file = List.copyOf(changed);
                files.put(c.name, file);
            } else {
                require(file != null, "no such file");
                int after = range.first;
                if (c.kind == Kind.EDIT) { buffer.clear(); after = 0; }
                insert(after, file);
                current = after + file.size();
            }
            emit(output, "file %s lines=%d bytes=%d\n", c.name, file.size(), fileBytes(file));
        }

        void transferHistory(boolean isRedo, int count) {
            ArrayList<HistoryRecord> from = isRedo ? redo : undo, to = isRedo ? undo : redo;
            require(from.size() >= count, isRedo ? "nothing to redo" : "nothing to undo");
            for (int i = 0; i < count; i++) {
                HistoryRecord record = from.removeLast();
                to.add(new HistoryRecord(record.command, snapshot()));
                buffer = new ArrayList<>(record.state.buffer);
                current = record.state.current;
            }
        }

        boolean execute(Command c, Range range, List<String> text, StringBuilder output, boolean inGlobal) {
            int a = range.first, b = range.last;
            switch (c.kind) {
                case EMPTY -> { printLine(b, 'p', output); current = b; }
                case PRINT, NUMBER, LIST -> {
                    char form = c.kind == Kind.PRINT ? 'p' : c.kind == Kind.NUMBER ? 'n' : 'l';
                    for (int i = a; i <= b; i++) printLine(i, form, output);
                    current = b;
                }
                case PAGE -> {
                    if (c.number != 0) display = c.number;
                    int last = Math.min(a + display - 1, buffer.size());
                    for (int i = a; i <= last; i++) printLine(i, 'p', output);
                    current = last;
                }
                case EQUALS -> emit(output, "%d\n", a);
                case COUNT, WRITE_PRINT -> {
                    int words = 0, chars = 0;
                    for (int i = a; i <= b; i++) {
                        String value = buffer.get(i - 1).text;
                        chars += value.length();
                        for (int j = 0; j < value.length(); j++)
                            if (value.charAt(j) != ' ' && (j == 0 || value.charAt(j - 1) == ' ')) words++;
                        if (c.kind == Kind.WRITE_PRINT) printLine(i, 'p', output);
                    }
                    int count = b - a + 1;
                    if (c.kind == Kind.COUNT) emit(output, "count lines=%d words=%d chars=%d\n", count, words, chars);
                    else emit(output, "lines=%d bytes=%d\n", count, chars + count);
                }
                case APPEND, INSERT -> {
                    int after = c.kind == Kind.APPEND ? a : Math.max(a, 1) - 1;
                    insert(after, text);
                    current = after + text.size();
                }
                case CHANGE, DELETE -> {
                    cut = contents(range);
                    buffer.subList(a - 1, b).clear();
                    if (c.kind == Kind.CHANGE) insert(a - 1, text);
                    current = c.kind == Kind.CHANGE && !text.isEmpty() ? a + text.size() - 1 : Math.min(a, buffer.size());
                }
                case YANK -> cut = contents(range);
                case PUT -> {
                    require(!cut.isEmpty(), "nothing to put");
                    insert(a, cut);
                    current = a + cut.size();
                }
                case MOVE, COPY -> {
                    int destination = address(c.destination);
                    require(destination >= 0 && destination <= buffer.size(), "address out of range");
                    require(c.kind != Kind.MOVE || destination < a || destination >= b, "invalid destination");
                    List<Line> moved = new ArrayList<>(buffer.subList(a - 1, b));
                    if (c.kind == Kind.MOVE) {
                        buffer.subList(a - 1, b).clear();
                        if (destination >= b) destination -= moved.size();
                    } else {
                        for (int i = 0; i < moved.size(); i++) moved.set(i, new Line(nextId++, moved.get(i).text));
                    }
                    buffer.addAll(destination, moved);
                    current = destination + moved.size();
                }
                case JOIN, JOIN_SPACE -> {
                    StringBuilder joined = new StringBuilder(buffer.get(a - 1).text);
                    for (int i = a + 1; i <= b; i++) {
                        String value = buffer.get(i - 1).text;
                        if (c.kind == Kind.JOIN_SPACE) {
                            joined.append(' ');
                            int start = 0;
                            while (value.charAt(start) == ' ') start++;
                            value = value.substring(start);
                        }
                        joined.append(value);
                    }
                    require(joined.length() <= 80, "line too long");
                    setText(a - 1, joined.toString());
                    buffer.subList(a, b).clear();
                    current = a;
                }
                case INDENT, UNINDENT, CASE -> {
                    int width = c.number == 0 ? 4 : c.number;
                    for (int i = a; i <= b; i++) {
                        String value = buffer.get(i - 1).text;
                        if (c.kind == Kind.INDENT) {
                            require(value.length() + width <= 80, "line too long");
                            value = " ".repeat(width) + value;
                        } else if (c.kind == Kind.UNINDENT) {
                            int removed = 0;
                            while (removed < width && value.charAt(removed) == ' ') removed++;
                            value = value.substring(removed);
                        } else {
                            char[] converted = value.toCharArray();
                            for (int j = 0; j < converted.length; j++) {
                                if (lower(converted[j]) && c.option != 'l') converted[j] = (char)(converted[j] - 'a' + 'A');
                                else if (upper(converted[j]) && c.option != 'u') converted[j] = (char)(converted[j] - 'A' + 'a');
                            }
                            value = new String(converted);
                        }
                        setText(i - 1, value);
                    }
                    current = b;
                }
                case SORT -> sortLines(c, range);
                case SUBSTITUTE -> { return substitute(c, range, output, inGlobal); }
                case MARK -> marks[c.option - 'a'] = buffer.get(a - 1).id;
                case MARKS -> {
                    output.append("marks");
                    boolean any = false;
                    for (int i = 0; i < marks.length; i++) {
                        int position = locate(marks[i]);
                        if (position != 0) { emit(output, " %c=%d", (char)('a' + i), position); any = true; }
                    }
                    output.append(any ? "\n" : " none\n");
                }
                case UNDO, REDO -> transferHistory(c.kind == Kind.REDO, c.number == 0 ? 1 : c.number);
                case HISTORY -> {
                    emit(output, "history undo=%d redo=%d\n", undo.size(), redo.size());
                    for (int side = 0; side < 2; side++) {
                        List<HistoryRecord> records = side == 0 ? undo : redo;
                        for (int i = records.size() - 1; i >= 0; i--)
                            emit(output, "%s %d: %s\n", side == 0 ? "undo" : "redo", records.size() - i, records.get(i).command);
                    }
                }
                case READ, WRITE, WRITE_APPEND, EDIT -> fileCommand(c, range, output);
                case FILES -> {
                    output.append("files");
                    for (Map.Entry<String, List<String>> file : files.entrySet()) emit(output, " %s=%d", file.getKey(), file.getValue().size());
                    output.append(files.isEmpty() ? " none\n" : "\n");
                }
                case GLOBAL, INVERSE -> {
                    String pattern = resolvePattern(c.search);
                    List<Long> selected = new ArrayList<>();
                    for (Line line : buffer.subList(a - 1, b))
                        if (line.text.contains(pattern) == (c.kind == Kind.GLOBAL)) selected.add(line.id);
                    require(!selected.isEmpty(), "no match");
                    boolean substituted = false;
                    for (long id : selected) {
                        int position = locate(id);
                        if (position != 0) {
                            current = position;
                            Range subrange = checkedRange(c.sub, 0, new Range(0, 0));
                            boolean changed = execute(c.sub, subrange, text, output, true);
                            substituted |= changed;
                        }
                    }
                    require(c.sub.kind != Kind.SUBSTITUTE || substituted, "no match");
                }
            }
            if (c.suffix != '\0' && current >= 1) printLine(current, c.suffix, output);
            return false;
        }
    }

    static long leadingInteger(String text) {
        boolean negative = text.charAt(0) == '-';
        int position = negative ? 1 : 0;
        long value = 0;
        while (position < text.length() && digit(text.charAt(position))) value = value * 10 + text.charAt(position++) - '0';
        return negative ? -value : value;
    }

    static int fileBytes(List<String> file) { return file.stream().mapToInt(line -> line.length() + 1).sum(); }

    static void emit(StringBuilder output, String format, Object... arguments) {
        output.append(String.format(Locale.ROOT, format, arguments));
    }

    static final class Editor {
        State state = new State();

        String apply(String line, List<String> text) {
            Lexed lexed = lexAddresses(line);
            Addresses addresses = Addresses.parse(lexed.tokens);
            Command command = Command.parse(line.substring(lexed.end));
            require(command.addressKind() != 0 || addresses.count == 0, "unexpected address");
            require(command.addressKind() != 1 || addresses.count != 2, "too many addresses");
            // Only a successful command publishes the trial state and its output.
            State trial = state.copy();
            Range values = trial.evaluate(addresses);
            Range range = trial.checkedRange(command, addresses.count, values);
            StringBuilder output = new StringBuilder();
            trial.execute(command, range, text, output, false);
            require(trial.buffer.size() <= 200, "buffer full");
            if (command.modifying()) {
                trial.undo.add(new HistoryRecord(line, state.snapshot()));
                trial.redo.clear();
            }
            state = trial;
            return output.toString();
        }
    }

    public static void main(String[] args) throws Exception {
        BufferedReader input = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.US_ASCII));
        BufferedWriter output = new BufferedWriter(new OutputStreamWriter(System.out, StandardCharsets.US_ASCII));
        Editor editor = new Editor();
        String line;
        while ((line = input.readLine()) != null && !line.equals("Q")) {
            List<String> text = new ArrayList<>();
            if (withText(line)) {
                String entered;
                while ((entered = input.readLine()) != null && !entered.equals(".")) text.add(entered);
            }
            try {
                output.write(editor.apply(line, text));
            } catch (CommandError error) {
                output.write("? " + error.getMessage() + "\n");
            }
        }
        output.flush();
    }
}
