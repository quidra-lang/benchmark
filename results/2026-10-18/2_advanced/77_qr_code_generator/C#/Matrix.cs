using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
public static class Matrix {
    public static readonly int DATA = 0, FUNCTION = 1, FORMAT = 2, VERSION = 3;
    public record Point(int x, int y) {}
    public record Positions(List<Point> first, List<Point> second) {}
    public record Built(int[][] symbol, int[][] areas, List<Point> order) {}
    public static Positions FormatPositions(int size) {
        List<Point> first = new(), second = new();
        for (int i = 0; i < 15; i++) {
            first.Add(i < 6    ? new Point(8, i)
                      : i == 6 ? new Point(8, 7)
                      : i == 7 ? new Point(8, 8)
                      : i == 8 ? new Point(7, 8)
                               : new Point(14 - i, 8));
            second.Add(i < 8 ? new Point(size - 1 - i, 8) : new Point(8, size - 15 + i));
        }
        return new Positions(first, second);
    }
    public static Positions VersionPositions(int size) {
        List<Point> first = new(), second = new();
        for (int i = 0; i < 18; i++) {
            first.Add(new Point(size - 11 + i % 3, i / 3));
            second.Add(new Point(i / 3, size - 11 + i % 3));
        }
        return new Positions(first, second);
    }
    public static int Remainder(int value, int divisor) {
        int degree = 31 - System.Numerics.BitOperations.LeadingZeroCount((uint)(divisor));
        while (value != 0 &&
               31 - System.Numerics.BitOperations.LeadingZeroCount((uint)(value)) >= degree)
            value ^=
                divisor << (31 - System.Numerics.BitOperations.LeadingZeroCount((uint)(value)) -
                            degree);
        return value;
    }
    public static int FormatInformation(string level, int mask) {
        int indicator = (level) switch {
            "L" => 1,
            "M" => 0,
            "Q" => 3,
            _ => 2,
        };
        int shifted = (8 * indicator + mask) << 10;
        return (shifted + Remainder(shifted, 0x537)) ^ 0x5412;
    }
    public static int VersionInformation(int version) {
        int shifted = version << 12;
        return shifted + Remainder(shifted, 0x1F25);
    }
    public static void WriteValue(int[][] symbol, List<Point> positions, int value) {
        for (int i = 0; i < positions.Count; i++) {
            Point point = positions[i];
            symbol[point.y][point.x] = (value >>> i) & 1;
        }
    }
    public static int ReadValue(int[][] symbol, List<Point> positions) {
        int value = 0;
        for (int i = 0; i < positions.Count; i++) {
            Point point = positions[i];
            value |= symbol[point.y][point.x] << i;
        }
        return value;
    }
    public static int[][] Copy(int[][] symbol) {
        int[][] result = new int [symbol.Length][];
        for (int y = 0; y < symbol.Length; y++)
            result[y] = symbol[y].ToArray();
        return result;
    }
    public static Built Build(int version, int[] alignments) {
        int size = 17 + 4 * version;
        int[][] symbol = Enumerable.Range(0, size)
                             .Select(
                                 _ => new int[size])
                             .ToArray(),
                areas = Enumerable.Range(0, size)
                            .Select(
                                _ => new int[size])
                            .ToArray();
        foreach (Point center in new List<Point> { new Point(3, 3), new Point(size - 4, 3),
                                                   new Point(3, size - 4) })
            for (int dy = -4; dy <= 4; dy++)
                for (int dx = -4; dx <= 4; dx++) {
                    int x = center.x + dx, y = center.y + dy;
                    if (x < 0 || x >= size || y < 0 || y >= size)
                        continue;
                    int distance = Math.Max(Math.Abs(dx), Math.Abs(dy));
                    symbol[y][x] = distance == 0 || distance == 1 || distance == 3 ? 1 : 0;
                    areas[y][x] = FUNCTION;
                }
        for (int i = 8; i <= size - 9; i++) {
            symbol[i][6] = symbol[6][i] = i % 2 == 0 ? 1 : 0;
            areas[i][6] = areas[6][i] = FUNCTION;
        }
        for (int yi = 0; yi < alignments.Length; yi++)
            for (int xi = 0; xi < alignments.Length; xi++) {
                if (yi == 0 && (xi == 0 || xi == alignments.Length - 1) ||
                    yi == alignments.Length - 1 && xi == 0)
                    continue;
                for (int dy = -2; dy <= 2; dy++)
                    for (int dx = -2; dx <= 2; dx++) {
                        int x = alignments[xi] + dx, y = alignments[yi] + dy;
                        symbol[y][x] = Math.Max(Math.Abs(dx), Math.Abs(dy)) != 1 ? 1 : 0;
                        areas[y][x] = FUNCTION;
                    }
            }
        symbol[size - 8][8] = 1;
        areas[size - 8][8] = FUNCTION;
        Positions format = FormatPositions(size);
        foreach (List<Point> positions in new List<List<Point>> { format.first, format.second })
            foreach (Point point in positions)
                areas[point.y][point.x] = FORMAT;
        if (version >= 7) {
            Positions information = VersionPositions(size);
            foreach (List<Point> positions in new List<List<Point>> { information.first,
                                                                      information.second }) {
                foreach (Point point in positions)
                    areas[point.y][point.x] = VERSION;
                WriteValue(symbol, positions, VersionInformation(version));
            }
        }
        return new Built(symbol, areas, ReadingOrder(areas));
    }
    public static List<Point> ReadingOrder(int[][] areas) {
        int size = areas.Length, pair = 0;
        List<Point> order = new();
        for (int right = size - 1; right >= 1; right -= 2) {
            if (right == 6)
                right = 5;
            for (int i = 0; i < size; i++) {
                int y = pair % 2 == 0 ? size - 1 - i : i;
                for (int x = right; x >= right - 1; x--)
                    if (areas[y][x] == DATA)
                        order.Add(new Point(x, y));
            }
            pair++;
        }
        return order;
    }
}
