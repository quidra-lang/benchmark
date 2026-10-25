import java.util.HashSet;
import java.util.Set;

final class Playfair {
    private Playfair() {}

    static String square(String key) {
        Set<Character> used = new HashSet<>();
        StringBuilder result = new StringBuilder();
        String source = key.toUpperCase().replace('J', 'I') + "ABCDEFGHIKLMNOPQRSTUVWXYZ";
        for (int i = 0; i < source.length(); i++) {
            char c = source.charAt(i);
            if (used.add(c)) result.append(c);
        }
        return result.toString();
    }

    static boolean valid(String text) {
        String normalized = text.replace('J', 'I');
        if (normalized.length() % 2 != 0) return false;
        for (int i = 0; i < normalized.length(); i += 2)
            if (normalized.charAt(i) == normalized.charAt(i + 1)) return false;
        return true;
    }

    static String prepare(String text) {
        String normalized = text.replace('J', 'I');
        StringBuilder result = new StringBuilder();
        for (int index = 0; index < normalized.length();) {
            char first = normalized.charAt(index);
            char second;
            if (index + 1 < normalized.length() && normalized.charAt(index + 1) != first) {
                second = normalized.charAt(index + 1);
                index += 2;
            } else {
                second = first == 'X' ? 'Q' : 'X';
                index++;
            }
            result.append(first).append(second);
        }
        return result.toString();
    }

    static String apply(String text, String key, boolean encrypt) {
        String board = square(key);
        String input = encrypt ? prepare(text) : text.replace('J', 'I');
        int distance = encrypt ? 1 : 4;
        StringBuilder result = new StringBuilder(input.length());
        for (int i = 0; i < input.length(); i += 2) {
            int a = board.indexOf(input.charAt(i));
            int b = board.indexOf(input.charAt(i + 1));
            int ra = a / 5, ca = a % 5;
            int rb = b / 5, cb = b % 5;
            if (ra == rb) {
                ca = (ca + distance) % 5;
                cb = (cb + distance) % 5;
            } else if (ca == cb) {
                ra = (ra + distance) % 5;
                rb = (rb + distance) % 5;
            } else {
                int tmp = ca;
                ca = cb;
                cb = tmp;
            }
            result.append(board.charAt(5 * ra + ca));
            result.append(board.charAt(5 * rb + cb));
        }
        return result.toString();
    }
}
