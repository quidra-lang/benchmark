public class Main {
    public static void main(String[] args) {
        String[] numbers = {
            "688126340316", "0128469655154", "92181914514156", "177332430060552",
            "7982377590420309", "9884593615513906"};
        for (String number : numbers) {
            int sum = 0;
            for (int i = number.length() - 1, position = 1; i >= 0; i--, position++) {
                int digit = number.charAt(i) - '0';
                if (position % 2 == 0) {
                    digit *= 2;
                    if (digit > 9) {
                        digit -= 9;
                    }
                }
                sum += digit;
            }
            int expected = (10 - (sum - (number.charAt(number.length() - 1) - '0')) % 10) % 10;
            System.out.println(number + ": "
                    + (sum % 10 == 0 ? "valid" : "invalid (expected check digit " + expected + ")"));
        }
    }
}
