using System;
using System.Collections.Generic;
using System.Linq;
using System.Globalization;

CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
static string Fixed(double x, int places) => Math.Round(x, places, MidpointRounding.AwayFromZero).ToString("F" + places, CultureInfo.InvariantCulture);
double[][][] systems = { new[] {new double[] {2,-1,3,7},new double[] {4,1,-2,3},new double[] {-3,5,1,-4}},
    new[] {new double[] {1,3,-2,4,6},new double[] {5,-2,1,3,-7},new double[] {-2,4,6,-1,9},new double[] {3,1,-4,2,5}} };
for (int system = 0; system < systems.Length; system++) {
    double[][] a = systems[system];
    int n = a.Length;
    for (int k = 0; k < n; k++) {
        int pivot = k;
        for (int i = k + 1; i < n; i++) {
            if (Math.Abs(a[i][k]) > Math.Abs(a[pivot][k])) pivot = i;
        }
        (a[k],a[pivot]) = (a[pivot],a[k]);
        for (int i = k + 1; i < n; i++) {
            double factor = a[i][k] / a[k][k];
            for (int j = k; j <= n; j++) a[i][j] = a[i][j] - factor * a[k][j];
        }
    }
    double[] x = new double[n];
    for (int i = n - 1; i >= 0; i--) {
        double sum = a[i][n];
        for (int j = i + 1; j < n; j++) sum = sum - a[i][j] * x[j];
        x[i] = sum / a[i][i];
    }
    Console.WriteLine($"system {system + 1}:");
    for (int i = 0; i < n; i++) Console.WriteLine($"x{i + 1} = {Fixed(x[i],4)}");
}
