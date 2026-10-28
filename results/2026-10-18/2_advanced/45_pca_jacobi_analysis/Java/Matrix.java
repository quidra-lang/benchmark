import java.util.*;

final class Matrix {
    static double[][] identity(int n) {
        double[][] a = new double[n][n];
        for (int i = 0; i < n; i++)
            a[i][i] = 1;
        return a;
    }
    static double[][] copy(double[][] a) {
        double[][] result = new double[a.length][];
        for (int i = 0; i < a.length; i++)
            result[i] = a[i].clone();
        return result;
    }
    static double[] column(double[][] a, int k) {
        double[] result = new double[a.length];
        for (int i = 0; i < a.length; i++)
            result[i] = a[i][k];
        return result;
    }
    static double sum(double[] x) {
        double result = 0;
        for (double v : x)
            result += v;
        return result;
    }
    static double dot(double[] a, double[] b) {
        double result = 0;
        for (int j = 0; j < a.length; j++)
            result += a[j] * b[j];
        return result;
    }
    static double[] multiply(double[][] a, double[] x) {
        double[] result = new double[a.length];
        for (int i = 0; i < a.length; i++)
            result[i] = dot(a[i], x);
        return result;
    }
    static double length(double[] x) {
        return Math.sqrt(dot(x, x));
    }
    static void normalize(double[] x) {
        double length = length(x);
        for (int j = 0; j < x.length; j++)
            x[j] /= length;
    }
    static void orient(double[] x) {
        int largest = 0;
        for (int j = 1; j < x.length; j++)
            if (Math.abs(x[j]) > Math.abs(x[largest]))
                largest = j;
        if (x[largest] < 0)
            for (int j = 0; j < x.length; j++)
                x[j] = -x[j];
    }
    static double difference(double[] a, double[] b) {
        double result = 0;
        for (int j = 0; j < a.length; j++)
            result = Math.max(result, Math.abs(a[j] - b[j]));
        return result;
    }
    static void deflate(double[][] a, double value, double[] x) {
        for (int i = 0; i < x.length; i++)
            for (int j = 0; j < x.length; j++)
                a[i][j] -= value * x[i] * x[j];
    }
    record Inverse(double[][] matrix, double determinant) {}
    static Inverse inverse(double[][] a) {
        int n = a.length;
        double[][] augmented = new double[n][2 * n];
        for (int i = 0; i < n; i++) {
            for (int j = 0; j < n; j++)
                augmented[i][j] = a[i][j];
            augmented[i][n + i] = 1;
        }
        double determinant = 1;
        for (int k = 0; k < n; k++) {
            double pivot = augmented[k][k];
            determinant *= pivot;
            for (int h = 0; h < 2 * n; h++)
                augmented[k][h] /= pivot;
            for (int i = 0; i < n; i++)
                if (i != k) {
                    double gamma = augmented[i][k];
                    for (int h = 0; h < 2 * n; h++)
                        augmented[i][h] -= gamma * augmented[k][h];
                }
        }
        double[][] result = new double[n][n];
        for (int i = 0; i < n; i++)
            for (int j = 0; j < n; j++)
                result[i][j] = augmented[i][n + j];
        return new Inverse(result, determinant);
    }
}
