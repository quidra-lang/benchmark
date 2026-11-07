import java.util.*;
final class Builtins {
    static final class RuntimeIssue extends RuntimeException {
        final Lexer.Position pos;
        RuntimeIssue(Lexer.Position pos, String message) {
            super(message);
            this.pos = pos;
        }
    }
    static String format(List<ValuesFields.Value> arguments, Lexer.Position pos) {
        String fmt = ValuesFields.text(arguments.getFirst());
        StringBuilder result = new StringBuilder();
        int index = 0, argument = 1;
        while (index < fmt.length()) {
            char c = fmt.charAt(index++);
            if (c != '%') {
                result.append(c);
                continue;
            }
            if (index < fmt.length() && fmt.charAt(index) == '%') {
                result.append('%');
                index++;
                continue;
            }
            boolean left = false, zero = false;
            while (index < fmt.length() && (fmt.charAt(index) == '-' || fmt.charAt(index) == '0')) {
                if (fmt.charAt(index) == '-')
                    left = true;
                else
                    zero = true;
                index++;
            }
            int width = 0;
            while (index < fmt.length() && Lexer.digit(fmt.charAt(index)))
                width = 10 * width + fmt.charAt(index++) - '0';
            Integer precision = null;
            if (index < fmt.length() && fmt.charAt(index) == '.') {
                index++;
                int value = 0;
                while (index < fmt.length() && Lexer.digit(fmt.charAt(index)))
                    value = 10 * value + fmt.charAt(index++) - '0';
                precision = value;
            }
            if (index == fmt.length() || "discxo".indexOf(fmt.charAt(index)) < 0)
                throw new RuntimeIssue(pos, "invalid format");
            char conversion = fmt.charAt(index++);
            if (argument == arguments.size())
                throw new RuntimeIssue(pos, "not enough arguments");
            ValuesFields.Value value = arguments.get(argument++);
            boolean numeric = "dixo".indexOf(conversion) >= 0;
            String body;
            if (numeric) {
                int n = ValuesFields.numeric(value), radix = conversion == 'x'   ? 16
                                                             : conversion == 'o' ? 8
                                                                                 : 10;
                String digits = Long.toString(Math.abs((long)n), radix);
                if (precision != null) {
                    if (precision == 0 && n == 0)
                        digits = "";
                    else if (digits.length() < precision)
                        digits = "0".repeat(precision - digits.length()) + digits;
                }
                body = (n < 0 ? "-" : "") + digits;
            } else if (conversion == 's') {
                body = ValuesFields.text(value);
                if (precision != null)
                    body = body.substring(0, Math.min(body.length(), precision));
            } else if (value.kind() == ValuesFields.Kind.NUMBER ||
                       value.kind() == ValuesFields.Kind.STRNUM) {
                int code = ValuesFields.numeric(value);
                if (code != 10 && (code < 32 || code > 126))
                    throw new RuntimeIssue(pos, "invalid character code");
                body = String.valueOf((char)code);
            } else {
                body = ValuesFields.text(value);
                body = body.substring(0, Math.min(1, body.length()));
            }
            int missing = width - body.length();
            if (missing > 0) {
                if (left)
                    body += " ".repeat(missing);
                else if (numeric && zero && precision == null)
                    body = body.startsWith("-") ? "-"
                                                      + "0".repeat(missing) + body.substring(1)
                                                : "0".repeat(missing) + body;
                else
                    body = " ".repeat(missing) + body;
            }
            result.append(body);
        }
        return result.toString();
    }
    static ValuesFields.Value invoke(String name, List<ValuesFields.Value> args,
                                     Lexer.Position pos) {
        if (name.equals("sprintf"))
            return ValuesFields.string(format(args, pos));
        if (name.equals("int"))
            return ValuesFields.number(ValuesFields.numeric(args.getFirst()));
        String text = ValuesFields.text(args.getFirst());
        if (name.equals("substr")) {
            int start = ValuesFields.numeric(args.get(1)),
                end = args.size() == 3 ? start + ValuesFields.numeric(args.get(2))
                                       : text.length() + 1;
            start = Math.max(start, 1);
            end = Math.min(end, text.length() + 1);
            return ValuesFields.string(end > start ? text.substring(start - 1, end - 1) : "");
        }
        if (name.equals("index")) {
            String sought = ValuesFields.text(args.get(1));
            return ValuesFields.number(sought.isEmpty() ? 0 : text.indexOf(sought) + 1);
        }
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (name.equals("toupper") && c >= 'a' && c <= 'z')
                c = (char)(c - 'a' + 'A');
            else if (name.equals("tolower") && c >= 'A' && c <= 'Z')
                c = (char)(c - 'A' + 'a');
            result.append(c);
        }
        return ValuesFields.string(result.toString());
    }
}
