import java.util.*;
final class Board {
    static final int SIZE = 15;
    static final String COLUMNS = "ABCDEFGHIJKLMNO";
    static final String[] PREMIUMS = {"#..+...#...+..#", ".*...^...^...*.", "..*...+.+...*..",
                                      "+..*...+...*..+", "....*.....*....", ".^...^...^...^.",
                                      "..+...+.+...+..", "#..+...*...+..#", "..+...+.+...+..",
                                      ".^...^...^...^.", "....*.....*....", "+..*...+...*..+",
                                      "..*...+.+...*..", ".*...^...^...*.", "#..+...#...+..#"};
    record Move(int row, int column, int direction, String word) {}
    record Tile(int row, int column, char letter) {}
    record Cell(int row, int column) {}
    static boolean inside(int r, int c) { return 0 <= r && r < SIZE && 0 <= c && c < SIZE; }
    static String square(int r, int c) { return "" + COLUMNS.charAt(c) + (r + 1); }
    static String position(Move move) {
        return move.direction() == 0 ? "" + (move.row() + 1) + COLUMNS.charAt(move.column())
                                     : "" + COLUMNS.charAt(move.column()) + (move.row() + 1);
    }
    static Move parse(String text, String word) {
        if (text.matches("([1-9]|1[0-5])[A-O]"))
            return new Move(Integer.parseInt(text.substring(0, text.length() - 1)) - 1,
                            COLUMNS.indexOf(text.charAt(text.length() - 1)), 0, word);
        if (text.matches("[A-O]([1-9]|1[0-5])"))
            return new Move(Integer.parseInt(text.substring(1)) - 1,
                            COLUMNS.indexOf(text.charAt(0)), 1, word);
        return null;
    }
    static char[][] empty() {
        char[][] board = new char[SIZE][SIZE];
        for (char[] row : board)
            Arrays.fill(row, '.');
        return board;
    }
    static char[][] transpose(char[][] board) {
        char[][] result = new char[SIZE][SIZE];
        for (int r = 0; r < SIZE; r++)
            for (int c = 0; c < SIZE; c++)
                result[r][c] = board[c][r];
        return result;
    }
    static List<Tile> transposeTiles(List<Tile> tiles) {
        List<Tile> result = new ArrayList<>();
        for (Tile tile : tiles)
            result.add(new Tile(tile.column(), tile.row(), tile.letter()));
        return result;
    }
    static List<Tile> tiles(char[][] board) {
        List<Tile> result = new ArrayList<>();
        for (int r = 0; r < SIZE; r++)
            for (int c = 0; c < SIZE; c++)
                if (board[r][c] != '.')
                    result.add(new Tile(r, c, board[r][c]));
        return result;
    }
    static List<Cell> neighbors(int r, int c) {
        List<Cell> result = new ArrayList<>();
        for (int[] delta : new int[][] {{-1, 0}, {1, 0}, {0, -1}, {0, 1}})
            if (inside(r + delta[0], c + delta[1]))
                result.add(new Cell(r + delta[0], c + delta[1]));
        return result;
    }
    static Move run(char[][] board, int r, int c, int direction) {
        int dr = direction, dc = 1 - direction;
        while (inside(r - dr, c - dc) && board[r - dr][c - dc] != '.') {
            r -= dr;
            c -= dc;
        }
        int firstRow = r, firstColumn = c;
        StringBuilder word = new StringBuilder();
        while (inside(r, c) && board[r][c] != '.') {
            word.append(board[r][c]);
            r += dr;
            c += dc;
        }
        return new Move(firstRow, firstColumn, direction, word.toString());
    }
    static List<Move> words(char[][] board) {
        List<Move> result = new ArrayList<>();
        for (int direction = 0; direction < 2; direction++)
            for (int line = 0; line < SIZE; line++) {
                int offset = 0;
                while (offset < SIZE) {
                    int r = direction == 0 ? line : offset, c = direction == 0 ? offset : line;
                    if (board[r][c] == '.') {
                        offset++;
                        continue;
                    }
                    Move word = run(board, r, c, direction);
                    if (word.word().length() >= 2)
                        result.add(word);
                    offset += word.word().length();
                }
            }
        return result;
    }
    static boolean connected(char[][] board) {
        List<Tile> occupied = tiles(board);
        if (occupied.isEmpty())
            return true;
        boolean[][] seen = new boolean[SIZE][SIZE];
        Deque<Cell> pending = new ArrayDeque<>();
        Tile first = occupied.getFirst();
        pending.add(new Cell(first.row(), first.column()));
        seen[first.row()][first.column()] = true;
        int count = 0;
        while (!pending.isEmpty()) {
            Cell cell = pending.removeLast();
            count++;
            for (Cell next : neighbors(cell.row(), cell.column()))
                if (board[next.row()][next.column()] != '.' && !seen[next.row()][next.column()]) {
                    seen[next.row()][next.column()] = true;
                    pending.add(next);
                }
        }
        return count == occupied.size();
    }
    static List<String> display(char[][] board) {
        List<String> result = new ArrayList<>();
        List<String> columns = new ArrayList<>();
        for (char c : COLUMNS.toCharArray())
            columns.add(Character.toString(c));
        result.add("   " + String.join(" ", columns));
        for (int r = 0; r < SIZE; r++) {
            List<String> cells = new ArrayList<>();
            for (int c = 0; c < SIZE; c++)
                cells.add(
                    Character.toString(board[r][c] == '.' ? PREMIUMS[r].charAt(c) : board[r][c]));
            result.add((r < 9 ? " " : "") + (r + 1) + " " + String.join(" ", cells));
        }
        return result;
    }
}
