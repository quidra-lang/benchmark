#include "geometry.h"
double radius2(Point a, Point b, Point c) {
    const Integer first = d2(a, b), second = d2(b, c), third = d2(c, a), area = orient(a, b, c);
    return (double)((first * second) * third) / (double)((4 * area) * area);
}
const char *position(Center vertex, const Point *points, Ints hull) {
    bool on = false;
    for (int k = 0; k < hull.n; ++k) {
        const Point a = points[hull.v[k]], b = points[hull.v[(k + 1) % hull.n]];
        const Integer sigma =
            (b.x - a.x) * (vertex.y - a.y * vertex.d) - (b.y - a.y) * (vertex.x - a.x * vertex.d);
        if (sigma < 0)
            return "outside";
        on = on || sigma == 0;
    }
    return on ? "on" : "inside";
}
Ints neighbor_order(const Triangulation *t, int site, Ints neighbors, int next) {
    Ints out = {0};
    const int start = next < 0 ? neighbors.v[0] : next;
    int current = start;
    while (true) {
        out.v[out.n++] = current;
        current = third(t, site, current);
        if (current < 0 || current == start)
            break;
    }
    return out;
}
double cell_area(Point site, const Center *vertices, Ints sequence) {
    double out = 0;
    for (int k = 0; k < sequence.n; ++k) {
        const Center a = vertices[sequence.v[k]], b = vertices[sequence.v[(k + 1) % sequence.n]];
        const double u = (double)a.x / a.d - site.x, w = (double)a.y / a.d - site.y,
                     un = (double)b.x / b.d - site.x, wn = (double)b.y / b.d - site.y;
        out += u * wn - un * w;
    }
    return out / 2;
}
typedef struct {
    double x, y;
} RealPoint;
static double side(RealPoint p, Integer c1, Integer c2, Integer c3) {
    return c1 * p.x + c2 * p.y - c3;
}
double clipped_area(const Point *points, int site, Ints neighbors) {
    RealPoint polygon[404] = {{0, 0}, {1000, 0}, {1000, 1000}, {0, 1000}};
    int count = 4;
    const Point s = points[site];
    for (int neighbor = 0; neighbor < neighbors.n; ++neighbor) {
        const Point t = points[neighbors.v[neighbor]];
        const Integer c1 = 2 * (t.x - s.x), c2 = 2 * (t.y - s.y),
                      c3 = t.x * t.x + t.y * t.y - s.x * s.x - s.y * s.y;
        RealPoint next[404];
        int nnext = 0;
        for (int k = 0; k < count; ++k) {
            const RealPoint p = polygon[k], q = polygon[(k + 1) % count];
            const double fp = side(p, c1, c2, c3), fq = side(q, c1, c2, c3);
            if (fp <= 0)
                next[nnext++] = p;
            if ((fp < 0 && fq > 0) || (fq < 0 && fp > 0)) {
                const double lambda = fp / (fp - fq);
                next[nnext++] = (RealPoint){p.x + (q.x - p.x) * lambda, p.y + (q.y - p.y) * lambda};
            }
        }
        memcpy(polygon, next, (size_t)nnext * sizeof *next);
        count = nnext;
    }
    double sum = 0;
    for (int k = 0; k < count; ++k) {
        const RealPoint p = polygon[k], q = polygon[(k + 1) % count];
        sum += p.x * q.y - q.x * p.y;
    }
    return sum / 2;
}
