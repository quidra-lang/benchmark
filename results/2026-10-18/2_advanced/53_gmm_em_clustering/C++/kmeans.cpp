#include "mixture.hpp"
double distance2(Vec a, Vec b) {
    const double x = a[0] - b[0], y = a[1] - b[1];
    return x * x + y * y;
}
double distance(Vec a, Vec b) {
    return std::sqrt(distance2(a, b));
}
static Ids assign(const std::vector<Point> &points, const std::vector<Vec> &centers) {
    Ids out;
    for (const Point &point : points) {
        int chosen = 0;
        double best = distance2(point.xy, centers[0]);
        for (int j = 1; j < int(centers.size()); ++j) {
            const double d = distance2(point.xy, centers[j]);
            if (d < best) {
                best = d;
                chosen = j;
            }
        }
        out.push_back(chosen);
    }
    return out;
}
Kmeans run_kmeans(const std::vector<Point> &points, const Model &initial, int maximum) {
    Kmeans out;
    for (const auto &component : initial.components)
        out.centers.push_back(component.mean);
    out.assignment = assign(points, out.centers);
    for (int t = 1; t <= maximum; ++t) {
        for (int j = 0; j < int(out.centers.size()); ++j) {
            Vec total{};
            int count = 0;
            for (int i = 0; i < int(points.size()); ++i)
                if (out.assignment[i] == j) {
                    ++count;
                    total[0] += points[i].xy[0];
                    total[1] += points[i].xy[1];
                }
            if (count)
                out.centers[j] = {total[0] / count, total[1] / count};
        }
        Ids assigned = assign(points, out.centers);
        out.iterations = t;
        const bool same = assigned == out.assignment;
        out.assignment = std::move(assigned);
        if (same)
            break;
    }
    out.sizes.resize(out.centers.size());
    for (int i = 0; i < int(points.size()); ++i) {
        out.inertia += distance2(points[i].xy, out.centers[out.assignment[i]]);
        ++out.sizes[out.assignment[i]];
    }
    return out;
}
