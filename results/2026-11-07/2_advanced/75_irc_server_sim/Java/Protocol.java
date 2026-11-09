import java.util.*;
final class Protocol {
    static final String SPECIAL = "[]\\`_^{}|";
    record Message(String command, List<String> parameters) {}
    static String fold(String value) {
        StringBuilder result = new StringBuilder();
        for (char c : value.toCharArray())
            result.append(c >= 'A' && c <= 'Z' ? (char)(c + 32) : switch (c) {
                case '[' -> '{';
                case ']' -> '}';
                case '\\' -> '|';
                case '^' -> '~';
                default -> c;
            });
        return result.toString();
    }
    static boolean letter(char c) { return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z'; }
    static boolean digits(String value) {
        if (value.isEmpty())
            return false;
        for (char c : value.toCharArray())
            if (c < '0' || c > '9')
                return false;
        return true;
    }
    static boolean validNickname(String value) {
        if (value.isEmpty() || !letter(value.charAt(0)) && SPECIAL.indexOf(value.charAt(0)) < 0)
            return false;
        for (int i = 1; i < value.length(); i++) {
            char c = value.charAt(i);
            if (!letter(c) && SPECIAL.indexOf(c) < 0 && !(c >= '0' && c <= '9') && c != '-')
                return false;
        }
        return true;
    }
    static boolean validChannel(String value, int maximum) {
        return value.length() >= 2 && value.length() <= maximum && value.startsWith("#") &&
            !value.contains(":");
    }
    static Message parse(String raw) {
        int position = 0;
        if (raw.startsWith(":")) {
            position = raw.indexOf(' ');
            if (position < 0)
                return new Message("", List.of());
        }
        while (position < raw.length() && raw.charAt(position) == ' ')
            position++;
        int start = position;
        while (position < raw.length() && raw.charAt(position) != ' ')
            position++;
        String command = raw.substring(start, position).toUpperCase(Locale.ROOT);
        List<String> parameters = new ArrayList<>();
        while (position < raw.length()) {
            while (position < raw.length() && raw.charAt(position) == ' ')
                position++;
            if (position == raw.length())
                break;
            if (raw.charAt(position) == ':') {
                parameters.add(raw.substring(position + 1));
                break;
            }
            if (parameters.size() == 14) {
                parameters.add(raw.substring(position));
                break;
            }
            start = position;
            while (position < raw.length() && raw.charAt(position) != ' ')
                position++;
            parameters.add(raw.substring(start, position));
        }
        return new Message(command, parameters);
    }
}
