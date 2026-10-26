using System;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int[] row = { 1 };
for (int n = 0; n < 12; n++)
{
    Console.WriteLine(string.Join(" ", row));
    int[] next = new int[row.Length + 1];
    next[0] = next[^1] = 1;
    for (int k = 1; k < row.Length; k++) next[k] = row[k - 1] + row[k];
    row = next;
}
