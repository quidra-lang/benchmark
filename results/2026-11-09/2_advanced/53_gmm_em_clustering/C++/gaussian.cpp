#include "mixture.hpp"
double determinant(Cov cov) {
    return cov[0] * cov[2] - cov[1] * cov[1];
}
double mahalanobis(Vec point, Vec mean, Cov cov) {
    const double dx = point[0] - mean[0], dy = point[1] - mean[1];
    return (cov[2] * dx * dx - 2 * cov[1] * dx * dy + cov[0] * dy * dy) / determinant(cov);
}
double weighted_log(Vec point, const Component &component) {
    return std::log(component.weight) - std::log(2 * pi) - std::log(determinant(component.cov)) / 2 -
           mahalanobis(point, component.mean, component.cov) / 2;
}
Eigen eigen(Cov cov) {
    const double a = cov[0], b = cov[1], c = cov[2], h = (a + c) / 2,
                 g = std::sqrt(((a - c) / 2) * ((a - c) / 2) + b * b), leading = h + g, trailing = h - g;
    Vec direction;
    if (b == 0)
        direction = a >= c ? Vec{1, 0} : Vec{0, 1};
    else {
        const double vx = a >= c ? leading - c : b, vy = a >= c ? b : leading - a,
                     length = std::sqrt(vx * vx + vy * vy);
        direction = vx < 0 ? Vec{-vx / length, -vy / length} : Vec{vx / length, vy / length};
    }
    return {leading,
            trailing,
            direction,
            std::atan2(direction[1], direction[0]) * 180 / pi,
            std::sqrt(leading),
            std::sqrt(trailing),
            pi * std::sqrt(leading * trailing),
            b / std::sqrt(a * c)};
}
double bhattacharyya(const Component &a, const Component &b) {
    Cov average;
    for (int i = 0; i < 3; ++i)
        average[i] = (a.cov[i] + b.cov[i]) / 2;
    return mahalanobis(b.mean, a.mean, average) / 8 +
           std::log(determinant(average) / std::sqrt(determinant(a.cov) * determinant(b.cov))) / 2;
}
