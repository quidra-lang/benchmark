import java.util.Arrays;

public class Main {
    public static void main(String[] args) {
        int[] values = {27, 64, 13, 88, 41, 5, 72, 36};
        int swaps = 0;
        for (int p = 1; p <= 7; p++) {
            boolean changed = false;
            for (int j = 0; j <= 7 - p; j++) {
                if (values[j] > values[j + 1]) {
                    int temp = values[j];
                    values[j] = values[j + 1];
                    values[j + 1] = temp;
                    changed = true;
                    swaps++;
                }
            }
            System.out.println("pass " + p + ": "
                    + String.join(" ", Arrays.stream(values).mapToObj(String::valueOf).toList()));
            if (!changed) {
                break;
            }
        }
        System.out.println("swaps: " + swaps);
    }
}
