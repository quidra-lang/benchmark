import java.util.Arrays;

public class Main {
    public static void main(String[] args) {
        int[] values = {52, 17, 38, 9, 61, 38, 24, 45};
        int total = 0;
        for (int i = 1; i < values.length; i++) {
            int value = values[i], j = i - 1, shifts = 0;
            while (j >= 0 && values[j] > value) {
                values[j + 1] = values[j];
                j--;
                shifts++;
            }
            values[j + 1] = value;
            total += shifts;
            System.out.println("i=" + i + " shifts=" + shifts + ": "
                    + String.join(" ", Arrays.stream(values).mapToObj(String::valueOf).toList()));
        }
        System.out.println("total shifts: " + total);
    }
}
