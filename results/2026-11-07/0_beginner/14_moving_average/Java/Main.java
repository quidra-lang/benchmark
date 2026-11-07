import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        int[] sales = {120, 135, 98, 143, 160, 152, 171, 149, 188, 176};
        int window = 3;
        for (int i = window - 1; i < sales.length; i++) {
            int sum = 0;
            for (int j = i - window + 1; j <= i; j++) sum += sales[j];
            double average = (double)sum / window;
            System.out.printf(Locale.ROOT, "day %d: %.2f%n", i + 1, average);
        }
    }
}
