import java.util.*;
import java.util.function.Function;
final class ValuesFields {
    enum Kind { NUMBER, STRING, STRNUM, UNINITIALIZED }
    record Value(Kind kind, String text, int numeric) {}
    static final Value UNINITIALIZED = new Value(Kind.UNINITIALIZED, null, 0);
    static Value number(int value) { return new Value(Kind.NUMBER, null, value); }
    static Value string(String value) { return new Value(Kind.STRING, value, 0); }
    static boolean whitespace(char c) { return c == ' ' || c == '\t' || c == '\n'; }
    static int numericPrefix(String text) {
        int index = 0, sign = 1, result = 0;
        while (index < text.length() && whitespace(text.charAt(index)))
            index++;
        if (index < text.length() && (text.charAt(index) == '+' || text.charAt(index) == '-')) {
            if (text.charAt(index) == '-')
                sign = -1;
            index++;
        }
        while (index < text.length() && Lexer.digit(text.charAt(index)))
            result = result * 10 + text.charAt(index++) - '0';
        return sign * result;
    }
    static Value input(String text) {
        int start = 0, end = text.length();
        while (start < end && whitespace(text.charAt(start)))
            start++;
        while (end > start && whitespace(text.charAt(end - 1)))
            end--;
        int digits = start;
        if (digits < end && (text.charAt(digits) == '+' || text.charAt(digits) == '-'))
            digits++;
        boolean numeric = digits < end;
        for (int i = digits; i < end; i++)
            if (!Lexer.digit(text.charAt(i)))
                numeric = false;
        return numeric ? new Value(Kind.STRNUM, text, numericPrefix(text)) : string(text);
    }
    static int numeric(Value value) {
        return value.kind() == Kind.STRING ? numericPrefix(value.text()) : value.numeric();
    }
    static String text(Value value) {
        return switch (value.kind()) {
            case NUMBER -> Integer.toString(value.numeric());
            case UNINITIALIZED -> "";
            default -> value.text();
        };
    }
    static boolean truth(Value value) {
        return value.kind() == Kind.STRING ? !value.text().isEmpty() : value.numeric() != 0;
    }
    static int compare(Value first, Value second) {
        return first.kind() != Kind.STRING && second.kind() != Kind.STRING
            ? Integer.compare(numeric(first), numeric(second))
            : text(first).compareTo(text(second));
    }
    static boolean integerKey(String text) {
        if (text.equals("0"))
            return true;
        int start = text.startsWith("-") ? 1 : 0;
        if (start == text.length() || text.charAt(start) < '1' || text.charAt(start) > '9')
            return false;
        for (int i = start + 1; i < text.length(); i++)
            if (!Lexer.digit(text.charAt(i)))
                return false;
        return true;
    }
    static final Comparator<String> KEY_ORDER = (first, second) -> {
        boolean a = integerKey(first), b = integerKey(second);
        return a && b ? Integer.compare(Integer.parseInt(first), Integer.parseInt(second))
        : a           ? -1
        : b           ? 1
                      : first.compareTo(second);
    };
    static List<String> split(String text, String separator) {
        List<String> result = new ArrayList<>();
        if (text.isEmpty())
            return result;
        if (separator.isEmpty()) {
            for (int i = 0; i < text.length(); i++)
                result.add(text.substring(i, i + 1));
        } else if (separator.equals(" ")) {
            int start = -1;
            for (int i = 0; i < text.length(); i++) {
                if (whitespace(text.charAt(i))) {
                    if (start >= 0) {
                        result.add(text.substring(start, i));
                        start = -1;
                    }
                } else if (start < 0)
                    start = i;
            }
            if (start >= 0)
                result.add(text.substring(start));
        } else {
            int start = 0, next;
            while ((next = text.indexOf(separator, start)) >= 0) {
                result.add(text.substring(start, next));
                start = next + separator.length();
            }
            result.add(text.substring(start));
        }
        return result;
    }
    static final class Record {
        final Function<String, Value> special;
        Value zero = string("");
        final List<Value> fields = new ArrayList<>();
        Record(Function<String, Value> special) { this.special = special; }
        void set(String text) {
            zero = input(text);
            fields.clear();
            for (String piece : split(text, text(special.apply("FS"))))
                fields.add(input(piece));
        }
        Value read(int index) {
            return index == 0        ? zero
            : index <= fields.size() ? fields.get(index - 1)
                                     : UNINITIALIZED;
        }
        void rebuild() {
            StringJoiner joined = new StringJoiner(text(special.apply("OFS")));
            for (Value value : fields)
                joined.add(text(value));
            zero = input(joined.toString());
        }
        void write(int index, Value value) {
            if (index == 0) {
                set(text(value));
                return;
            }
            while (fields.size() < index)
                fields.add(string(""));
            fields.set(index - 1, value);
            rebuild();
        }
        void resize(int size) {
            while (fields.size() > size)
                fields.removeLast();
            while (fields.size() < size)
                fields.add(string(""));
            rebuild();
        }
    }
    static String quoted(String text) {
        StringBuilder result = new StringBuilder("\"");
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            result.append(switch (c) {
                case '"' -> "\\\"";
                case '\\' -> "\\\\";
                case '\n' -> "\\n";
                case '\t' -> "\\t";
                default ->
                    c >= 32 && c <= 126 ? String.valueOf(c)
                                        : "\\" + String.format(Locale.ROOT, "%03o", (int)c);
            });
        }
        return result.append('"').toString();
    }
    static String describe(Value value) {
        return switch (value.kind()) {
            case NUMBER -> Integer.toString(value.numeric());
            case UNINITIALIZED -> "(uninitialized)";
            default -> quoted(value.text()) + (value.kind() == Kind.STRNUM ? " (strnum)" : "");
        };
    }
}
