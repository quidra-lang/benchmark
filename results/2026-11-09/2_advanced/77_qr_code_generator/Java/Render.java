import java.util.*;
final class Render {
    static List<String> symbolLines(int[][] symbol) {
        List<String> lines = new ArrayList<>();
        for (int[] row : symbol) {
            StringBuilder line = new StringBuilder();
            for (int value : row)
                line.append(value == 1 ? '#' : '.');
            lines.add(line.toString());
        }
        return lines;
    }
    static String pbmText(int[][] symbol, int quiet, int scale) {
        int size = symbol.length, width = (size + 2 * quiet) * scale;
        StringBuilder result = new StringBuilder("P1\n" + width + " " + width + "\n");
        for (int y = 0; y < width; y++) {
            for (int x = 0; x < width; x++) {
                int mx = x / scale - quiet, my = y / scale - quiet;
                result.append(mx >= 0 && mx < size && my >= 0 && my < size ? symbol[my][mx] : 0);
            }
            result.append('\n');
        }
        return result.toString();
    }
}
