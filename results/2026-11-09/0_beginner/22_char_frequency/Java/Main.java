import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        int[] counts = new int[26];
        String sentence = "Peter Piper picked a peck of pickled peppers!";
        for (char ch : sentence.toLowerCase(Locale.ROOT).toCharArray()) {
            if (ch >= 'a' && ch <= 'z') {
                counts[ch - 'a']++;
            }
        }
        for (int i = 0; i < 26; i++) {
            if (counts[i] > 0) {
                System.out.println((char)('a' + i) + ": " + counts[i]);
            }
        }
    }
}
