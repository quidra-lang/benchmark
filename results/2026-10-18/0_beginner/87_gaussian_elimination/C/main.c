#include <stdio.h>
#include <math.h>

int main(void) {
    double systems[2][4][5] = {{{2, -1, 3, 7}, {4, 1, -2, 3}, {-3, 5, 1, -4}},
                               {{1, 3, -2, 4, 6}, {5, -2, 1, 3, -7}, {-2, 4, 6, -1, 9}, {3, 1, -4, 2, 5}}};
    for (int s = 0; s < 2; s++) {
        int n = s + 3;
        double (*a)[5] = systems[s], x[4];
        for (int k = 0; k < n; k++) {
            int pivot = k;
            for (int i = k + 1; i < n; i++)
                if (fabs(a[i][k]) > fabs(a[pivot][k]))
                    pivot = i;
            if (pivot != k)
                for (int j = 0; j <= n; j++) {
                    double t = a[k][j];
                    a[k][j] = a[pivot][j];
                    a[pivot][j] = t;
                }
            for (int i = k + 1; i < n; i++) {
                double f = a[i][k] / a[k][k];
                for (int j = k; j <= n; j++)
                    a[i][j] = a[i][j] - f * a[k][j];
            }
        }
        for (int i = n - 1; i >= 0; i--) {
            double sum = a[i][n];
            for (int j = i + 1; j < n; j++)
                sum = sum - a[i][j] * x[j];
            x[i] = sum / a[i][i];
        }
        printf("system %d:\n", s + 1);
        for (int i = 0; i < n; i++)
            printf("x%d = %.4f\n", i + 1, x[i]);
    }
    return 0;
}
