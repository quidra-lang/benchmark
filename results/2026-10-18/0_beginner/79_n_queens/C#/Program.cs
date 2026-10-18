using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static int Queens(int[] positions, int row, int[] first, ref bool found) {
    if (row == positions.Length) {
        if (!found) Array.Copy(positions,first,positions.Length);
        found = true;
        return 1;
    }
    int count = 0;
    for (int column = 0; column < positions.Length; column++) {
        bool safe = true;
        for (int previous = 0; previous < row; previous++) {
            if (positions[previous] == column || Math.Abs(positions[previous] - column) == row - previous) {
                safe = false;
                break;
            }
        }
        if (safe) {
            positions[row] = column;
            count += Queens(positions,row + 1,first,ref found);
        }
    }
    return count;
}
int[] firstEight = new int[8];
for (int n = 4; n <= 8; n++) {
    int[] positions = new int[n], first = new int[n];
    bool found = false;
    int solutions = Queens(positions,0,first,ref found);
    Console.WriteLine($"N={n}: {solutions} solutions");
    if (n == 8) firstEight = first;
}
foreach (int column in firstEight) Console.WriteLine(new string('.',column) + "Q" + new string('.',7 - column));
