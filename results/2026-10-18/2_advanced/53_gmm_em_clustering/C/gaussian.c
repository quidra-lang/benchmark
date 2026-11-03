#include "mixture.h"
static const double pi = 3.141592653589793;
double determinant(Cov cov) {
    return cov.a * cov.c - cov.b * cov.b;
}
double mahalanobis(Vec point, Vec mean, Cov cov) {
    double dx = point.x - mean.x, dy = point.y - mean.y;
    return (cov.c * dx * dx - 2 * cov.b * dx * dy + cov.a * dy * dy) / determinant(cov);
}
double weighted_log(Vec point, Component component) {
    return log(component.weight) - log(2 * pi) - log(determinant(component.cov)) / 2 -
           mahalanobis(point, component.mean, component.cov) / 2;
}
Eigen eigen(Cov cov) {
    double a = cov.a, b = cov.b, c = cov.c, h = (a + c) / 2, g = sqrt(((a - c) / 2) * ((a - c) / 2) + b * b),
           leading = h + g, trailing = h - g;
    Vec direction;
    if (b == 0)
        direction = a >= c ? (Vec){1, 0} : (Vec){0, 1};
    else {
        double vx = a >= c ? leading - c : b, vy = a >= c ? b : leading - a, length = sqrt(vx * vx + vy * vy);
        direction = vx < 0 ? (Vec){-vx / length, -vy / length} : (Vec){vx / length, vy / length};
    }
    return (Eigen){leading,
                   trailing,
                   direction,
                   atan2(direction.y, direction.x) * 180 / pi,
                   sqrt(leading),
                   sqrt(trailing),
                   pi * sqrt(leading * trailing),
                   b / sqrt(a * c)};
}
double bhattacharyya(Component a, Component b) {
    Cov average = {(a.cov.a + b.cov.a) / 2, (a.cov.b + b.cov.b) / 2, (a.cov.c + b.cov.c) / 2};
    return mahalanobis(b.mean, a.mean, average) / 8 +
           log(determinant(average) / sqrt(determinant(a.cov) * determinant(b.cov))) / 2;
}
