import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        for (String phrase : new String[]{"Never odd or even", "Race a car", "Was it a car or a cat I saw?", "Hello, World!", "Step on no pets.", "No lemon, no melon"}) {
            String normalized = phrase.replaceAll("[^A-Za-z]", "").toLowerCase(Locale.ROOT);
            boolean palindrome = normalized.equals(new StringBuilder(normalized).reverse().toString());
            System.out.println(phrase + " -> " + (palindrome ? "yes" : "no"));
        }
    }
}
