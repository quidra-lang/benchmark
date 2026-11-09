using System;
using System.Globalization;
using System.Linq;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

double[][][] systems =
[
    [[2, -1, 3, 7], [4, 1, -2, 3], [-3, 5, 1, -4]],
    [[1, 3, -2, 4, 6], [5, -2, 1, 3, -7], [-2, 4, 6, -1, 9], [3, 1, -4, 2, 5]],
];
for (int system = 0; system < systems.Length; system++)
{
    double[][] a = systems[system];
    int n = a.Length;
    for (int k = 0; k < n; k++)
    {
        int pivot = Enumerable.Range(k, n - k).MaxBy(i => Math.Abs(a[i][k]));
        (a[k], a[pivot]) = (a[pivot], a[k]);
        for (int i = k + 1; i < n; i++)
        {
            double factor = a[i][k] / a[k][k];
            for (int j = k; j <= n; j++) a[i][j] = a[i][j] - factor * a[k][j];
        }
    }
    double[] x = new double[n];
    for (int i = n - 1; i >= 0; i--)
    {
        double sum = a[i][n];
        for (int j = i + 1; j < n; j++) sum = sum - a[i][j] * x[j];
        x[i] = sum / a[i][i];
    }
    Console.WriteLine($"system {system + 1}:");
    for (int i = 0; i < n; i++) Console.WriteLine($"x{i + 1} = {x[i]:F4}");
}
