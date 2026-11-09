import java.util.Arrays;
import java.util.Comparator;
import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        String[] words = "we planted beans and carrots in the garden behind our old house".split(" ");
        var byLength = Comparator.comparingInt(String::length);
        String longest = Arrays.stream(words).sorted(byLength.reversed()).findFirst().orElseThrow();
        String shortest = Arrays.stream(words).sorted(byLength).findFirst().orElseThrow();
        int characters = Arrays.stream(words).mapToInt(String::length).sum();
        double average = (double)characters / words.length;
        System.out.println("words: " + words.length);
        System.out.println("longest: " + longest);
        System.out.println("shortest: " + shortest);
        System.out.printf(Locale.ROOT, "average length: %.2f%n", average);
    }
}
