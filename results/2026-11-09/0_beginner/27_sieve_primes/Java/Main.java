import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        int limit = 200;
        boolean[] prime = new boolean[limit + 1];
        Arrays.fill(prime, true);
        prime[0] = prime[1] = false;
        for (int p = 2; p <= limit; p++) {
            if (prime[p]) {
                for (int m = 2 * p; m <= limit; m += p) {
                    prime[m] = false;
                }
            }
        }
        List<String> primes = new ArrayList<>();
        for (int n = 2; n <= limit; n++) {
            if (prime[n]) {
                primes.add(Integer.toString(n));
            }
        }
        System.out.println("count: " + primes.size());
        for (int i = 0; i < primes.size(); i += 10) {
            System.out.println(String.join(" ", primes.subList(i, Math.min(i + 10, primes.size()))));
        }
    }
}
