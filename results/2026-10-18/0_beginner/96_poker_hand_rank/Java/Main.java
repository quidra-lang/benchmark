import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class Main {
    record Hand(String text, int category, int[] sequence) {}
    static Hand evaluate(String text) {
        String[] cards = text.split(" ");
        Map<Integer,Integer> counts = new HashMap<>();
        for (String card : cards) counts.merge("23456789TJQKA".indexOf(card.charAt(0)) + 2,1,Integer::sum);
        List<Integer> ranks = new ArrayList<>(counts.keySet());
        Collections.sort(ranks);
        boolean wheel = ranks.equals(List.of(2,3,4,5,14));
        boolean straight = wheel || (ranks.size() == 5 && ranks.getLast() - ranks.getFirst() == 4);
        boolean flush = Arrays.stream(cards).allMatch(card -> card.charAt(1) == cards[0].charAt(1));
        int largest = Collections.max(counts.values());
        long pairs = counts.values().stream().filter(count -> count == 2).count();
        int category;
        if (straight && flush) category = 8;
        else if (largest == 4) category = 7;
        else if (largest == 3 && pairs == 1) category = 6;
        else if (flush) category = 5;
        else if (straight) category = 4;
        else if (largest == 3) category = 3;
        else if (pairs == 2) category = 2;
        else if (pairs == 1) category = 1;
        else category = 0;
        ranks.sort(Comparator.<Integer>comparingInt(counts::get).reversed().thenComparing(Comparator.reverseOrder()));
        if (wheel && straight) ranks = new ArrayList<>(List.of(5,4,3,2,1));
        return new Hand(text,category,ranks.stream().mapToInt(Integer::intValue).toArray());
    }
    public static void main(String[] args) {
        String[] input = {"9C 9D 5H QH 2C", "4D AH 3C 5S 2H", "KS 8S 2S JS 6S", "7H 7D KC 7S KD",
            "3H 6C 4S 2D 5C", "JD TC 4H 8C AS", "QC 6D QS 3S 6H", "9H KH 9S 8H 3D"};
        String[] categories = {"high card", "one pair", "two pair", "three of a kind", "straight",
            "flush", "full house", "four of a kind", "straight flush"};
        List<Hand> hands = new ArrayList<>();
        for (String text : input) hands.add(evaluate(text));
        hands.sort(Comparator.comparingInt(Hand::category).reversed()
                .thenComparing(Hand::sequence, (a,b) -> Arrays.compare(b, a)));
        for (int i = 0; i < hands.size(); i++) {
            Hand hand = hands.get(i);
            System.out.println((i + 1) + ". " + hand.text() + ": " + categories[hand.category()]);
        }
    }
}
