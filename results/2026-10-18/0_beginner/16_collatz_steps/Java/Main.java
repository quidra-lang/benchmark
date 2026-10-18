import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        for (long start : new long[]{1,6,27,97,871}) {
            long n = start, maximum = n; int steps = 0;
            while (n != 1) { n = n % 2 == 0 ? n / 2 : 3 * n + 1; steps++; maximum = Math.max(maximum, n); }
            System.out.println(start + ": steps=" + steps + " max=" + maximum);
        }
    }
}
