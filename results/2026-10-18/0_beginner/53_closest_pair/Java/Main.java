import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        int[][] points = {{12,-7},{-33,25},{41,18},{-8,-44},{27,39},{-46,-12},{5,14},{36,-29},{-19,47},{-2,3}};
        int minimum = Integer.MAX_VALUE, maximum = -1, minI = 0, minJ = 0, maxI = 0, maxJ = 0;
        for (int i = 0; i < points.length; i++) for (int j = i + 1; j < points.length; j++) {
            int dx = points[i][0] - points[j][0], dy = points[i][1] - points[j][1], distance = dx * dx + dy * dy;
            if (distance < minimum) {
                minimum = distance;
                minI = i;
                minJ = j;
            }
            if (distance > maximum) {
                maximum = distance;
                maxI = i;
                maxJ = j;
            }
        }
        System.out.printf(Locale.ROOT, "closest: P%d P%d %.4f%n", minI, minJ, Math.sqrt(minimum));
        System.out.printf(Locale.ROOT, "farthest: P%d P%d %.4f%n", maxI, maxJ, Math.sqrt(maximum));
    }
}
