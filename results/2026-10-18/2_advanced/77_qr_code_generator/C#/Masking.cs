using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
public static class Masking {
    public record Penalty(int n1, int n2, int n3, int n4) {
        public int Total() { return n1 + n2 + n3 + n4; }
    }
    public static bool Condition(int mask, int x, int y) {
        return (mask) switch {
            0 => (y + x) % 2 == 0,
            1 => y % 2 == 0,
            2 => x % 3 == 0,
            3 => (y + x) % 3 == 0,
            4 => (y / 2 + x / 3) % 2 == 0,
            5 => (y * x) % 2 + (y * x) % 3 == 0,
            6 => ((y * x) % 2 + (y * x) % 3) % 2 == 0,
            _ => ((y + x) % 2 + (y * x) % 3) % 2 == 0,
        };
    }
    public static int[][] Apply(int[][] symbol, List<Matrix.Point> order, int mask) {
        int[][] result = Matrix.Copy(symbol);
        foreach (Matrix.Point point in order)
            if (Condition(mask, point.x, point.y))
                result[point.y][point.x] ^= 1;
        return result;
    }
    public static Penalty Penalties(int[][] symbol) {
        int size = symbol.Length, n1 = 0, n2 = 0, n3 = 0, dark = 0;
        for (int orientation = 0; orientation < 2; orientation++)
            for (int line = 0; line < size; line++) {
                int previous = -1, run = 0, window = 0;
                for (int i = 0; i < size; i++) {
                    int value = orientation == 0 ? symbol[line][i] : symbol[i][line];
                    if (value == previous)
                        run++;
                    else {
                        if (run >= 5)
                            n1 += run - 2;
                        previous = value;
                        run = 1;
                    }
                    window = ((window << 1) | value) & 2047;
                    if (i >= 10 && (window == 0b10111010000 || window == 0b00001011101))
                        n3 += 40;
                }
                if (run >= 5)
                    n1 += run - 2;
            }
        for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++) {
                dark += symbol[y][x];
                if (y + 1 < size && x + 1 < size && symbol[y][x] == symbol[y + 1][x] &&
                    symbol[y][x] == symbol[y][x + 1] && symbol[y][x] == symbol[y + 1][x + 1])
                    n2 += 3;
            }
        return new Penalty(n1, n2, n3,
                           10 * (Math.Abs(20 * dark - 10 * size * size) / (size * size)));
    }
}
