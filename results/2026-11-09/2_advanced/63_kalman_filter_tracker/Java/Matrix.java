import java.util.*;
final class Matrix {
    static double total(double[] values) {
        double result = 0;
        for (double value : values)
            result += value;
        return result;
    }
    static double[][] diagonal(double[] values) {
        double[][] result = new double[values.length][values.length];
        for (int i = 0; i < values.length; i++)
            result[i][i] = values[i];
        return result;
    }
    static double[][] identity(int n) {
        double[] values = new double[n];
        Arrays.fill(values, 1);
        return diagonal(values);
    }
    static double[][] transpose(double[][] a) {
        double[][] result = new double[a[0].length][a.length];
        for (int i = 0; i < a.length; i++)
            for (int k = 0; k < a[0].length; k++)
                result[k][i] = a[i][k];
        return result;
    }
    static double[][] add(double[][] a, double[][] b) {
        double[][] c = new double[a.length][a[0].length];
        for (int i = 0; i < a.length; i++)
            for (int k = 0; k < a[0].length; k++)
                c[i][k] = a[i][k] + b[i][k];
        return c;
    }
    static double[][] subtract(double[][] a, double[][] b) {
        double[][] c = new double[a.length][a[0].length];
        for (int i = 0; i < a.length; i++)
            for (int k = 0; k < a[0].length; k++)
                c[i][k] = a[i][k] - b[i][k];
        return c;
    }
    static double[] add(double[] a, double[] b) {
        double[] c = new double[a.length];
        for (int i = 0; i < a.length; i++)
            c[i] = a[i] + b[i];
        return c;
    }
    static double[] subtract(double[] a, double[] b) {
        double[] c = new double[a.length];
        for (int i = 0; i < a.length; i++)
            c[i] = a[i] - b[i];
        return c;
    }
    static double[][] product(double[][] a, double[][] b) {
        double[][] c = new double[a.length][b[0].length];
        for (int i = 0; i < a.length; i++)
            for (int j = 0; j < b[0].length; j++)
                for (int k = 0; k < b.length; k++)
                    c[i][j] += a[i][k] * b[k][j];
        return c;
    }
    static double[] product(double[][] a, double[] b) {
        double[] c = new double[a.length];
        for (int i = 0; i < a.length; i++)
            for (int k = 0; k < b.length; k++)
                c[i] += a[i][k] * b[k];
        return c;
    }
    static double[][] inverse(double[][] a) {
        int n = a.length;
        double[][] x = new double[n][2 * n];
        for (int i = 0; i < n; i++) {
            System.arraycopy(a[i], 0, x[i], 0, n);
            x[i][n + i] = 1;
        }
        for (int c = 0; c < n; c++) {
            double p = x[c][c];
            for (int j = 0; j < 2 * n; j++)
                x[c][j] /= p;
            for (int i = 0; i < n; i++)
                if (i != c) {
                    double f = x[i][c];
                    for (int j = 0; j < 2 * n; j++)
                        x[i][j] -= f * x[c][j];
                }
        }
        double[][] result = new double[n][n];
        for (int i = 0; i < n; i++)
            System.arraycopy(x[i], n, result[i], 0, n);
        return result;
    }
    static double determinant2(double[][] a) {
        return a[0][0] * a[1][1] - a[0][1] * a[1][0];
    }
    static double quadratic2(double[] u, double[][] a) {
        return u[0] * (a[0][0] * u[0] + a[0][1] * u[1]) + u[1] * (a[1][0] * u[0] + a[1][1] * u[1]);
    }
}
