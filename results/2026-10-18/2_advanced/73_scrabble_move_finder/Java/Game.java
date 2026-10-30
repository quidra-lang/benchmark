import java.util.*;
final class Game {
    static final String TILE_ORDER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ?";
    static final class Minstd {
        long state;
        Minstd(int seed) { state = seed; }
        int next() {
            state = state * 48271 % 2147483647;
            return (int)state;
        }
    }
    static void shuffle(List<Character> bag, Minstd random) {
        for (int i = bag.size() - 1; i >= 1; i--) {
            int j = random.next() % (i + 1);
            char tile = bag.get(i);
            bag.set(i, bag.get(j));
            bag.set(j, tile);
        }
    }
    static List<Character> bag(int[] counts, Minstd random) {
        List<Character> result = new ArrayList<>();
        for (char tile : TILE_ORDER.toCharArray())
            for (int i = 0; i < counts[tile]; i++)
                result.add(tile);
        shuffle(result, random);
        return result;
    }
    static String draw(List<Character> bag, int count) {
        StringBuilder tiles = new StringBuilder();
        while (count-- > 0 && !bag.isEmpty())
            tiles.append(bag.removeLast());
        return tiles.toString();
    }
    static String exchange(List<Character> bag, String returned, Minstd random) {
        String drawn = draw(bag, returned.length());
        char[] ordered = returned.toCharArray();
        Arrays.sort(ordered);
        for (char tile : ordered)
            bag.add(tile);
        shuffle(bag, random);
        return drawn;
    }
    static int points(String collection, int[] values) {
        int result = 0;
        for (char tile : collection.toCharArray())
            result += values[tile];
        return result;
    }
}
