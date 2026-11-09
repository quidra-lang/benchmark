using System;
using System.Collections.Generic;
using System.Linq;

sealed record Massey(double[] Ratings, double HomeAdvantage);
static class LinearModels {
    public static double[] Cholesky(double[][] matrix, double[] vector) {
        int size = vector.Length;
        double[][] lower = Enumerable.Range(0, size).Select(_ => new double[size]).ToArray();
        for (int i = 0; i < size; i++) for (int j = 0; j <= i; j++) {
            double total = 0;
            for (int k = 0; k < j; k++) total += lower[i][k] * lower[j][k];
            lower[i][j] = j < i ? (matrix[i][j] - total) / lower[j][j] : Math.Sqrt(matrix[i][i] - total);
        }
        double[] forward = new double[size];
        for (int i = 0; i < size; i++) {
            double total = 0;
            for (int k = 0; k < i; k++) total += lower[i][k] * forward[k];
            forward[i] = (vector[i] - total) / lower[i][i];
        }
        double[] solution = new double[size];
        for (int i = size - 1; i >= 0; i--) {
            double total = 0;
            for (int k = i + 1; k < size; k++) total += lower[k][i] * solution[k];
            solution[i] = (forward[i] - total) / lower[i][i];
        }
        return solution;
    }
    public static double[] Gaussian(double[][] matrix, double[] vector) {
        int size = vector.Length;
        for (int k = 0; k < size; k++) {
            int pivot = k;
            for (int row = k + 1; row < size; row++) if (Math.Abs(matrix[row][k]) > Math.Abs(matrix[pivot][k])) pivot = row;
            (matrix[k], matrix[pivot]) = (matrix[pivot], matrix[k]); (vector[k], vector[pivot]) = (vector[pivot], vector[k]);
            for (int i = k + 1; i < size; i++) {
                double factor = matrix[i][k] / matrix[k][k];
                for (int j = k; j < size; j++) matrix[i][j] -= factor * matrix[k][j];
                vector[i] -= factor * vector[k];
            }
        }
        double[] solution = new double[size];
        for (int i = size - 1; i >= 0; i--) {
            double total = 0;
            for (int j = i + 1; j < size; j++) total += matrix[i][j] * solution[j];
            solution[i] = (vector[i] - total) / matrix[i][i];
        }
        return solution;
    }
    public static double[] Colley(int count, List<Match> matches) {
        double[][] matrix = Enumerable.Range(0, count).Select(_ => new double[count]).ToArray();
        int[] balance = new int[count];
        for (int i = 0; i < count; i++) matrix[i][i] = 2;
        foreach (Match match in matches) {
            int home = match.Home, away = match.Away;
            matrix[home][home]++; matrix[away][away]++; matrix[home][away]--; matrix[away][home]--;
            if (match.Margin > 0) { balance[home]++; balance[away]--; }
            else if (match.Margin < 0) { balance[home]--; balance[away]++; }
        }
        double[] vector = new double[count];
        for (int i = 0; i < count; i++) vector[i] = 1 + balance[i] / 2.0;
        return Cholesky(matrix, vector);
    }
    public static Massey FitMassey(int count, List<Match> matches) {
        int size = count + 1;
        double[][] matrix = Enumerable.Range(0, size).Select(_ => new double[size]).ToArray();
        double[] vector = new double[size];
        foreach (Match match in matches) {
            int home = match.Home, away = match.Away, margin = match.Margin;
            matrix[home][home]++; matrix[away][away]++; matrix[home][away]--; matrix[away][home]--;
            matrix[home][count]++; matrix[count][home]++; matrix[away][count]--; matrix[count][away]--; matrix[count][count]++;
            vector[home] += margin; vector[away] -= margin; vector[count] += margin;
        }
        Array.Fill(matrix[count - 1], 1); matrix[count - 1][count] = 0; vector[count - 1] = 0;
        double[] solution = Gaussian(matrix, vector);
        return new Massey(solution[..count], solution[count]);
    }
}
