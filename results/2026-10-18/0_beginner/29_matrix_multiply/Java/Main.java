import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        int[][] a = {{3, -2, 5, 1}, {-4, 7, 0, 6}, {2, 9, -8, -3}};
        int[][] b = {{1, 4}, {-5, 2}, {6, -1}, {0, 7}};
        for (int i = 0; i < 3; i++) {
            for (int j = 0; j < 2; j++) {
                int sum = 0;
                for (int k = 0; k < 4; k++) {
                    sum += a[i][k] * b[k][j];
                }
                System.out.printf(Locale.ROOT, "%5d", sum);
            }
            System.out.println();
        }
    }
}
