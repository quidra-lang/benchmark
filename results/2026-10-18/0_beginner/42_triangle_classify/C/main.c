#include <stdio.h>
#include <string.h>

int main(void) {
    int values[][3] = {{3, 8, 5}, {6, 6, 6}, {5, 8, 5}, {13, 5, 12}, {2, 9, 4}, {7, 4, 7}, {8, 6, 7}, {4, 9, 6}};
    for (int i = 0; i < 8; i++) {
        int a[3];
        memcpy(a, values[i], sizeof a);
        for (int j = 0; j < 3; j++)
            for (int k = j + 1; k < 3; k++)
                if (a[j] > a[k]) {
                    int t = a[j];
                    a[j] = a[k];
                    a[k] = t;
                }
        printf("%d %d %d: ", values[i][0], values[i][1], values[i][2]);
        if (a[0] + a[1] <= a[2]) {
            puts("not a triangle");
        } else {
            const char *side = a[0] == a[2] ? "equilateral" : a[0] == a[1] || a[1] == a[2] ? "isosceles" : "scalene";
            int d = a[2] * a[2] - a[0] * a[0] - a[1] * a[1];
            printf("%s %s\n", side, d < 0 ? "acute" : d == 0 ? "right" : "obtuse");
        }
    }
    return 0;
}
