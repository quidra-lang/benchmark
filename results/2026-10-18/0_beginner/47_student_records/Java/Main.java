import java.util.*;
import java.math.*;

public class Main {
    static String fixed(double x, int places) { return BigDecimal.valueOf(x).setScale(places, RoundingMode.HALF_UP).toPlainString(); }
    public static void main(String[] args) {
        String[] names = {"Tanaka","Suzuki","Yamada","Ito","Kato","Mori"};
        int[][] scores = {{78,85,94},{88,74,82},{65,90,71},{80,79,85},{92,88,95},{70,62,78}};
        int[] totals = Arrays.stream(scores).mapToInt(row -> Arrays.stream(row).sum()).toArray();
        List<Integer> order = new ArrayList<>(); for (int i = 0; i < names.length; i++) order.add(i);
        order.sort(Comparator.<Integer>comparingInt(i -> totals[i]).reversed().thenComparing(i -> names[i]));
        int rank = 0, previous = -1;
        for (int position = 0; position < order.size(); position++) {
            int i = order.get(position); if (totals[i] != previous) rank = position + 1; previous = totals[i];
            System.out.println(rank + ". " + names[i] + " total=" + totals[i] + " average=" + fixed(totals[i] / 3.0,2));
        }
    }
}
