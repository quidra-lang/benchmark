using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
public static class Tiles {
    public record Tile(int kind, bool red);
    public const string SUITS = "mpsz", WINDS = "ESWN";
    public static readonly List<int> YAOCHUU =
        new() { 0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33 };
    public static readonly HashSet<int> GREEN = new() { 19, 20, 21, 23, 25, 32 };
    public static List<Tile> Parse(string text, bool allowEmpty = false) {
        if (text == "-")
            return allowEmpty ? new() : null;
        List<Tile> result = new();
        List<int> digits = new();
        foreach (char c in text) {
            if (c >= '0' && c <= '9')
                digits.Add(c - '0');
            else {
                int suit = SUITS.IndexOf(c);
                if (suit < 0 || digits.Count == 0)
                    return null;
                foreach (int digit in digits) {
                    if (suit == 3 && (digit < 1 || digit > 7))
                        return null;
                    result.Add(new(suit * 9 + (digit == 0 ? 5 : digit) - 1, digit == 0));
                }
                digits.Clear();
            }
        }
        return result.Count == 0 || digits.Count != 0 ? null : result;
    }
    public static string Name(int kind) => (kind % 9 + 1).ToString() + SUITS[kind / 9];
    public static string Block(List<int> kinds) {
        List<int> ordered = kinds.Order().ToList();
        return string.Concat(ordered.Select(kind => (kind % 9 + 1).ToString())) +
               SUITS[ordered[0] / 9];
    }
    public static int[] Counts(IEnumerable<Tile> tiles) {
        int[] result = new int[34];
        foreach (Tile tile in tiles)
            result[tile.kind]++;
        return result;
    }
    public static bool Honor(int kind) => kind >= 27;
    public static bool Terminal(int kind) => kind < 27 && (kind % 9 == 0 || kind % 9 == 8);
    public static bool Yaochuu(int kind) => Honor(kind) || Terminal(kind);
    public static int NextDora(int kind) => kind < 27   ? kind / 9 * 9 + (kind % 9 + 1) % 9
                                            : kind < 31 ? 27 + (kind - 26) % 4
                                                        : 31 + (kind - 30) % 3;
    public static int WindTile(string wind) => 27 + WINDS.IndexOf(wind);
    public static string
    Key(int[] counts) => new string(counts.Select(count => (char)('0' + count)).ToArray());
}
