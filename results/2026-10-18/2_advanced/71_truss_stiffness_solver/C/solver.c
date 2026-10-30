#include "truss.h"
int cholesky(const Matrix *matrix, const int *free_dofs, Matrix *lower) {
    memset(lower, 0, sizeof *lower);
    lower->n = matrix->n;
    for (int i = 0; i < matrix->n; ++i)
        for (int j = 0; j <= i; ++j) {
            double value = matrix->v[i][j];
            for (int h = 0; h < j; ++h)
                value -= lower->v[i][h] * lower->v[j][h];
            if (j < i)
                lower->v[i][j] = value / lower->v[j][j];
            else {
                if (value <= 0.000000001 * matrix->v[i][i])
                    return free_dofs[i];
                lower->v[i][i] = sqrt(value);
            }
        }
    return -1;
}
void solve(const Matrix *lower, const double *right, double *out) {
    double intermediate[80];
    for (int i = 0; i < lower->n; ++i) {
        double value = right[i];
        for (int h = 0; h < i; ++h)
            value -= lower->v[i][h] * intermediate[h];
        intermediate[i] = value / lower->v[i][i];
    }
    for (int i = lower->n - 1; i >= 0; --i) {
        double value = intermediate[i];
        for (int h = i + 1; h < lower->n; ++h)
            value -= lower->v[h][i] * out[h];
        out[i] = value / lower->v[i][i];
    }
}
