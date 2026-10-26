import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        List<String> deck = new ArrayList<>();
        for (char suit : "SHDC".toCharArray()) {
            for (char rank : "A23456789TJQK".toCharArray()) {
                deck.add("" + rank + suit);
            }
        }
        long state = 2026;
        for (int i = 51; i >= 1; i--) {
            state = state * 48271 % 2147483647;
            int j = (int)(state % (i + 1));
            Collections.swap(deck, i, j);
        }
        for (int i = 0; i < 52; i += 13) {
            System.out.println(String.join(" ", deck.subList(i, i + 13)));
        }
    }
}
