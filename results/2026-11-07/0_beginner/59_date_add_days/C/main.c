#include <stdio.h>

int days(int y, int m) {
    static const int lengths[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return lengths[m - 1] + (m == 2 && (y % 400 == 0 || (y % 4 == 0 && y % 100 != 0)));
}

int main(void) {
    int cases[][4] = {{1999, 12, 25, 10}, {2000, 2, 27, 3}, {2021, 2, 20, 14}, {2023, 11, 15, 120},
        {2026, 10, 17, 1500}};
    for (int i = 0; i < 5; i++) {
        int y = cases[i][0], m = cases[i][1], d = cases[i][2], n = cases[i][3];
        for (int j = 0; j < n; j++) {
            d++;
            if (d > days(y, m)) {
                d = 1;
                m++;
                if (m > 12) {
                    m = 1;
                    y++;
                }
            }
        }
        printf("%04d-%02d-%02d + %d days = %04d-%02d-%02d\n", cases[i][0], cases[i][1], cases[i][2], n,
            y, m, d);
    }
    return 0;
}
