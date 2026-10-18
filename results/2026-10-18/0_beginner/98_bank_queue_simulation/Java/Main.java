import java.util.*;
import java.math.*;

public class Main {
    static String fixed(double x, int places) { return BigDecimal.valueOf(x).setScale(places, RoundingMode.HALF_UP).toPlainString(); }
    public static void main(String[] args) {
        long state = 42;
        int[] free = {0,0};
        int arrival = 0, totalWait = 0, maxWait = 0;
        for (int customer = 1; customer <= 20; customer++) {
            state = state * 48271 % 2147483647;
            arrival += (int)(state % 5) + 1;
            state = state * 48271 % 2147483647;
            int service = (int)(state % 7) + 2;
            int teller = free[0] <= free[1] ? 0 : 1;
            int start = Math.max(arrival,free[teller]), end = start + service, wait = start - arrival;
            free[teller] = end;
            totalWait += wait;
            maxWait = Math.max(maxWait,wait);
            System.out.println("customer " + customer + ": arrive=" + arrival + " start=" + start + " end=" + end +
                " teller=" + (teller + 1) + " wait=" + wait);
        }
        System.out.println("average wait: " + fixed(totalWait / 20.0,2));
        System.out.println("max wait: " + maxWait);
        System.out.println("last departure: " + Math.max(free[0],free[1]));
    }
}
