import java.util.*;
final class Scoring {
    static final int RACK_SIZE = 7, BINGO_BONUS = 50;
    record WordScore(Board.Move word, int score) {}
    record Result(int score, List<Board.Tile> tiles, List<WordScore> words) {}
    static List<Board.Tile> squares(Board.Move move) {
        List<Board.Tile> result = new ArrayList<>();
        for (int i = 0; i < move.word().length(); i++)
            result.add(new Board.Tile(move.row() + move.direction() * i,
                                      move.column() + (1 - move.direction()) * i,
                                      move.word().charAt(i)));
        return result;
    }
    static List<Board.Tile> placement(char[][] board, Board.Move move) {
        List<Board.Tile> result = new ArrayList<>();
        for (Board.Tile tile : squares(move))
            if (board[tile.row()][tile.column()] == '.')
                result.add(tile);
        return result;
    }
    static char[][] apply(char[][] board, List<Board.Tile> tiles) {
        char[][] result = new char[board.length][];
        for (int r = 0; r < board.length; r++)
            result[r] = board[r].clone();
        for (Board.Tile tile : tiles)
            result[tile.row()][tile.column()] = tile.letter();
        return result;
    }
    static List<Board.Move> crosses(char[][] board, Board.Move move) {
        List<Board.Tile> tiles = placement(board, move);
        char[][] after = apply(board, tiles);
        List<Board.Move> result = new ArrayList<>();
        for (Board.Tile tile : tiles) {
            Board.Move word = Board.run(after, tile.row(), tile.column(), 1 - move.direction());
            if (word.word().length() >= 2)
                result.add(word);
        }
        return result;
    }
    static int wordScore(char[][] board, Board.Move word, int[] values) {
        int score = 0, multiplier = 1;
        for (Board.Tile tile : squares(word)) {
            char letter = tile.letter();
            int value = letter >= 'A' && letter <= 'Z' ? values[letter] : 0;
            if (board[tile.row()][tile.column()] == '.') {
                char premium = Board.PREMIUMS[tile.row()].charAt(tile.column());
                value *= premium == '+' ? 2 : premium == '^' ? 3 : 1;
                multiplier *= premium == '*' ? 2 : premium == '#' ? 3 : 1;
            }
            score += value;
        }
        return score * multiplier;
    }
    static Result evaluate(char[][] board, Board.Move move, int[] values) {
        List<Board.Move> words = new ArrayList<>();
        words.add(move);
        words.addAll(crosses(board, move));
        List<WordScore> scores = new ArrayList<>();
        int score = 0;
        for (Board.Move word : words) {
            int value = wordScore(board, word, values);
            score += value;
            scores.add(new WordScore(word, value));
        }
        List<Board.Tile> tiles = placement(board, move);
        if (tiles.size() == RACK_SIZE)
            score += BINGO_BONUS;
        return new Result(score, tiles, scores);
    }
}
