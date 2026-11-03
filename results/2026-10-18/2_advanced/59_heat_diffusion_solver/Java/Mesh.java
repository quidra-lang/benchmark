import java.nio.file.*;
import java.util.*;

final class Mesh {
    record FaceRef(int point, int direction) {}
    int width, height, count;
    double dx, thickness;
    char[] codes;
    int[][] neighbors;
    Mesh() throws Exception {
        List<String> lines = Files.readAllLines(Path.of("input/plate.txt"));
        String[] w = lines.get(0).split(" ");
        width = Integer.parseInt(w[0]);
        height = Integer.parseInt(w[1]);
        dx = Double.parseDouble(w[2]);
        thickness = Double.parseDouble(w[3]);
        count = width * height;
        codes = new char[count];
        neighbors = new int[count][4];
        for (int r = 0; r < height; r++)
            for (int c = 0; c < width; c++) {
                int p = cell(r, c);
                codes[p] = lines.get(r + 1).charAt(c);
                neighbors[p] = new int[] {c > 0 ? p - 1 : -1, c + 1 < width ? p + 1 : -1,
                                          r > 0 ? p - width : -1, r + 1 < height ? p + width : -1};
            }
    }
    int cell(int row, int column) {
        return row * width + column;
    }
    String coordinates(int p) {
        return p / width + " " + p % width;
    }
    List<FaceRef> segment(String edge, int start, int end) {
        List<FaceRef> faces = new ArrayList<>();
        int direction = edge.equals("left") ? 0 : edge.equals("right") ? 1 : edge.equals("top") ? 2 : 3;
        for (int i = start; i <= end; i++) {
            int p = direction == 0   ? cell(i, 0)
                    : direction == 1 ? cell(i, width - 1)
                    : direction == 2 ? cell(0, i)
                                     : cell(height - 1, i);
            faces.add(new FaceRef(p, direction));
        }
        return faces;
    }
    List<Integer> source(int r1, int c1, int r2, int c2) {
        List<Integer> cells = new ArrayList<>();
        for (int r = r1; r <= r2; r++)
            for (int c = c1; c <= c2; c++)
                cells.add(cell(r, c));
        return cells;
    }
}
