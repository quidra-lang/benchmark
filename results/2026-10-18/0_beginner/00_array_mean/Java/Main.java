import java.math.BigDecimal;
import java.math.RoundingMode;

public class Main {
    public static void main(String[] args) {
        int[] values = {48, 73, 56, 91, 35, 62, 84};
        int sum = 0;
        for (int value : values) sum += value;
        double mean = (double) sum / values.length;
        System.out.println(BigDecimal.valueOf(mean).setScale(2, RoundingMode.HALF_UP).toPlainString());
    }
}
