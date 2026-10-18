public class Main {
    public static void main(String[] args) {
        for (int i = 1; i <= 9; i++) {
            StringBuilder row = new StringBuilder();
            for (int j = 1; j <= 9; j++) {
                String product = Integer.toString(i * j);
                row.append(" ".repeat(3 - product.length())).append(product);
            }
            System.out.println(row);
        }
    }
}
