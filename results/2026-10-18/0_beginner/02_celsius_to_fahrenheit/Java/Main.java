import java.math.BigDecimal;
import java.math.RoundingMode;

public class Main {
    public static void main(String[] args) {
        int[] temperatures = {-40, -15, -3, 0, 22, 37, 100};
        for (int celsius : temperatures) {
            double fahrenheit = celsius * 9.0 / 5.0 + 32;
            String formatted = BigDecimal.valueOf(fahrenheit).setScale(1, RoundingMode.HALF_UP).toPlainString();
            System.out.println(celsius + " C = " + formatted + " F");
        }
    }
}
