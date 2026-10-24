public class Main {
    static int gcd(int a, int b) {
        while (b != 0) {
            int r = a % b;
            a = b;
            b = r;
        }
        return a;
    }
    public static void main(String[] args) {
        for (int[] pair : new int[][]{{48,180},{1071,462},{7,91},{13,97},{36288,98280}}) {
            int a = pair[0], b = pair[1], g = gcd(a, b);
            System.out.println("gcd(" + a + ", " + b + ") = " + g + ", lcm(" + a + ", " + b + ") = " + (a / g * b));
        }
    }
}
