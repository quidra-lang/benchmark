import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        int[] sales = {120, 135, 98, 143, 160, 152, 171, 149, 188, 176};
        for (int i = 2; i < sales.length; i++) {
            double average = (sales[i - 2] + sales[i - 1] + sales[i]) / 3.0;
            System.out.printf(Locale.ROOT, "day %d: %.2f%n", i + 1, average);
        }
    }
}
