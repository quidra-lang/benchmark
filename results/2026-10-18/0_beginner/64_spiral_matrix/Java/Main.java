import java.util.Locale;

public class Main {
    public static void main(String[] args) {
        int[][] matrix = new int[5][6];
        int[] dr = {0,1,0,-1}, dc = {1,0,-1,0};
        int r = 0, c = 0, direction = 0;
        for (int value = 1; value <= 30; value++) {
            matrix[r][c] = value;
            if (value == 30) break;
            int nr = r + dr[direction], nc = c + dc[direction];
            if (nr < 0 || nr >= 5 || nc < 0 || nc >= 6 || matrix[nr][nc] != 0) direction = (direction + 1) % 4;
            r += dr[direction];
            c += dc[direction];
        }
        for (int[] row : matrix) {
            for (int value : row) System.out.printf(Locale.ROOT, "%3d", value);
            System.out.println();
        }
    }
}
