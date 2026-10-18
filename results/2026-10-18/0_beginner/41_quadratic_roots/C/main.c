#include <stdio.h>
#include <stdlib.h>
#include <math.h>

void decimal(double x, char *out) {
    long long q = (long long)(fabs(x) * 10000.0 + 0.5);
    sprintf(out, "%s%lld.%04lld", x < 0 ? "-": "", q / 10000, q % 10000);
}

int main(void) {
    int coefficients[][3] = {{1, -3, -10}, {-2, 5, 4}, {3, 1, -2}, {4, -12, 9}, {1, 2, 5}, {-2, 3, -4}};
    for (int i = 0; i < 6; i++) {
        int a = coefficients[i][0], b = coefficients[i][1], c = coefficients[i][2], d = b * b - 4 * a * c;
        char u[64], v[64];
        printf("%d %d %d: ", a, b, c);
        if (d > 0) {
            double x = (-b + sqrt((double) d)) / (2.0 * a), y = (-b - sqrt((double) d)) / (2.0 * a);
            if (x < y) {
                double t = x;
                x = y;
                y = t;
            }
            decimal(x, u);
            decimal(y, v);
            printf("x1 = %s, x2 = %s\n", u, v);
        } else if (d == 0) {
            decimal(-b / (2.0 * a), u);
            printf("x = %s\n", u);
        } else {
            decimal(-b / (2.0 * a), u);
            decimal(sqrt((double) - d) / (2.0 * abs(a)), v);
            printf("x = %s + %si, %s - %si\n", u, v, u, v);
        }
    }
    return 0;
}
