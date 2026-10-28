#include "geometry.hpp"
double radius2(Point a, Point b, Point c) {
    const Integer first = d2(a, b), second = d2(b, c), third = d2(c, a), area = orient(a, b, c);
    return double((first * second) * third) / double((4 * area) * area);
}
std::string position(Center vertex, const std::vector<Point> &points, const Ints &hull) {
    bool on = false;
    for (std::size_t k = 0; k < hull.size(); ++k) {
        const Point a = points[hull[k]], b = points[hull[(k + 1) % hull.size()]];
        const Integer sigma =
            (b.x - a.x) * (vertex.y - a.y * vertex.d) - (b.y - a.y) * (vertex.x - a.x * vertex.d);
        if (sigma < 0)
            return "outside";
        on = on || sigma == 0;
    }
    return on ? "on" : "inside";
}
Ints neighbor_order(const Triangulation &triangulation, int site, const Ints &neighbors, int next) {
    Ints out;
    const int start = next < 0 ? neighbors[0] : next;
    int current = start;
    while (true) {
        out.push_back(current);
        current = triangulation.third(site, current);
        if (current < 0 || current == start)
            break;
    }
    return out;
}
double cell_area(Point site, const std::vector<Center> &vertices, const Ints &sequence) {
    double out = 0;
    for (std::size_t k = 0; k < sequence.size(); ++k) {
        const Center a = vertices[sequence[k]], b = vertices[sequence[(k + 1) % sequence.size()]];
        const double u = double(a.x) / a.d - site.x, w = double(a.y) / a.d - site.y,
                     un = double(b.x) / b.d - site.x, wn = double(b.y) / b.d - site.y;
        out += u * wn - un * w;
    }
    return out / 2;
}
double clipped_area(const std::vector<Point> &points, int site, const Ints &neighbors) {
    using RealPoint = std::pair<double, double>;
    std::vector<RealPoint> polygon = {{0, 0}, {1000, 0}, {1000, 1000}, {0, 1000}};
    const Point s = points[site];
    for (int neighbor : neighbors) {
        const Point t = points[neighbor];
        const Integer c1 = 2 * (t.x - s.x), c2 = 2 * (t.y - s.y),
                      c3 = t.x * t.x + t.y * t.y - s.x * s.x - s.y * s.y;
        auto value = [&](RealPoint p) { return c1 * p.first + c2 * p.second - c3; };
        std::vector<RealPoint> next;
        for (std::size_t k = 0; k < polygon.size(); ++k) {
            const RealPoint p = polygon[k], q = polygon[(k + 1) % polygon.size()];
            const double fp = value(p), fq = value(q);
            if (fp <= 0)
                next.push_back(p);
            if ((fp < 0 && fq > 0) || (fq < 0 && fp > 0)) {
                const double lambda = fp / (fp - fq);
                next.push_back(
                    {p.first + (q.first - p.first) * lambda, p.second + (q.second - p.second) * lambda});
            }
        }
        polygon = std::move(next);
    }
    double sum = 0;
    for (std::size_t k = 0; k < polygon.size(); ++k) {
        const auto p = polygon[k], q = polygon[(k + 1) % polygon.size()];
        sum += p.first * q.second - q.first * p.second;
    }
    return sum / 2;
}
