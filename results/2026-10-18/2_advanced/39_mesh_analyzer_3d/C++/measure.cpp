#include "mesh.hpp"
Point difference(Point a, Point b) {
    return {a[0] - b[0], a[1] - b[1], a[2] - b[2]};
}
Point cross(Point a, Point b) {
    return {a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]};
}
Integer dot(Point a, Point b) {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}
Point normal(const Face &face, const std::vector<Point> &points) {
    const auto &v = face.vertices;
    return cross(difference(points[v[1]], points[v[0]]), difference(points[v[2]], points[v[0]]));
}
Integer determinant(const Face &face, const std::vector<Point> &points) {
    const auto &v = face.vertices;
    return dot(points[v[0]], cross(points[v[1]], points[v[2]]));
}
double area(const std::vector<int> &faces, const std::vector<Face> &mesh, const std::vector<Point> &points) {
    double total = 0;
    for (int f : faces) {
        const Point n = normal(mesh[f], points);
        total += std::sqrt(double(dot(n, n)));
    }
    return total / 2;
}
std::string fraction(Integer numerator, Integer denominator) {
    if (denominator < 0) {
        denominator = -denominator;
        numerator = -numerator;
    }
    const Integer divisor = std::gcd(numerator, denominator);
    numerator /= divisor;
    denominator /= divisor;
    return std::to_string(numerator) + (denominator == 1 ? "" : "/" + std::to_string(denominator));
}
std::string real(double value) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(3) << value;
    return out.str();
}
std::string point_text(Point point) {
    return std::to_string(point[0]) + " " + std::to_string(point[1]) + " " + std::to_string(point[2]);
}
std::string centroid(const std::vector<int> &faces, const std::vector<Face> &mesh,
                     const std::vector<Point> &points, Integer volume6) {
    Point sum{};
    for (int f : faces) {
        const Face &face = mesh[f];
        const Integer d = determinant(face, points);
        for (int axis = 0; axis < 3; ++axis)
            sum[axis] += d * (points[face.vertices[0]][axis] + points[face.vertices[1]][axis] +
                              points[face.vertices[2]][axis]);
    }
    return fraction(sum[0], 4 * volume6) + " " + fraction(sum[1], 4 * volume6) + " " +
           fraction(sum[2], 4 * volume6);
}
int winding(Point point, const std::vector<int> &faces, const std::vector<Face> &mesh,
            const std::vector<Point> &points) {
    double total = 0;
    for (int f : faces) {
        const Face &face = mesh[f];
        const Point a = difference(points[face.vertices[0]], point),
                    b = difference(points[face.vertices[1]], point),
                    c = difference(points[face.vertices[2]], point);
        const double al = std::sqrt(double(dot(a, a))), bl = std::sqrt(double(dot(b, b))),
                     cl = std::sqrt(double(dot(c, c)));
        const double denominator =
            al * bl * cl + double(dot(a, b)) * cl + double(dot(b, c)) * al + double(dot(c, a)) * bl;
        total += 2 * std::atan2(double(dot(a, cross(b, c))), denominator);
    }
    return int(std::llround(total / (4 * std::acos(-1.0))));
}
std::string triangle_angle(const Face &face, const std::vector<Point> &points) {
    const auto &v = face.vertices;
    Integer smallest = dot(difference(points[v[1]], points[v[0]]), difference(points[v[2]], points[v[0]]));
    for (int i = 1; i < 3; ++i)
        smallest = std::min(smallest, dot(difference(points[v[(i + 1) % 3]], points[v[i]]),
                                          difference(points[v[(i + 2) % 3]], points[v[i]])));
    return smallest < 0 ? "obtuse" : smallest == 0 ? "right" : "acute";
}
