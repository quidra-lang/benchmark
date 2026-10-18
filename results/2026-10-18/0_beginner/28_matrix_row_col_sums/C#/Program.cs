using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

int[][] matrix = { new[] {125,340,78,912,456}, new[] {603,27,819,150,384}, new[] {0,765,231,498,62}, new[] {947,113,586,39,720} };
int[] columns = new int[5]; int total = 0;
foreach (int[] row in matrix) {
    int sum = 0;
    for (int j = 0; j < row.Length; j++) { Console.Write($"{row[j],6}"); sum += row[j]; columns[j] += row[j]; }
    Console.WriteLine($"{sum,6}"); total += sum;
}
foreach (int sum in columns) Console.Write($"{sum,6}");
Console.WriteLine($"{total,6}");
