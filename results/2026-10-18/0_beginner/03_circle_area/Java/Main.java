import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        int[] radii = {3, 7, 12, 25, 41};
        double pi = 3.141592653589793;
        for (int radius : radii) {
            double area = pi * radius * radius;
            double circumference = 2 * pi * radius;
            System.out.printf(Locale.ROOT, "r=%d area=%.3f circumference=%.3f%n", radius, area, circumference);
        }
    }
}
