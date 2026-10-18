import java.util.Arrays;

public class Main {
    static boolean solve(int[][] board, long[] placements) {
        for (int r = 0; r < 9; r++) {
            for (int c = 0; c < 9; c++) {
                if (board[r][c] != 0) continue;
                for (int digit = 1; digit <= 9; digit++) {
                    boolean valid = true;
                    for (int i = 0; i < 9; i++) {
                        if (board[r][i] == digit || board[i][c] == digit ||
                            board[r / 3 * 3 + i / 3][c / 3 * 3 + i % 3] == digit) valid = false;
                    }
                    if (!valid) continue;
                    board[r][c] = digit;
                    placements[0]++;
                    if (solve(board,placements)) return true;
                    board[r][c] = 0;
                }
                return false;
            }
        }
        return true;
    }
    public static void main(String[] args) {
        String[] rows = {"800025000", "070080005", "260400070", "000001900", "010000040",
            "600200000", "900010000", "700000004", "020000036"};
        int[][] board = Arrays.stream(rows).map(row -> row.chars().map(ch -> ch - '0').toArray()).toArray(int[][]::new);
        long[] placements = {0};
        solve(board,placements);
        for (int[] row : board) System.out.println(String.join(" ",Arrays.stream(row).mapToObj(String::valueOf).toList()));
        System.out.println("placements: " + placements[0]);
    }
}
