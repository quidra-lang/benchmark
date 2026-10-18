#include <stdio.h>
#include <stdlib.h>

typedef struct {
    int x, y;
} Point;
int compare(const void *a, const void *b) {
    const Point * x = a, *y = b;
    return x->x != y->x ? x->x - y->x: x->y - y->y;
}

int cross(Point o, Point a, Point b) {
    return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
}

int main(void) {
    Point points[] = {{3, 2}, {-6, 1}, {8, 4}, {0, 0}, {-3, 7}, {4, -3}, {1, -5}, {-2, 1}, {5, 6},
        {-6, -2}, {2, -2}, {7, -1}, {-3, 4}, {2, 8}, {-6, 3}};
    qsort(points, 15, sizeof(Point), compare);
    Point lower[15], upper[15], hull[30];
    int nl = 0, nu = 0, nh = 0;
    for (int i = 0; i < 15; i++) {
        while (nl >= 2 && cross(lower[nl - 2], lower[nl - 1], points[i]) <= 0)
            nl--;
        lower[nl++] = points[i];
    }
    for (int i = 14; i >= 0; i--) {
        while (nu >= 2 && cross(upper[nu - 2], upper[nu - 1], points[i]) <= 0)
            nu--;
        upper[nu++] = points[i];
    }
    for (int i = 0; i < nl - 1; i++)
        hull[nh++] = lower[i];
    for (int i = 0; i < nu - 1; i++)
        hull[nh++] = upper[i];
    int twice = 0;
    printf("hull: %d points\n", nh);
    for (int i = 0; i < nh; i++) {
        Point p = hull[i], q = hull[(i + 1) % nh];
        printf("(%d, %d)\n", p.x, p.y);
        twice += p.x * q.y - q.x * p.y;
    }
    printf("area: %d.%d\n", twice / 2, twice % 2 * 5);
    return 0;
}
