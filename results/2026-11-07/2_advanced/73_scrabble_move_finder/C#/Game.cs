using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
public static class Game {
    public static readonly string TILE_ORDER = "ABCDEFGHIJKLMNOPQRSTUVWXYZ?";
    public sealed class Minstd {
        public long state;
        public Minstd(int seed) { state = seed; }
        public int Next() {
            state = state * 48271 % 2147483647;
            return (int)state;
        }
    }
    public static void Shuffle(List<char> bag, Minstd random) {
        for (int i = bag.Count - 1; i >= 1; i--) {
            int j = random.Next() % (i + 1);
            char tile = bag[i];
            bag[i] = bag[j];
            bag[j] = tile;
        }
    }
    public static List<char> Bag(int[] counts, Minstd random) {
        List<char> result = new();
        foreach (char tile in TILE_ORDER.ToCharArray())
            for (int i = 0; i < counts[tile]; i++)
                result.Add(tile);
        Shuffle(result, random);
        return result;
    }
    public static char RemoveLast(List<char> bag) {
        char value = bag[^1];
        bag.RemoveAt(bag.Count - 1);
        return value;
    }
    public static string Draw(List<char> bag, int count) {
        StringBuilder tiles = new StringBuilder();
        while (count-- > 0 && bag.Count != 0)
            tiles.Append(RemoveLast(bag));
        return tiles.ToString();
    }
    public static string Exchange(List<char> bag, string returned, Minstd random) {
        string drawn = Draw(bag, returned.Length);
        char[] ordered = returned.ToCharArray();
        ordered.AsSpan().Sort();
        foreach (char tile in ordered)
            bag.Add(tile);
        Shuffle(bag, random);
        return drawn;
    }
    public static int Points(string collection, int[] values) {
        int result = 0;
        foreach (char tile in collection.ToCharArray())
            result += values[tile];
        return result;
    }
}
