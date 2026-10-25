import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.stream.Collectors;

final class Clues {
    static boolean isLine(String text) { return !text.isEmpty() && text.chars().allMatch(c -> c == ' ' || c >= '0' && c <= '9'); }
    static int[] parse(String text) {
        if (text.equals("0")) return new int[0]; String[] tokens = text.split(" ",-1);
        for (String token : tokens) if (token.isEmpty() || token.length() > 2 || token.charAt(0) == '0' || !token.chars().allMatch(c -> c >= '0' && c <= '9')) return null; return Arrays.stream(tokens).mapToInt(Integer::parseInt).toArray();
    }
    static int[] run(char[] cells) {
        List<Integer> clue = new ArrayList<>(); int run = 0; for (char state : cells) { if (state == LineSolver.FILLED) run++; else if (run > 0) { clue.add(run); run = 0; } } if (run > 0) clue.add(run); return clue.stream().mapToInt(Integer::intValue).toArray();
    }
    static String text(int[] clue) { return text(clue," "); }
    static String text(int[] clue, String separator) { return clue.length == 0 ? "0" : Arrays.stream(clue).mapToObj(Integer::toString).collect(Collectors.joining(separator)); }
    static int span(int[] clue) { return Arrays.stream(clue).sum() + clue.length - 1; }
    static boolean equal(List<int[]> a, List<int[]> b) { if (a.size() != b.size()) return false; for (int i = 0; i < a.size(); i++) if (!Arrays.equals(a.get(i),b.get(i))) return false; return true; }
}
