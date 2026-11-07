import java.util.Arrays;
import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        int[][] matrix = {
            {125, 340, 78, 912, 456},
            {603, 27, 819, 150, 384},
            {0, 765, 231, 498, 62},
            {947, 113, 586, 39, 720}};
        int[] columns = new int[5];
        for (int[] row : matrix) {
            int sum = Arrays.stream(row).sum();
            for (int j = 0; j < row.length; j++) {
                System.out.printf(Locale.ROOT, "%6d", row[j]);
                columns[j] += row[j];
            }
            System.out.printf(Locale.ROOT, "%6d%n", sum);
        }
        for (int sum : columns) {
            System.out.printf(Locale.ROOT, "%6d", sum);
        }
        System.out.printf(Locale.ROOT, "%6d%n", Arrays.stream(columns).sum());
    }
}
