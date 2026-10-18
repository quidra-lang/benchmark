#include <stdio.h>
#include <stdlib.h>
#include <math.h>

int main(void) {
    int polygons[3][7][2] = {{{0, 0}, {5, 0}, {6, 4}, {1, 3}}, {{2, 1}, {0, 4}, {3, 7}, {7, 6}, {8,
        2}}, {{0, 0}, {8, 0}, {8, 6}, {5, 6}, {4, 3}, {3, 6}, {0, 6}}}, sizes[] = {4, 5, 7};
    for (int k = 0; k < 3; k++) {
        int twice = 0;
        double perimeter = 0;
        for (int i = 0; i < sizes[k]; i++) {
            int j = (i + 1) % sizes[k], x = polygons[k][i][0], y = polygons[k][i][1], nx = polygons[k][j][0], ny = polygons[k][j][1], dx = x - nx, dy = y - ny;
            twice += x * ny - nx * y;
            perimeter += sqrt((double)(dx * dx + dy * dy));
        }
        twice = abs(twice);
        int q = (int)(perimeter * 1000 + 0.5);
        printf("polygon %d: area=%d.%d perimeter=%d.%03d\n", k + 1, twice / 2, (twice % 2) * 5, q / 1000,
            q % 1000);
    }
    return 0;
}
