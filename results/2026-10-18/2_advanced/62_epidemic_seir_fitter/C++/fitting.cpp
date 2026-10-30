#include "epidemic.hpp"
Golden golden(const std::function<double(double)> &function, double a, double b, int iterations) {
    constexpr double phi = 0.6180339887498949;
    double c = b - phi * (b - a), d = a + phi * (b - a), fc = function(c), fd = function(d);
    Golden out{};
    out.records.push_back({a, b, c, d, fc, fd});
    for (int i = 0; i < iterations; ++i) {
        if (fc < fd) {
            b = d;
            d = c;
            fd = fc;
            c = b - phi * (b - a);
            fc = function(c);
        } else {
            a = c;
            c = d;
            fc = fd;
            d = a + phi * (b - a);
            fd = function(d);
        }
        out.records.push_back({a, b, c, d, fc, fd});
    }
    out.point = fc < fd ? c : d;
    out.value = fc < fd ? fc : fd;
    return out;
}
static bool vertex_less(const Vertex &a, const Vertex &b) {
    return a.value != b.value ? a.value < b.value : a.number < b.number;
}
static Point along(Point first, double factor, Point second) {
    return {first[0] + factor * (second[0] - first[0]), first[1] + factor * (second[1] - first[1])};
}
Simplex nelder_mead(const std::function<double(Point)> &function, Point start,
                    const Params &params) {
    Simplex out;
    const std::array<Point, 3> points{start, Point{start[0] + params.delta_beta, start[1]},
                                      Point{start[0], start[1] + params.delta_gamma}};
    int serial = 0;
    for (int i = 0; i < 3; ++i)
        out.initial[i] = {points[i], function(points[i]), serial++};
    auto vertices = out.initial;
    for (int iteration = 0; iteration < params.nelder; ++iteration) {
        std::sort(vertices.begin(), vertices.end(), vertex_less);
        const Vertex first = vertices[0], second = vertices[1], third = vertices[2];
        const Point centroid{(first.point[0] + second.point[0]) / 2,
                             (first.point[1] + second.point[1]) / 2},
            reflected{centroid[0] + params.alpha * (centroid[0] - third.point[0]),
                      centroid[1] + params.alpha * (centroid[1] - third.point[1])};
        const double fr = function(reflected);
        Point accepted = reflected;
        double value = fr;
        std::string operation = "reflect";
        bool shrink = false;
        if (fr < first.value) {
            const Point expanded = along(centroid, params.chi, reflected);
            const double fe = function(expanded);
            if (fe < fr) {
                accepted = expanded;
                value = fe;
                operation = "expand";
            }
        } else if (fr < second.value) {
        } else if (fr < third.value) {
            const Point contracted = along(centroid, params.psi, reflected);
            const double fc = function(contracted);
            if (fc <= fr) {
                accepted = contracted;
                value = fc;
                operation = "contract_out";
            } else
                shrink = true;
        } else {
            const Point contracted = along(centroid, params.psi, third.point);
            const double fc = function(contracted);
            if (fc < third.value) {
                accepted = contracted;
                value = fc;
                operation = "contract_in";
            } else
                shrink = true;
        }
        if (shrink) {
            operation = "shrink";
            for (int i = 1; i < 3; ++i) {
                const Point point = along(first.point, params.omega, vertices[i].point);
                vertices[i] = {point, function(point), serial++};
            }
        } else
            vertices[2] = {accepted, value, serial++};
        std::sort(vertices.begin(), vertices.end(), vertex_less);
        out.records.push_back({operation, vertices[0]});
    }
    std::sort(vertices.begin(), vertices.end(), vertex_less);
    out.final = vertices;
    return out;
}
