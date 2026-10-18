import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        Map<String,List<String>> groups = new LinkedHashMap<>();
        for (String word : new String[]{"listen","stone","night","silent","notes","apple","thing","enlist","earth","onset","heart","tones"}) { char[] letters = word.toCharArray(); Arrays.sort(letters); groups.computeIfAbsent(new String(letters), key -> new ArrayList<>()).add(word); }
        for (List<String> group : groups.values()) System.out.println(String.join(" ", group));
    }
}
