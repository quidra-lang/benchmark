import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public class Main {
    public static void main(String[] args) {
        String text = "The cat sat on the mat. The dog sat on the rug, and the cat watched the dog. A bird sang on the fence, and the Dog barked at the bird. The cat slept in the sun, the bird flew away, and the dog sat by the door.";
        Map<String, Integer> counts = new HashMap<>();
        for (String word : text.toLowerCase(Locale.ROOT).split("[^a-z]+")) {
            if (!word.isEmpty()) {
                counts.merge(word, 1, Integer::sum);
            }
        }
        List<String> words = new ArrayList<>(counts.keySet());
        words.sort(Comparator.<String>comparingInt(counts::get).reversed().thenComparing(Comparator.naturalOrder()));
        for (String word : words.subList(0, 5)) {
            System.out.println(word + ": " + counts.get(word));
        }
        System.out.println("distinct words: " + counts.size());
    }
}
