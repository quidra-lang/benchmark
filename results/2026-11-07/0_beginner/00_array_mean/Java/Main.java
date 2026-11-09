import java.util.Arrays;
import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        int[] values = {48, 73, 56, 91, 35, 62, 84};
        double mean = Arrays.stream(values).average().orElseThrow();
        System.out.printf(Locale.ROOT, "%.2f%n", mean);
    }
}
