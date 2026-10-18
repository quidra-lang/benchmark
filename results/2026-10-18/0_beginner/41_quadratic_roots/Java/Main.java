import java.util.*;
import java.math.*;

public class Main {
    static String fixed(double x, int places) { return BigDecimal.valueOf(x).setScale(places, RoundingMode.HALF_UP).toPlainString(); }
    public static void main(String[] args) {
        for (int[] coefficients : new int[][]{{1,-3,-10},{-2,5,4},{3,1,-2},{4,-12,9},{1,2,5},{-2,3,-4}}) {
            int a = coefficients[0], b = coefficients[1], c = coefficients[2], d = b * b - 4 * a * c;
            String prefix = a + " " + b + " " + c + ": ";
            if (d > 0) {
                double first = (-b + Math.sqrt(d)) / (2 * a), second = (-b - Math.sqrt(d)) / (2 * a);
                System.out.println(prefix + "x1 = " + fixed(Math.max(first,second),4) + ", x2 = " + fixed(Math.min(first,second),4));
            } else if (d == 0) System.out.println(prefix + "x = " + fixed(-b / (2.0 * a),4));
            else {
                String p = fixed(-b / (2.0 * a),4), q = fixed(Math.sqrt(-d) / (2 * Math.abs(a)),4);
                System.out.println(prefix + "x = " + p + " + " + q + "i, " + p + " - " + q + "i");
            }
        }
    }
}
