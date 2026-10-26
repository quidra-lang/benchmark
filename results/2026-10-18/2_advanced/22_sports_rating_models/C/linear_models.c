#include "ratings.h"

void colley_ratings(int n, const Match *matches, int count, double *ratings) {
    double matrix[30][30] = {{0}}, lower[30][30] = {{0}}, vector[30], forward[30];
    int balance[30] = {0};
    for (int i = 0; i < n; ++i) matrix[i][i] = 2;
    for (int k = 0; k < count; ++k) {
        Match match = matches[k];
        int home = match.home, away = match.away;
        matrix[home][home] += 1;
        matrix[away][away] += 1;
        matrix[home][away] -= 1;
        matrix[away][home] -= 1;
        int result = match.margin > 0 ? 1 : match.margin < 0 ? -1 : 0;
        balance[home] += result;
        balance[away] -= result;
    }
    for (int i = 0; i < n; ++i) vector[i] = 1 + balance[i] / 2.0;
    for (int i = 0; i < n; ++i) for (int j = 0; j <= i; ++j) {
        double total = 0;
        for (int k = 0; k < j; ++k) total += lower[i][k] * lower[j][k];
        lower[i][j] = j < i ? (matrix[i][j] - total) / lower[j][j] : sqrt(matrix[i][i] - total);
    }
    for (int i = 0; i < n; ++i) {
        double total = 0;
        for (int k = 0; k < i; ++k) total += lower[i][k] * forward[k];
        forward[i] = (vector[i] - total) / lower[i][i];
    }
    for (int i = n - 1; i >= 0; --i) {
        double total = 0;
        for (int k = i + 1; k < n; ++k) total += lower[k][i] * ratings[k];
        ratings[i] = (forward[i] - total) / lower[i][i];
    }
}

double massey_ratings(int n, const Match *matches, int count, double *ratings) {
    int size = n + 1;
    double matrix[31][31] = {{0}}, vector[31] = {0}, solution[31];
    for (int k = 0; k < count; ++k) {
        Match match = matches[k];
        int home = match.home, away = match.away;
        matrix[home][home] += 1;
        matrix[away][away] += 1;
        matrix[home][away] -= 1;
        matrix[away][home] -= 1;
        matrix[home][n] += 1;
        matrix[n][home] += 1;
        matrix[away][n] -= 1;
        matrix[n][away] -= 1;
        matrix[n][n] += 1;
        vector[home] += match.margin;
        vector[away] -= match.margin;
        vector[n] += match.margin;
    }
    for (int j = 0; j < size; ++j) matrix[n - 1][j] = j < n ? 1 : 0;
    vector[n - 1] = 0;
    for (int k = 0; k < size; ++k) {
        int pivot = k;
        for (int row = k + 1; row < size; ++row) if (fabs(matrix[row][k]) > fabs(matrix[pivot][k])) pivot = row;
        for (int j = 0; j < size; ++j) {
            double temporary = matrix[k][j];
            matrix[k][j] = matrix[pivot][j];
            matrix[pivot][j] = temporary;
        }
        double temporary = vector[k];
        vector[k] = vector[pivot];
        vector[pivot] = temporary;
        for (int i = k + 1; i < size; ++i) {
            double factor = matrix[i][k] / matrix[k][k];
            for (int j = k; j < size; ++j) matrix[i][j] -= factor * matrix[k][j];
            vector[i] -= factor * vector[k];
        }
    }
    for (int i = size - 1; i >= 0; --i) {
        double total = 0;
        for (int j = i + 1; j < size; ++j) total += matrix[i][j] * solution[j];
        solution[i] = (vector[i] - total) / matrix[i][i];
    }
    memcpy(ratings, solution, (size_t)n * sizeof(double));
    return solution[n];
}
