import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.util.ArrayList;
import java.util.List;

record Weights(int[] mono, int[][] bi) {}

final class Scoring {
    private Scoring() {}

    static boolean letter(char c) {
        return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z';
    }

    static int value(char c) {
        return c >= 'a' ? c - 'a' : c - 'A';
    }

    static char upper(int value) {
        return (char)('A' + value);
    }

    static String letters(String text) {
        StringBuilder result = new StringBuilder();
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (letter(c)) result.append(upper(value(c)));
        }
        return result.toString();
    }

    static List<String> groups(String letters) {
        List<String> lines = new ArrayList<>();
        List<String> groups = new ArrayList<>();
        for (int i = 0; i < letters.length(); i += 5) {
            groups.add(letters.substring(i, Math.min(i + 5, letters.length())));
            if (groups.size() == 10) {
                lines.add(String.join(" ", groups));
                groups.clear();
            }
        }
        if (!groups.isEmpty()) lines.add(String.join(" ", groups));
        return lines;
    }

    static int monogram(String text, int[] weights) {
        int score = 0;
        for (int i = 0; i < text.length(); i++)
            score += weights[text.charAt(i) - 'A'];
        return score;
    }

    static int bigram(String text, int[][] weights) {
        int score = 0;
        for (int i = 1; i < text.length(); i++)
            score += weights[text.charAt(i - 1) - 'A'][text.charAt(i) - 'A'];
        return score;
    }

    static Weights read(String path) throws IOException {
        List<String> lines = Files.readAllLines(Path.of(path), StandardCharsets.US_ASCII);
        int[] mono = values(lines.get(1));
        int[][] bi = new int[26][];
        for (int i = 0; i < 26; i++) bi[i] = values(lines.get(i + 3));
        return new Weights(mono, bi);
    }

    private static int[] values(String line) {
        String[] fields = line.split(" ");
        int[] values = new int[fields.length];
        for (int i = 0; i < fields.length; i++) values[i] = Integer.parseInt(fields[i]);
        return values;
    }
}
