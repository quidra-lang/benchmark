public class Main {
    public static void main(String[] args) {
        int n = 5;
        for (int row = 1; row <= 2 * n - 1; row++) {
            int i = row <= n ? row : 2 * n - row;
            System.out.println(" ".repeat(n - i) + "*".repeat(2 * i - 1));
        }
    }
}
