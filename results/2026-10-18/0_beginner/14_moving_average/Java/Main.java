import java.util.*;
import java.math.*;

public class Main {
    static String fixed(double x, int places) { return BigDecimal.valueOf(x).setScale(places, RoundingMode.HALF_UP).toPlainString(); }
    public static void main(String[] args) {
        int[] sales = {120, 135, 98, 143, 160, 152, 171, 149, 188, 176};
        for (int i = 2; i < sales.length; i++) {
            double average = (sales[i - 2] + sales[i - 1] + sales[i]) / 3.0;
            System.out.println("day " + (i + 1) + ": " + fixed(average, 2));
        }
    }
}
