import java.util.ArrayList;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        for (int n : new int[]{84,9973,15625,1001,123456,48000,999958,999999}) {
            int remaining = n;
            List<String> factors = new ArrayList<>();
            for (int d = 2; d * d <= remaining; d++) {
                int exponent = 0;
                while (remaining % d == 0) {
                    remaining /= d;
                    exponent++;
                }
                if (exponent > 0) factors.add(d + (exponent > 1 ? "^" + exponent : ""));
            }
            if (remaining > 1) factors.add(Integer.toString(remaining));
            System.out.println(n + " = " + String.join(" * ", factors));
        }
    }
}
