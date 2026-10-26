using System;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

static int Determinant(int[][] matrix)
{
    int n = matrix.Length;
    if (n == 1) return matrix[0][0];
    int result = 0;
    for (int column = 0; column < n; column++)
    {
        int[][] minor = matrix.Skip(1).Select(row => row.Where((_, c) => c != column).ToArray()).ToArray();
        int term = matrix[0][column] * Determinant(minor);
        result += column % 2 == 0 ? term : -term;
    }
    return result;
}

int[][][] matrices =
[
    [[2, -3, 1], [5, 4, -2], [-1, 6, 3]],
    [[3, 0, -2, 5], [1, 4, 7, -3], [-6, 2, 1, 8], [9, -5, 3, 2]],
    [[4, -1, 7, 0, -3], [2, 8, -5, 6, 1], [-9, 3, 2, -4, 5], [6, 0, -7, 3, -2], [1, -6, 4, 9, 8]],
];
foreach (int[][] matrix in matrices) Console.WriteLine($"det({matrix.Length}x{matrix.Length}) = {Determinant(matrix)}");
