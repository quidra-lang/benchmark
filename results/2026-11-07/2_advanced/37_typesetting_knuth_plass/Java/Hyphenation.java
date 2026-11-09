import java.util.*;
final class Hyphenation {
    final Map<String, List<Integer>> dictionary = new HashMap<>();
    final int left, right;
    Hyphenation(List<String> lines, List<String> additions, int left, int right) {
        this.left = left;
        this.right = right;
        for (String word : lines)
            register(word);
        for (String word : additions)
            register(word);
    }
    static boolean letter(char c) {
        return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z';
    }
    void register(String spelling) {
        StringBuilder word = new StringBuilder();
        List<Integer> points = new ArrayList<>();
        for (int i = 0; i < spelling.length(); i++) {
            char c = spelling.charAt(i);
            if (c == '-')
                points.add(word.length());
            else
                word.append(c);
        }
        dictionary.put(word.toString(), points);
    }
    SortedMap<Integer, Boolean> points(String word) {
        SortedMap<Integer, Boolean> points = new TreeMap<>();
        int first = 0, last = word.length();
        while (first < word.length() && !letter(word.charAt(first)))
            first++;
        while (last > first && !letter(word.charAt(last - 1)))
            last--;
        String core = word.substring(first, last);
        boolean letters = !core.isEmpty();
        for (int i = 0; i < core.length(); i++)
            if (!letter(core.charAt(i)))
                letters = false;
        if (letters)
            for (int position : dictionary.getOrDefault(core.toLowerCase(Locale.ROOT), List.of()))
                if (position >= left && core.length() - position >= right)
                    points.put(first + position, true);
        for (int i = 1; i < word.length() - 1; i++)
            if (word.charAt(i) == '-' && letter(word.charAt(i - 1)) && letter(word.charAt(i + 1)))
                points.put(i + 1, false);
        return points;
    }
}
