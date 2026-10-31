import java.util.List;
import java.util.Set;
import java.util.TreeSet;

public class Main {
    public static void main(String[] args) {
        Set<Integer> a = new TreeSet<>(List.of(12, 5, 8, 21, 5, 17, 3, 12, 9));
        Set<Integer> b = new TreeSet<>(List.of(8, 14, 21, 6, 14, 3, 25, 6));
        Set<Integer> union = new TreeSet<>(a);
        union.addAll(b);
        Set<Integer> intersection = new TreeSet<>(a);
        intersection.retainAll(b);
        Set<Integer> difference = new TreeSet<>(a);
        difference.removeAll(b);
        Set<Integer> symmetric = new TreeSet<>(union);
        symmetric.removeAll(intersection);
        String[] labels = {"union", "intersection", "difference", "symmetric difference"};
        List<Set<Integer>> results = List.of(union, intersection, difference, symmetric);
        for (int i = 0; i < labels.length; i++) {
            System.out.println(labels[i] + ": "
                    + String.join(" ", results.get(i).stream().map(String::valueOf).toList()));
        }
    }
}
