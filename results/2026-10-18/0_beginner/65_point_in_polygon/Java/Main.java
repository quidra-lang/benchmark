public class Main {
    public static void main(String[] args) {
        int[][] polygon = {{1, 1}, {11, 2}, {13, 9}, {9, 7}, {7, 12}, {5, 6}, {2, 10}, {3, 5}};
        for (int[] point : new int[][]{{4, 8}, {6, 4}, {10, 8}, {7, 11}, {14, 3}, {12, 8}}) {
            int px = point[0], py = point[1];
            boolean inside = false;
            for (int i = 0; i < polygon.length; i++) {
                int[] a = polygon[i], b = polygon[(i + 1) % polygon.length];
                if ((a[1] > py) != (b[1] > py)) {
                    double intersection = a[0] + (b[0] - a[0]) * (py - a[1]) / (double)(b[1] - a[1]);
                    if (intersection > px) {
                        inside = !inside;
                    }
                }
            }
            System.out.println("(" + px + ", " + py + "): " + (inside ? "inside" : "outside"));
        }
    }
}
