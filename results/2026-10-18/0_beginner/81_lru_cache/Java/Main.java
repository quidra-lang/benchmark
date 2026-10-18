import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        List<String> cache = new ArrayList<>();
        int hits = 0, misses = 0;
        for (char ch : "BACBDABEADDCAEB".toCharArray()) {
            String key = String.valueOf(ch), status;
            if (cache.remove(key)) {
                hits++;
                status = "hit";
            } else {
                misses++;
                status = "miss";
                if (cache.size() == 3) status += ", evict " + cache.removeLast();
            }
            cache.addFirst(key);
            System.out.println(key + ": " + status + " [" + String.join(" ",cache) + "]");
        }
        System.out.println("hits: " + hits + " misses: " + misses);
    }
}
