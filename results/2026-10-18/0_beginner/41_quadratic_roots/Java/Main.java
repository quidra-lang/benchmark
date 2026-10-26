import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        int[][] equations = {
            {1, -3, -10}, {-2, 5, 4}, {3, 1, -2}, {4, -12, 9}, {1, 2, 5}, {-2, 3, -4}};
        for (int[] coefficients : equations) {
            int a = coefficients[0], b = coefficients[1], c = coefficients[2], d = b * b - 4 * a * c;
            String prefix = a + " " + b + " " + c + ": ";
            if (d > 0) {
                double first = (-b + Math.sqrt(d)) / (2 * a), second = (-b - Math.sqrt(d)) / (2 * a);
                System.out.printf(Locale.ROOT, prefix + "x1 = %.4f, x2 = %.4f%n",
                        Math.max(first, second), Math.min(first, second));
            } else if (d == 0) {
                System.out.printf(Locale.ROOT, prefix + "x = %.4f%n", -b / (2.0 * a));
            } else {
                double p = -b / (2.0 * a), q = Math.sqrt(-d) / (2 * Math.abs(a));
                System.out.printf(Locale.ROOT, prefix + "x = %.4f + %.4fi, %.4f - %.4fi%n", p, q, p, q);
            }
        }
    }
}
