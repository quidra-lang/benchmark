import java.util.Arrays;
import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        int[] values = {48, 73, 56, 91, 35, 62, 84};
        System.out.printf(Locale.ROOT, "%.2f%n", Arrays.stream(values).average().orElseThrow());
    }
}
