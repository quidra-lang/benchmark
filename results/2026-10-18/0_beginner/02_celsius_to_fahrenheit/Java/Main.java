import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        int[] temperatures = {-40, -15, -3, 0, 22, 37, 100};
        for (int celsius : temperatures) {
            double fahrenheit = celsius * 9.0 / 5.0 + 32;
            System.out.printf(Locale.ROOT, "%d C = %.1f F%n", celsius, fahrenheit);
        }
    }
}
