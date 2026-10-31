import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

record LetterKey(int length, int position, char letter) {}
final class WordIndex {
    final Map<String, Integer> scores;
    final List<String> ranked;
    final Map<Integer, List<String>> byLength = new TreeMap<>();
    final Map<LetterKey, List<String>> byLetter = new HashMap<>();
    WordIndex(Map<String, Integer> scores) {
        this.scores = scores;
        ranked = scores.keySet().stream().sorted(Comparator.<String>comparingInt(scores::get).reversed().thenComparing(Comparator.naturalOrder())).toList();
        for (String word : ranked) {
            byLength.computeIfAbsent(word.length(), ignored -> new ArrayList<>()).add(word);
            for (int position = 0; position < word.length(); position++) byLetter.computeIfAbsent(new LetterKey(word.length(), position, word.charAt(position)), ignored -> new ArrayList<>()).add(word);
        }
    }
    static boolean validWord(String text) { return text.length() >= 3 && text.length() <= 15 && text.chars().allMatch(letter -> letter >= 'A' && letter <= 'Z'); }
    static boolean validInteger(String text, int low, int high) {
        if (text.isEmpty() || text.charAt(0) == '0' || text.length() > Integer.toString(high).length()) return false;
        if (!text.chars().allMatch(letter -> letter >= '0' && letter <= '9')) return false;
        int value = Integer.parseInt(text); return value >= low && value <= high;
    }
    static String wordError(String line) {
        if (line.chars().filter(letter -> letter == ' ').count() != 1) return "bad format";
        int split = line.indexOf(' ');
        if (!validWord(line.substring(0, split))) return "bad word";
        return validInteger(line.substring(split + 1), 1, 100) ? null : "bad score";
    }
    static String clueError(String line) {
        if (line.chars().filter(letter -> letter == '|').count() != 1) return "bad format";
        int split = line.indexOf('|'); String word = line.substring(0, split), clue = line.substring(split + 1);
        if (!validWord(word)) return "bad word";
        return clue.isEmpty() || clue.length() > 60 || clue.charAt(0) == ' ' || clue.charAt(clue.length() - 1) == ' ' ? "bad clue" : null;
    }
    static boolean matches(String word, String pattern) {
        for (int position = 0; position < pattern.length(); position++) if (pattern.charAt(position) != '.' && pattern.charAt(position) != word.charAt(position)) return false;
        return true;
    }
    List<String> candidates(String pattern, int minimum, Set<String> used) {
        List<String> pool = byLength.getOrDefault(pattern.length(), List.of());
        for (int position = 0; position < pattern.length(); position++) if (pattern.charAt(position) != '.') {
            List<String> bucket = byLetter.getOrDefault(new LetterKey(pattern.length(), position, pattern.charAt(position)), List.of());
            if (bucket.size() < pool.size()) pool = bucket;
        }
        List<String> candidates = new ArrayList<>();
        for (String word : pool) { if (scores.get(word) < minimum) break; if (!used.contains(word) && matches(word, pattern)) candidates.add(word); }
        return candidates;
    }
}
