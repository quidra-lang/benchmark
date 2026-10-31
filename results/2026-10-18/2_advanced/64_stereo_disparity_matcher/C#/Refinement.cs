using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
public static class Refinement {
    public static string Hundredths(long value) {
        return value / 100 + "." + (value % 100 < 10 ? "0" : "") + value % 100;
    }
    public static string Two(long a, long b) { return Hundredths((200 * a + b) / (2 * b)); }
    public static long DepthHundredths(int disparity, long focal, long baseline) {
        return (200 * focal * baseline + disparity) / (2 * disparity);
    }
    public static string[] Subpixel(int d, long[] costs, int min, int max, long focal,
                                    long baseline) {
        int index = d - min;
        long a = 0, b = 1;
        if (min < d && d < max && costs[index - 1] > costs[index] &&
            costs[index + 1] >= costs[index]) {
            a = costs[index - 1] - costs[index + 1];
            b = 2 * (costs[index - 1] - 2 * costs[index] + costs[index + 1]);
        }
        long q = (200 * (d * b + a) + b) / (2 * b);
        return new string[] { Hundredths(q), Two(100 * focal * baseline, q) };
    }
}
