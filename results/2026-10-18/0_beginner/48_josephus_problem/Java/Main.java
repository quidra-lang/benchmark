import java.util.ArrayList;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        for (int[] pair : new int[][]{{7, 3}, {10, 2}, {41, 3}}) {
            int n = pair[0], k = pair[1], index = 0;
            List<Integer> people = new ArrayList<>();
            List<String> removed = new ArrayList<>();
            for (int i = 1; i <= n; i++) {
                people.add(i);
            }
            while (!people.isEmpty()) {
                index = (index + k - 1) % people.size();
                removed.add(Integer.toString(people.remove(index)));
            }
            System.out.println("n=" + n + " k=" + k + ": " + String.join(" ", removed));
            System.out.println("survivor: " + removed.get(removed.size() - 1));
        }
    }
}
