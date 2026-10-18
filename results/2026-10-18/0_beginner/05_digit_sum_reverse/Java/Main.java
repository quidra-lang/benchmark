public class Main {
    public static void main(String[] args) {
        int[] values = {7, 98000, 4096, 50301, 2718281, 123456789};
        for (int value : values) {
            int remaining = value, digits = 0, sum = 0, reversed = 0;
            while (remaining > 0) {
                int digit = remaining % 10;
                digits++;
                sum += digit;
                reversed = reversed * 10 + digit;
                remaining /= 10;
            }
            System.out.println(value + ": digits=" + digits + " sum=" + sum + " reversed=" + reversed);
        }
    }
}
