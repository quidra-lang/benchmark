using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
public static class Scoring {
    public static readonly int RACK_SIZE = 7, BINGO_BONUS = 50;
    public record WordScore(Board.Move word, int score) {}
    public record Result(int score, List<Board.Tile> tiles, List<WordScore> words) {}
    public static List<Board.Tile> Squares(Board.Move move) {
        List<Board.Tile> result = new();
        for (int i = 0; i < move.word.Length; i++)
            result.Add(new Board.Tile(move.row + move.direction * i,
                                      move.column + (1 - move.direction) * i, move.word[i]));
        return result;
    }
    public static List<Board.Tile> Placement(char[][] board, Board.Move move) {
        List<Board.Tile> result = new();
        foreach (Board.Tile tile in Squares(move))
            if (board[tile.row][tile.column] == '.')
                result.Add(tile);
        return result;
    }
    public static char[][] Apply(char[][] board, List<Board.Tile> tiles) {
        char[][] result = new char [board.Length][];
        for (int r = 0; r < board.Length; r++)
            result[r] = board[r].ToArray();
        foreach (Board.Tile tile in tiles)
            result[tile.row][tile.column] = tile.letter;
        return result;
    }
    public static List<Board.Move> Crosses(char[][] board, Board.Move move) {
        List<Board.Tile> tiles = Placement(board, move);
        char[][] after = Apply(board, tiles);
        List<Board.Move> result = new();
        foreach (Board.Tile tile in tiles) {
            Board.Move word = Board.Run(after, tile.row, tile.column, 1 - move.direction);
            if (word.word.Length >= 2)
                result.Add(word);
        }
        return result;
    }
    public static int ComputeWordScore(char[][] board, Board.Move word, int[] values) {
        int score = 0, multiplier = 1;
        foreach (Board.Tile tile in Squares(word)) {
            char letter = tile.letter;
            int value = letter >= 'A' && letter <= 'Z' ? values[letter] : 0;
            if (board[tile.row][tile.column] == '.') {
                char premium = Board.PREMIUMS[tile.row][tile.column];
                value *= premium == '+' ? 2 : premium == '^' ? 3 : 1;
                multiplier *= premium == '*' ? 2 : premium == '#' ? 3 : 1;
            }
            score += value;
        }
        return score * multiplier;
    }
    public static Result Evaluate(char[][] board, Board.Move move, int[] values) {
        List<Board.Move> words = new();
        words.Add(move);
        words.AddRange(Crosses(board, move));
        List<WordScore> scores = new();
        int score = 0;
        foreach (Board.Move word in words) {
            int value = ComputeWordScore(board, word, values);
            score += value;
            scores.Add(new WordScore(word, value));
        }
        List<Board.Tile> tiles = Placement(board, move);
        if (tiles.Count == RACK_SIZE)
            score += BINGO_BONUS;
        return new Result(score, tiles, scores);
    }
}
