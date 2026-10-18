#include <stdio.h>
#include <math.h>

int main(void) {
    int p[][2] = {{12, -7}, {-33, 25}, {41, 18}, {-8, -44}, {27, 39}, {-46, -12}, {5, 14}, {36, -29},
        {-19, 47}, {-2, 3}}, best[2] = {0, 0}, bi[2] = {0, 0}, bj[2] = {1, 1};
    for (int i = 0; i < 10; i++)
        for (int j = i + 1; j < 10; j++) {
            int dx = p[i][0] - p[j][0], dy = p[i][1] - p[j][1], d = dx * dx + dy * dy;
            for (int k = 0; k < 2; k++)
                if ((i == 0 && j == 1) || (k == 0 ? d < best[k]: d > best[k])) {
                    best[k] = d;
                    bi[k] = i;
                    bj[k] = j;
                }
        }
    for (int k = 0; k < 2; k++) {
        int q = (int)(sqrt((double) best[k]) * 10000 + 0.5);
        printf("%s: P%d P%d %d.%04d\n", k ? "farthest": "closest", bi[k], bj[k], q / 10000, q % 10000);
    }
    return 0;
}
