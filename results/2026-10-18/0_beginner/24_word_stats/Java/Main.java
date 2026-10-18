import java.util.*;
import java.math.*;

public class Main {
    static String fixed(double x, int places) { return BigDecimal.valueOf(x).setScale(places, RoundingMode.HALF_UP).toPlainString(); }
    public static void main(String[] args) {
        String[] words = "we planted beans and carrots in the garden behind our old house".split(" ");
        String longest = words[0], shortest = words[0]; int total = 0;
        for (String word : words) {
            if (word.length() > longest.length()) longest = word;
            if (word.length() < shortest.length()) shortest = word;
            total += word.length();
        }
        System.out.println("words: " + words.length);
        System.out.println("longest: " + longest);
        System.out.println("shortest: " + shortest);
        System.out.println("average length: " + fixed((double)total / words.length, 2));
    }
}
