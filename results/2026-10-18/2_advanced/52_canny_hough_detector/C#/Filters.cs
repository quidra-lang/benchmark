using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Filters {
    public record Gradient(int[][] gx, int[][] gy, int[][] magnitude) {
    }
    public static int Clamped(int[][] image, int x, int y) {
        return image[Math.Min(Math.Max(y, 0), image.Length - 1)]
                    [Math.Min(Math.Max(x, 0), image[0].Length - 1)];
    }
    public static int[][] Smooth(int[][] image, PgmIo.Params settings) {
        int height = image.Length, width = image[0].Length, k = settings.Get("gauss_size"), half = k / 2;
        long[] kernel = settings.Row("gauss_kernel");
        int[][] result = Enumerable.Range(0, height)
                             .Select(
                                 _ => new int[width])
                             .ToArray();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                long sum = 0;
                for (int j = 0; j < k; j++)
                    for (int i = 0; i < k; i++)
                        sum += kernel[j * k + i] * Clamped(image, x + i - half, y + j - half);
                result[y][x] = (int)(sum / settings.Get("gauss_divisor"));
            }
        return result;
    }
    public static Gradient ComputeGradient(int[][] image) {
        int height = image.Length, width = image[0].Length;
        int[][] gx = Enumerable.Range(0, height)
                         .Select(
                             _ => new int[width])
                         .ToArray(),
                gy = Enumerable.Range(0, height)
                         .Select(
                             _ => new int[width])
                         .ToArray(),
                m = Enumerable.Range(0, height)
                        .Select(
                            _ => new int[width])
                        .ToArray();
        for (int y = 0; y < height; y++)
            for (int x = 0; x < width; x++) {
                int a = Clamped(image, x - 1, y - 1), b = Clamped(image, x, y - 1),
                    c = Clamped(image, x + 1, y - 1), d = Clamped(image, x - 1, y),
                    f = Clamped(image, x + 1, y), g = Clamped(image, x - 1, y + 1),
                    h = Clamped(image, x, y + 1), i = Clamped(image, x + 1, y + 1);
                gx[y][x] = c + 2 * f + i - (a + 2 * d + g);
                gy[y][x] = g + 2 * h + i - (a + 2 * b + c);
                m[y][x] = Math.Abs(gx[y][x]) + Math.Abs(gy[y][x]);
            }
        return new Gradient(gx, gy, m);
    }
}
