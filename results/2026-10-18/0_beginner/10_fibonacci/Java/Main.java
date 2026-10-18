import java.util.ArrayList;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        int a = 1, b = 1;
        List<Integer> terms = new ArrayList<>();
        for (int i = 0; i < 30; i++) {
            terms.add(a);
            int next = a + b;
            a = b;
            b = next;
        }
        System.out.println(String.join(" ", terms.stream().map(String::valueOf).toList()));
        System.out.println("sum: " + terms.stream().mapToInt(Integer::intValue).sum());
    }
}
