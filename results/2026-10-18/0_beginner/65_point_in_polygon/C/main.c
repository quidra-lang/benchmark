#include <stdio.h>

int main(void) {
    int polygon[][2] = {{1, 1}, {11, 2}, {13, 9}, {9, 7}, {7, 12}, {5, 6}, {2, 10}, {3, 5}};
    int points[][2] = {{4, 8}, {6, 4}, {10, 8}, {7, 11}, {14, 3}, {12, 8}};
    for (int k = 0; k < 6; k++) {
        int px = points[k][0], py = points[k][1], inside = 0;
        for (int i = 0; i < 8; i++) {
            int j = (i + 1) % 8, x1 = polygon[i][0], y1 = polygon[i][1], x2 = polygon[j][0], y2 = polygon[j][1];
            if ((y1 > py) != (y2 > py)) {
                double intersection = x1 + (double)(x2 - x1) * (py - y1) / (y2 - y1);
                if (intersection > px)
                    inside = !inside;
            }
        }
        printf("(%d, %d): %s\n", px, py, inside ? "inside" : "outside");
    }
    return 0;
}
