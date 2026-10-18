import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        int a = 1, b = 1, sum = 0;
        List<String> terms = new ArrayList<>();
        for (int i = 0; i < 30; i++) {
            terms.add(Integer.toString(a)); sum += a;
            int next = a + b; a = b; b = next;
        }
        System.out.println(String.join(" ", terms));
        System.out.println("sum: " + sum);
    }
}
