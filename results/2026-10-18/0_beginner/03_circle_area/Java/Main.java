import java.math.BigDecimal;
import java.math.RoundingMode;

public class Main {
    private static String fixed(double value) {
        return BigDecimal.valueOf(value).setScale(3, RoundingMode.HALF_UP).toPlainString();
    }

    public static void main(String[] args) {
        int[] radii = {3, 7, 12, 25, 41};
        double pi = 3.141592653589793;
        for (int radius : radii) {
            double area = pi * radius * radius;
            double circumference = 2 * pi * radius;
            System.out.println("r=" + radius + " area=" + fixed(area) + " circumference=" + fixed(circumference));
        }
    }
}
