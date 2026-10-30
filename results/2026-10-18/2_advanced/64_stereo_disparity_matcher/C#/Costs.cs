using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Costs {
    public static int Clamp(int v, int size) { return Math.Min(Math.Max(v, 0), size - 1); }
    public static int At(int[] image, int w, int h, int x, int y) {
        return image[Clamp(y, h) * w + Clamp(x, w)];
    }
    public static long[] Box(long[] image, int w, int h, int window) {
        int radius = window / 2, pw = w + 2 * radius, ph = h + 2 * radius;
        long[][] integral = Enumerable.Range(0, ph + 1)
                                .Select(
                                    _ => new long[pw + 1])
                                .ToArray();
        for (int y = 0; y < ph; y++) {
            long row = 0;
            for (int x = 0; x < pw; x++) {
                row += image[Clamp(y - radius, h) * w + Clamp(x - radius, w)];
                integral[y + 1][x + 1] = integral[y][x + 1] + row;
            }
        }
        long[] result = new long[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                result[y * w + x] = integral[y + window][x + window] - integral[y][x + window] -
                                    integral[y + window][x] + integral[y][x];
        return result;
    }
    public static int[] Census(int[] image, int w, int h) {
        int[] result = new int[image.Length];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int code = 0;
                for (int dy = -2; dy <= 2; dy++)
                    for (int dx = -2; dx <= 2; dx++)
                        if (dx != 0 || dy != 0)
                            code = (code << 1) |
                                   (At(image, w, h, x + dx, y + dy) < image[y * w + x] ? 1 : 0);
                result[y * w + x] = code;
            }
        return result;
    }
    public static long[] Texture(int[] image, int w, int h, int window) {
        long[] gradient = new long[image.Length];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++)
                gradient[y * w + x] =
                    Math.Abs(At(image, w, h, x + 1, y) - At(image, w, h, x - 1, y));
        return Box(gradient, w, h, window);
    }
    public static long[][] Volume(int[] left, int[] right, int[] cl, int[] cr, int w, int h,
                                  string kind, int window, int min, int max) {
        long[][] volume = Enumerable.Range(0, left.Length)
                              .Select(
                                  _ => new long[max - min + 1])
                              .ToArray();
        for (int d = min; d <= max; d++) {
            long[] pixels = new long[left.Length];
            for (int y = 0; y < h; y++)
                for (int x = 0; x < w; x++) {
                    int p = y * w + x, q = y * w + Math.Max(x - d, 0),
                        difference = left[p] - right[q];
                    pixels[p] = kind.Equals("census")
                                    ? System.Numerics.BitOperations.PopCount((uint)(cl[p] ^ cr[q]))
                                : kind.Equals("sad") ? Math.Abs(difference)
                                                     : difference * difference;
                }
            long[] totals = Box(pixels, w, h, window);
            for (int p = 0; p < left.Length; p++)
                volume[p][d - min] = totals[p];
        }
        return volume;
    }
}
