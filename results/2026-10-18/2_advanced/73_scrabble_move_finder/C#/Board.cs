using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
public static class Board {
    public static readonly int SIZE = 15;
    public static readonly string COLUMNS = "ABCDEFGHIJKLMNO";
    public static readonly string[] PREMIUMS = {
        "#..+...#...+..#", ".*...^...^...*.", "..*...+.+...*..", "+..*...+...*..+",
        "....*.....*....", ".^...^...^...^.", "..+...+.+...+..", "#..+...*...+..#",
        "..+...+.+...+..", ".^...^...^...^.", "....*.....*....", "+..*...+...*..+",
        "..*...+.+...*..", ".*...^...^...*.", "#..+...#...+..#"
    };
    public record Move(int row, int column, int direction, string word) {}
    public record Tile(int row, int column, char letter) {}
    public record Cell(int row, int column) {}
    public static bool Inside(int r, int c) { return 0 <= r && r < SIZE && 0 <= c && c < SIZE; }
    public static string Square(int r, int c) { return "" + COLUMNS[c] + (r + 1); }
    public static string Position(Move move) {
        return move.direction == 0 ? "" + (move.row + 1) + COLUMNS[move.column]
                                   : "" + COLUMNS[move.column] + (move.row + 1);
    }
    public static Move Parse(string text, string word) {
        if (text.Matches("([1-9]|1[0-5])[A-O]"))
            return new Move(int.Parse(text.Substring(0, text.Length - 1 - (0))) - 1,
                            COLUMNS.IndexOf(text[text.Length - 1]), 0, word);
        if (text.Matches("[A-O]([1-9]|1[0-5])"))
            return new Move(int.Parse(text.Substring(1)) - 1, COLUMNS.IndexOf(text[0]), 1, word);
        return null;
    }
    public static char[][] Empty() {
        char[][] board = Enumerable.Range(0, SIZE)
                             .Select(
                                 _ => new char[SIZE])
                             .ToArray();
        foreach (char[] row in board)
            Array.Fill(row, '.');
        return board;
    }
    public static char[][] Transpose(char[][] board) {
        char[][] result = Enumerable.Range(0, SIZE)
                              .Select(
                                  _ => new char[SIZE])
                              .ToArray();
        for (int r = 0; r < SIZE; r++)
            for (int c = 0; c < SIZE; c++)
                result[r][c] = board[c][r];
        return result;
    }
    public static List<Tile> TransposeTiles(List<Tile> tiles) {
        List<Tile> result = new();
        foreach (Tile tile in tiles)
            result.Add(new Tile(tile.column, tile.row, tile.letter));
        return result;
    }
    public static List<Tile> Tiles(char[][] board) {
        List<Tile> result = new();
        for (int r = 0; r < SIZE; r++)
            for (int c = 0; c < SIZE; c++)
                if (board[r][c] != '.')
                    result.Add(new Tile(r, c, board[r][c]));
        return result;
    }
    public static List<Cell> Neighbors(int r, int c) {
        List<Cell> result = new();
        foreach ((int dr, int dc) in new[] { (-1, 0), (1, 0), (0, -1), (0, 1) })
            if (Inside(r + dr, c + dc))
                result.Add(new(r + dr, c + dc));
        return result;
    }
    public static Move Run(char[][] board, int r, int c, int direction) {
        int dr = direction, dc = 1 - direction;
        while (Inside(r - dr, c - dc) && board[r - dr][c - dc] != '.') {
            r -= dr;
            c -= dc;
        }
        int firstRow = r, firstColumn = c;
        StringBuilder word = new StringBuilder();
        while (Inside(r, c) && board[r][c] != '.') {
            word.Append(board[r][c]);
            r += dr;
            c += dc;
        }
        return new Move(firstRow, firstColumn, direction, word.ToString());
    }
    public static List<Move> Words(char[][] board) {
        List<Move> result = new();
        for (int direction = 0; direction < 2; direction++)
            for (int line = 0; line < SIZE; line++) {
                int offset = 0;
                while (offset < SIZE) {
                    int r = direction == 0 ? line : offset, c = direction == 0 ? offset : line;
                    if (board[r][c] == '.') {
                        offset++;
                        continue;
                    }
                    Move word = Run(board, r, c, direction);
                    if (word.word.Length >= 2)
                        result.Add(word);
                    offset += word.word.Length;
                }
            }
        return result;
    }
    public static bool Connected(char[][] board) {
        List<Tile> occupied = Tiles(board);
        if (occupied.Count == 0)
            return true;
        bool[][] seen = Enumerable.Range(0, SIZE)
                            .Select(
                                _ => new bool[SIZE])
                            .ToArray();
        Stack<Cell> pending = new();
        Tile first = occupied[0];
        pending.Push(new Cell(first.row, first.column));
        seen[first.row][first.column] = true;
        int count = 0;
        while (pending.Count != 0) {
            Cell cell = pending.Pop();
            count++;
            foreach (Cell next in Neighbors(cell.row, cell.column))
                if (board[next.row][next.column] != '.' && !seen[next.row][next.column]) {
                    seen[next.row][next.column] = true;
                    pending.Push(next);
                }
        }
        return count == occupied.Count;
    }
    public static List<string> Display(char[][] board) {
        List<string> result = new();
        List<string> columns = new();
        foreach (char c in COLUMNS.ToCharArray())
            columns.Add(c.ToString());
        result.Add("   " + string.Join(" ", columns));
        for (int r = 0; r < SIZE; r++) {
            List<string> cells = new();
            for (int c = 0; c < SIZE; c++)
                cells.Add(char.ToString(board[r][c] == '.' ? PREMIUMS[r][c] : board[r][c]));
            result.Add((r < 9 ? " " : "") + (r + 1) + " " + string.Join(" ", cells));
        }
        return result;
    }
}

public static class CollectionHelpers {
    public static bool Matches(this string text,
                               string pattern) => Regex.IsMatch(text, "\\A(?:" + pattern + ")\\z");
    public static string Repeat(this string text,
                                int count) => string.Concat(Enumerable.Repeat(text, count));
    public static V GetOrAdd<K, V>(this IDictionary<K, V> map, K key, Func<K, V> factory) {
        if (!map.TryGetValue(key, out V value)) {
            value = factory(key);
            map[key] = value;
        }
        return value;
    }
    public static void AddCount<K>(this IDictionary<K, int> map, K key, int amount) {
        map.TryGetValue(key, out int value);
        map[key] = value + amount;
    }
}
