using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
public static class MoveGenerator {
    public static readonly string LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    public static bool[][] Anchors(char[][] board) {
        bool[][] result = Enumerable.Range(0, 15)
                              .Select(
                                  _ => new bool[15])
                              .ToArray();
        if (Board.Tiles(board).Count == 0) {
            result[7][7] = true;
            return result;
        }
        for (int r = 0; r < 15; r++)
            for (int c = 0; c < 15; c++)
                if (board[r][c] == '.')
                    foreach (Board.Cell neighbor in Board.Neighbors(r, c))
                        if (board[neighbor.row][neighbor.column] != '.')
                            result[r][c] = true;
        return result;
    }
    public static int[][] Checks(char[][] board, DictionaryTrie trie) {
        int[][] result = Enumerable.Range(0, 15)
                             .Select(
                                 _ => new int[15])
                             .ToArray();
        foreach (int[] row in result)
            Array.Fill(row, -1);
        for (int r = 0; r < 15; r++)
            for (int c = 0; c < 15; c++)
                if (board[r][c] == '.') {
                    int first = r, last = r;
                    while (first > 0 && board[first - 1][c] != '.')
                        first--;
                    while (last + 1 < 15 && board[last + 1][c] != '.')
                        last++;
                    if (first == last)
                        continue;
                    StringBuilder prefix = new StringBuilder(), suffix = new StringBuilder();
                    for (int i = first; i < r; i++)
                        prefix.Append(char.ToUpperInvariant(board[i][c]));
                    for (int i = r + 1; i <= last; i++)
                        suffix.Append(char.ToUpperInvariant(board[i][c]));
                    int mask = 0;
                    for (int i = 0; i < 26; i++)
                        if (trie.Contains(prefix.ToString() + (char)('A' + i) + suffix))
                            mask |= 1 << i;
                    result[r][c] = mask;
                }
        return result;
    }
    public sealed class Search {
        public char[][] board;
        public DictionaryTrie trie;
        public bool[][] anchors;
        public int[][] checks;
        public int[] counts = new int[128];
        public List<Board.Move> result = new();
        public int row, anchor;
        public Search(char[][] board, string rack, DictionaryTrie trie, bool[][] anchors,
                      int[][] checks) {
            this.board = board;
            this.trie = trie;
            this.anchors = anchors;
            this.checks = checks;
            foreach (char c in rack.ToCharArray())
                counts[c]++;
        }
        public void Extend(DictionaryTrie.Node node, int column, string word, int start) {
            bool empty = column == 15 || board[row][column] == '.';
            if (empty && column > anchor && node.terminal)
                result.Add(new Board.Move(row, start, 0, word));
            if (column == 15)
                return;
            if (!empty) {
                char letter = board[row][column];
                DictionaryTrie.Node child = node.children[char.ToUpperInvariant(letter) - 'A'];
                if (child != null)
                    Extend(child, column + 1, word + letter, start);
                return;
            }
            for (int i = 0; i < 26; i++)
                if (node.children[i] != null &&
                    (checks[row][column] == -1 || (checks[row][column] & (1 << i)) != 0)) {
                    char letter = (char)('A' + i);
                    for (int blank = 0; blank < 2; blank++) {
                        char tile = blank == 0 ? letter : '?',
                             written = blank == 0 ? letter : char.ToLowerInvariant(letter);
                        if (counts[tile] > 0) {
                            counts[tile]--;
                            Extend(node.children[i], column + 1, word + written, start);
                            counts[tile]++;
                        }
                    }
                }
        }
        public void Left(DictionaryTrie.Node node, string prefix, int remaining) {
            Extend(node, anchor, prefix, anchor - prefix.Length);
            if (remaining == 0)
                return;
            for (int i = 0; i < 26; i++)
                if (node.children[i] != null) {
                    char letter = (char)('A' + i);
                    for (int blank = 0; blank < 2; blank++) {
                        char tile = blank == 0 ? letter : '?',
                             written = blank == 0 ? letter : char.ToLowerInvariant(letter);
                        if (counts[tile] > 0) {
                            counts[tile]--;
                            Left(node.children[i], prefix + written, remaining - 1);
                            counts[tile]++;
                        }
                    }
                }
        }
        public List<Board.Move> Generate() {
            for (row = 0; row < 15; row++)
                for (anchor = 0; anchor < 15; anchor++)
                    if (anchors[row][anchor]) {
                        if (anchor > 0 && board[row][anchor - 1] != '.') {
                            int first = anchor - 1;
                            while (first > 0 && board[row][first - 1] != '.')
                                first--;
                            string prefix = new string(board[row], first, anchor - first);
                            DictionaryTrie.Node node = trie.Prefix(prefix.ToUpperInvariant());
                            if (node != null)
                                Extend(node, anchor, prefix, first);
                        } else {
                            int first = anchor - 1;
                            while (first >= 0 && board[row][first] == '.' && !anchors[row][first])
                                first--;
                            Left(trie.root, "", anchor - first - 1);
                        }
                    }
            return result;
        }
    }
    public static List<Board.Move> Generate(char[][] board, string rack, DictionaryTrie trie) {
        bool[][] anchors = Anchors(board);
        List<Board.Move> across =
            new Search(board, rack, trie, anchors, Checks(board, trie)).Generate();
        char[][] transposed = Board.Transpose(board);
        bool[][] downAnchors = Enumerable.Range(0, 15)
                                   .Select(
                                       _ => new bool[15])
                                   .ToArray();
        for (int r = 0; r < 15; r++)
            for (int c = 0; c < 15; c++)
                downAnchors[r][c] = anchors[c][r];
        List<Board.Move> down =
            new Search(transposed, rack, trie, downAnchors, Checks(transposed, trie)).Generate();
        foreach (Board.Move move in down)
            across.Add(new Board.Move(move.column, move.row, 1, move.word));
        Dictionary<string, Board.Move> distinct = new(StringComparer.Ordinal);
        foreach (Board.Move move in across) {
            List<Board.Tile> tiles = Scoring.Placement(board, move);
            if (tiles.Count == 1 && move.direction == 1) {
                Board.Tile tile = tiles[0];
                if (Board.Run(Scoring.Apply(board, tiles), tile.row, tile.column, 0).word.Length >=
                    2)
                    continue;
            }
            tiles.Sort((a, b) => {
                int c = a.row.CompareTo(b.row);
                return c != 0 ? c : a.column.CompareTo(b.column);
            });
            distinct[string.Join(";", tiles.Select(tile => tile.row + "," + tile.column + "," +
                                                           tile.letter))] = move;
        }
        return new(distinct.Values);
    }
}
