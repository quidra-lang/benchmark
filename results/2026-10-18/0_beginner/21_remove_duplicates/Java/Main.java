import java.util.LinkedHashSet;
import java.util.Set;

public class Main {
    public static void main(String[] args) {
        int[] values = {12,5,12,8,3,5,20,8,8,15,3,7,20,12,9};
        Set<Integer> unique = new LinkedHashSet<>();
        for (int n : values) unique.add(n);
        System.out.println(String.join(" ", unique.stream().map(String::valueOf).toList()));
        System.out.println("removed: " + (values.length - unique.size()));
    }
}
