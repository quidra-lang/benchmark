#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(void) {
    int coefficients[][3] = {{1, -3, -10}, {-2, 5, 4}, {3, 1, -2}, {4, -12, 9}, {1, 2, 5}, {-2, 3, -4}};
    for (int i = 0; i < 6; ++i) {
        int a = coefficients[i][0], b = coefficients[i][1], c = coefficients[i][2];
        int d = b * b - 4 * a * c;
        printf("%d %d %d: ", a, b, c);
        if (d > 0) {
            double root = sqrt((double)d);
            double x = (-b + root) / (2.0 * a), y = (-b - root) / (2.0 * a);
            if (x < y) {
                double t = x;
                x = y;
                y = t;
            }
            printf("x1 = %.4f, x2 = %.4f\n", x, y);
        } else if (d == 0) {
            printf("x = %.4f\n", -b / (2.0 * a));
        } else {
            double p = -b / (2.0 * a), q = sqrt((double)-d) / (2.0 * abs(a));
            printf("x = %.4f + %.4fi, %.4f - %.4fi\n", p, q, p, q);
        }
    }
    return 0;
}
