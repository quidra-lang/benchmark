#include "mixture.h"
double distance2(Vec a, Vec b) {
    double x = a.x - b.x, y = a.y - b.y;
    return x * x + y * y;
}
double distance(Vec a, Vec b) {
    return sqrt(distance2(a, b));
}
static void assign(const Point *points, int count, const Vec *centers, int k, int *result) {
    for (int i = 0; i < count; ++i) {
        int chosen = 0;
        double best = distance2(points[i].xy, centers[0]);
        for (int j = 1; j < k; ++j) {
            double d = distance2(points[i].xy, centers[j]);
            if (d < best) {
                best = d;
                chosen = j;
            }
        }
        result[i] = chosen;
    }
}
Kmeans run_kmeans(const Point *points, int count, Model initial, int maximum) {
    Kmeans out = {0};
    for (int j = 0; j < initial.k; ++j)
        out.centers[j] = initial.components[j].mean;
    assign(points, count, out.centers, initial.k, out.assignment);
    for (int t = 1; t <= maximum; ++t) {
        for (int j = 0; j < initial.k; ++j) {
            Vec total = {0};
            int members = 0;
            for (int i = 0; i < count; ++i)
                if (out.assignment[i] == j) {
                    ++members;
                    total.x += points[i].xy.x;
                    total.y += points[i].xy.y;
                }
            if (members)
                out.centers[j] = (Vec){total.x / members, total.y / members};
        }
        int labels[300];
        assign(points, count, out.centers, initial.k, labels);
        bool same = true;
        for (int i = 0; i < count; ++i) {
            same = same && labels[i] == out.assignment[i];
            out.assignment[i] = labels[i];
        }
        out.iterations = t;
        if (same)
            break;
    }
    for (int i = 0; i < count; ++i) {
        out.inertia += distance2(points[i].xy, out.centers[out.assignment[i]]);
        ++out.sizes[out.assignment[i]];
    }
    return out;
}
