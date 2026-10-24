using System;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static int Determinant(int[][] matrix) {
    int n = matrix.Length;
    if (n == 1) return matrix[0][0];
    int result = 0;
    for (int column = 0; column < n; column++) {
        int[][] minor = matrix.Skip(1).Select(row => row.Where((_,c) => c != column).ToArray()).ToArray();
        int term = matrix[0][column] * Determinant(minor);
        result += column % 2 == 0 ? term : -term;
    }
    return result;
}
int[][][] matrices = { new[] { new[] {2,-3,1},new[] {5,4,-2},new[] {-1,6,3} }, new[] { new[] {3,0,-2,5},new[] {1,4,7,-3},new[] {-6,2,1,8},new[] {9,-5,3,2} }, new[] { new[] {4,-1,7,0,-3},new[] {2,8,-5,6,1},new[] {-9,3,2,-4,5},new[] {6,0,-7,3,-2},new[] {1,-6,4,9,8} } };
foreach (int[][] matrix in matrices) Console.WriteLine($"det({matrix.Length}x{matrix.Length}) = {Determinant(matrix)}");
