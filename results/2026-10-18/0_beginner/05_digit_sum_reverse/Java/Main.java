public class Main {
    public static void main(String[] args) {
        int[] values = {7, 98000, 4096, 50301, 2718281, 123456789};
        for (int value : values) {
            String digits = Integer.toString(value);
            int sum = digits.chars().map(c -> c - '0').sum();
            int reversed = Integer.parseInt(new StringBuilder(digits).reverse().toString());
            System.out.println(value + ": digits=" + digits.length() + " sum=" + sum + " reversed=" + reversed);
        }
    }
}
