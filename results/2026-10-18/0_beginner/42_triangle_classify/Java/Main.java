import java.util.Arrays;

public class Main {
    public static void main(String[] args) {
        for (int[] sides : new int[][]{{3,8,5},{6,6,6},{5,8,5},{13,5,12},{2,9,4},{7,4,7},{8,6,7},{4,9,6}}) {
            String prefix = sides[0] + " " + sides[1] + " " + sides[2] + ": ";
            int[] sorted = Arrays.stream(sides).sorted().toArray();
            int a = sorted[0], b = sorted[1], c = sorted[2];
            if (a + b <= c) {
                System.out.println(prefix + "not a triangle");
                continue;
            }
            String side = a == c ? "equilateral" : a == b || b == c ? "isosceles" : "scalene";
            int difference = c * c - a * a - b * b;
            String angle = difference < 0 ? "acute" : difference == 0 ? "right" : "obtuse";
            System.out.println(prefix + side + " " + angle);
        }
    }
}
