public class Main {
    public static void main(String[] args) {
        int factorial = 1;
        for (int n = 0; n <= 12; n++) {
            if (n > 0) factorial *= n;
            System.out.println(n + "! = " + factorial);
        }
    }
}
