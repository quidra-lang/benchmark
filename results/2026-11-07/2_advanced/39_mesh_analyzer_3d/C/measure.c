#include "mesh.h"
#include <math.h>
Point difference(Point a, Point b) {
    return (Point){{a.v[0] - b.v[0], a.v[1] - b.v[1], a.v[2] - b.v[2]}};
}
Point cross(Point a, Point b) {
    return (Point){{a.v[1] * b.v[2] - a.v[2] * b.v[1], a.v[2] * b.v[0] - a.v[0] * b.v[2],
                    a.v[0] * b.v[1] - a.v[1] * b.v[0]}};
}
Integer dot(Point a, Point b) {
    return a.v[0] * b.v[0] + a.v[1] * b.v[1] + a.v[2] * b.v[2];
}
Point normal(const Face *face, const Point *points) {
    return cross(difference(points[face->v[1]], points[face->v[0]]),
                 difference(points[face->v[2]], points[face->v[0]]));
}
Integer determinant(const Face *face, const Point *points) {
    return dot(points[face->v[0]], cross(points[face->v[1]], points[face->v[2]]));
}
double area(const IntList *face_ids, const Faces *faces, const Point *points) {
    double sum = 0;
    for (int i = 0; i < face_ids->count; ++i) {
        Point n = normal(&faces->data[face_ids->data[i]], points);
        sum += sqrt((double)dot(n, n));
    }
    return sum / 2;
}
char *fraction(Integer numerator, Integer denominator) {
    if (denominator < 0) {
        numerator = -numerator;
        denominator = -denominator;
    }
    Integer a = numerator < 0 ? -numerator : numerator, b = denominator;
    while (b) {
        Integer remainder = a % b;
        a = b;
        b = remainder;
    }
    numerator /= a;
    denominator /= a;
    return denominator == 1 ? format("%lld", (long long)numerator)
                            : format("%lld/%lld", (long long)numerator, (long long)denominator);
}
char *real(double value) {
    return format("%.3f", value);
}
char *point_text(Point point) {
    return format("%lld %lld %lld", (long long)point.v[0], (long long)point.v[1], (long long)point.v[2]);
}
char *centroid(const IntList *face_ids, const Faces *faces, const Point *points, Integer volume6) {
    Point sum = {{0}};
    for (int i = 0; i < face_ids->count; ++i) {
        const Face *face = &faces->data[face_ids->data[i]];
        Integer d = determinant(face, points);
        for (int axis = 0; axis < 3; ++axis)
            sum.v[axis] +=
                d * (points[face->v[0]].v[axis] + points[face->v[1]].v[axis] + points[face->v[2]].v[axis]);
    }
    char *x = fraction(sum.v[0], 4 * volume6), *y = fraction(sum.v[1], 4 * volume6),
         *z = fraction(sum.v[2], 4 * volume6);
    char *out = format("%s %s %s", x, y, z);
    free(x);
    free(y);
    free(z);
    return out;
}
int winding(Point point, const IntList *face_ids, const Faces *faces, const Point *points) {
    double sum = 0;
    for (int i = 0; i < face_ids->count; ++i) {
        const Face *face = &faces->data[face_ids->data[i]];
        Point a = difference(points[face->v[0]], point), b = difference(points[face->v[1]], point),
              c = difference(points[face->v[2]], point);
        double al = sqrt((double)dot(a, a)), bl = sqrt((double)dot(b, b)), cl = sqrt((double)dot(c, c));
        double denominator =
            al * bl * cl + (double)dot(a, b) * cl + (double)dot(b, c) * al + (double)dot(c, a) * bl;
        sum += 2 * atan2((double)dot(a, cross(b, c)), denominator);
    }
    return (int)llround(sum / (4 * acos(-1.0)));
}
const char *triangle_angle(const Face *face, const Point *points) {
    Integer smallest = INT64_MAX;
    for (int i = 0; i < 3; ++i) {
        Integer value = dot(difference(points[face->v[(i + 1) % 3]], points[face->v[i]]),
                            difference(points[face->v[(i + 2) % 3]], points[face->v[i]]));
        if (value < smallest)
            smallest = value;
    }
    return smallest < 0 ? "obtuse" : smallest == 0 ? "right" : "acute";
}
