using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int[][] arrays = { new[] {3,-5,8,-2,6,-9,4,1,-7,5,-3,2}, new[] {-4,7,-1,3,-8,10,-2,5,-6,-2,9,-12,4,-1}, new[] {-6,-3,5,-1,-4,3,-9,2,3,-1,4,-5,1,6,-2} };
foreach (int[] values in arrays) {
    int current = values[0], best = current, start = 0, bestStart = 0, bestEnd = 0;
    for (int i = 1; i < values.Length; i++) {
        if (current < 0) {
            current = values[i];
            start = i;
        } else current += values[i];
        if (current > best) {
            best = current;
            bestStart = start;
            bestEnd = i;
        }
    }
    Console.WriteLine($"max sum {best} at [{bestStart}, {bestEnd}]");
}
