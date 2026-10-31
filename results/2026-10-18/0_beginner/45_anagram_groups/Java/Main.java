import java.util.ArrayList;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public class Main {
    public static void main(String[] args) {
        Map<String, List<String>> groups = new LinkedHashMap<>();
        String[] words = {
            "listen", "stone", "night", "silent", "notes", "apple", "thing", "enlist", "earth",
            "onset", "heart", "tones"};
        for (String word : words) {
            char[] letters = word.toCharArray();
            Arrays.sort(letters);
            groups.computeIfAbsent(new String(letters), key -> new ArrayList<>()).add(word);
        }
        for (List<String> group : groups.values()) {
            System.out.println(String.join(" ", group));
        }
    }
}
