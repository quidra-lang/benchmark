import java.util.*;
final class Tiles {
    record Tile(int kind, boolean red) {}
    static final String SUITS = "mpsz", WINDS = "ESWN";
    static final List<Integer> YAOCHUU = List.of(0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33);
    static final Set<Integer> GREEN = Set.of(19, 20, 21, 23, 25, 32);
    static List<Tile> parse(String text, boolean allowEmpty) {
        if (text.equals("-"))
            return allowEmpty ? new ArrayList<>() : null;
        List<Tile> result = new ArrayList<>();
        List<Integer> digits = new ArrayList<>();
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c >= '0' && c <= '9')
                digits.add(c - '0');
            else {
                int suit = SUITS.indexOf(c);
                if (suit < 0 || digits.isEmpty())
                    return null;
                for (int digit : digits) {
                    if (suit == 3 && (digit < 1 || digit > 7))
                        return null;
                    result.add(new Tile(suit * 9 + (digit == 0 ? 5 : digit) - 1, digit == 0));
                }
                digits.clear();
            }
        }
        return result.isEmpty() || !digits.isEmpty() ? null : result;
    }
    static List<Tile> parse(String text) { return parse(text, false); }
    static String name(int kind) { return Integer.toString(kind % 9 + 1) + SUITS.charAt(kind / 9); }
    static String block(List<Integer> kinds) {
        List<Integer> ordered = new ArrayList<>(kinds);
        Collections.sort(ordered);
        StringBuilder result = new StringBuilder();
        for (int kind : ordered)
            result.append(kind % 9 + 1);
        return result.toString() + SUITS.charAt(ordered.getFirst() / 9);
    }
    static int[] counts(Collection<Tile> tiles) {
        int[] result = new int[34];
        for (Tile tile : tiles)
            result[tile.kind()]++;
        return result;
    }
    static boolean honor(int kind) { return kind >= 27; }
    static boolean terminal(int kind) { return kind < 27 && (kind % 9 == 0 || kind % 9 == 8); }
    static boolean yaochuu(int kind) { return honor(kind) || terminal(kind); }
    static int nextDora(int kind) {
        return kind < 27 ? kind / 9 * 9 + (kind % 9 + 1) % 9
        : kind < 31      ? 27 + (kind - 26) % 4
                         : 31 + (kind - 30) % 3;
    }
    static int windTile(String wind) { return 27 + WINDS.indexOf(wind); }
    static String key(int[] counts) {
        StringBuilder key = new StringBuilder();
        for (int count : counts)
            key.append((char)('0' + count));
        return key.toString();
    }
}
