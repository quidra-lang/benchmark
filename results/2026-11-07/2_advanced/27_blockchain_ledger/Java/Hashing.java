import java.util.*;

final class Hashing {
    static String digest(String text) {
        long[] bases = {1000003, 1500007, 2750159, 4194301}, initials = {11, 23, 37, 53};
        StringBuilder result = new StringBuilder();
        for (int lane = 0; lane < 4; lane++) {
            long value = initials[lane];
            for (int i = 0; i < text.length(); i++)
                value = (value * bases[lane] + text.charAt(i)) % 2147483647;
            for (int extra : new int[] {text.length(), 0, 0})
                value = (value * bases[lane] + extra) % 2147483647;
            result.append(String.format(Locale.ROOT, "%08x", value));
        }
        return result.toString();
    }
    static String merkle(List<String> hashes) {
        List<String> level = new ArrayList<>(hashes);
        while (level.size() > 1) {
            if (level.size() % 2 == 1)
                level.add(level.getLast());
            List<String> next = new ArrayList<>();
            for (int i = 0; i < level.size(); i += 2)
                next.add(digest(level.get(i) + level.get(i + 1)));
            level = next;
        }
        return level.getFirst();
    }
    static String shortId(String value) {
        return value.substring(0, 8);
    }
}
