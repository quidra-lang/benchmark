import java.util.*;
import java.math.*;

public class Main {

    public static void main(String[] args) {
        String[] initial = {".#......", "..#.....", "###.....", "........",
            "........", "........", ".....###", "........"};
        boolean[][] board = new boolean[8][8];
        for (int r = 0; r < 8; r++) {
            for (int c = 0; c < 8; c++) board[r][c] = initial[r].charAt(c) == '#';
        }
        for (int generation = 0; generation <= 4; generation++) {
            System.out.println("generation " + generation);
            for (boolean[] row : board) {
                StringBuilder line = new StringBuilder();
                for (boolean alive : row) line.append(alive ? '#' : '.');
                System.out.println(line);
            }
            if (generation == 4) break;
            boolean[][] next = new boolean[8][8];
            for (int r = 0; r < 8; r++) {
                for (int c = 0; c < 8; c++) {
                    int neighbors = 0;
                    for (int dr = -1; dr <= 1; dr++) {
                        for (int dc = -1; dc <= 1; dc++) {
                            if (dr == 0 && dc == 0) continue;
                            int nr = r + dr, nc = c + dc;
                            if (nr >= 0 && nr < 8 && nc >= 0 && nc < 8 && board[nr][nc]) neighbors++;
                        }
                    }
                    next[r][c] = neighbors == 3 || (board[r][c] && neighbors == 2);
                }
            }
            board = next;
        }
        int alive = 0;
        for (boolean[] row : board) {
            for (boolean cell : row) {
                if (cell) alive++;
            }
        }
        System.out.println("alive: " + alive);
    }
}
