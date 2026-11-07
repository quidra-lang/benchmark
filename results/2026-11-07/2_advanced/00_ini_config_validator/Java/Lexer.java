import java.util.ArrayList;
import java.util.List;

record LogicalLine(int number, List<String> segments, String code, String message) {}

final class Lexer {
    static final char LITERAL_DOLLAR = '\u0001';

    static List<LogicalLine> lines(List<String> physical) {
        List<LogicalLine> result = new ArrayList<>();
        int index = 0;
        while (index < physical.size()) {
            int number = index + 1;
            String source = physical.get(index++);
            List<String> segments = new ArrayList<>();
            StringBuilder current = new StringBuilder();
            boolean quoted = false;
            String code = "", message = "";
            int position = 0;
            while (position < source.length()) {
                char c = source.charAt(position);
                if (c == '\\' && position == source.length() - 1) {
                    source = physical.get(index++).replaceFirst("^ +", "");
                    position = 0;
                } else if (quoted && c == '\\') {
                    char follower = source.charAt(position + 1);
                    switch (follower) {
                        case '\\', '"' -> current.append(follower);
                        case 'n' -> current.append('\n');
                        case 't' -> current.append('\t');
                        case '$' -> current.append(LITERAL_DOLLAR);
                        default -> {
                            if (code.isEmpty()) {
                                code = "E_ESCAPE";
                                message = "invalid escape sequence \\" + follower;
                            }
                        }
                    }
                    position += 2;
                } else if (c == '"') {
                    segments.add(current.toString());
                    current.setLength(0);
                    quoted = !quoted;
                    position++;
                } else if (!quoted && (c == ';' || c == '#')) {
                    break;
                } else {
                    current.append(c);
                    position++;
                }
            }
            if (quoted && code.isEmpty()) {
                code = "E_UNTERMINATED";
                message = "unterminated string";
            }
            segments.add(current.toString());
            result.add(new LogicalLine(number, segments, code, message));
        }
        return result;
    }
}
