public class Main {
    public static void main(String[] args) {
        int[] values = {17, -8, 42, 5, -23, 36, 5, 0, -11, 29};
        int sum = 0, maximum = values[0], minimum = values[0];
        for (int value : values) {
            sum += value;
            maximum = Math.max(maximum, value);
            minimum = Math.min(minimum, value);
        }
        System.out.println("sum: " + sum);
        System.out.println("max: " + maximum);
        System.out.println("min: " + minimum);
    }
}
