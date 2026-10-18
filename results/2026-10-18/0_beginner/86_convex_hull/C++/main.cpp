#include <iostream>
#include <vector>
#include <algorithm>
#include <utility>

using Point = std::pair<int, int>;
int cross(Point o, Point a, Point b) {
    return (a.first - o.first) * (b.second - o.second) - (a.second - o.second) * (b.first - o.first);
}

int main() {
    std::vector<Point> points = {{3, 2}, {-6, 1}, {8, 4}, {0, 0}, {-3, 7}, {4, -3}, {1, -5}, {-2, 1},
        {5, 6}, {-6, -2}, {2, -2}, {7, -1}, {-3, 4}, {2, 8}, {-6, 3}};
    std::sort(points.begin(), points.end());
    std::vector<Point> lower, upper;
    for (Point p : points) {
        while (lower.size() >= 2 && cross(lower[lower.size() - 2], lower.back(), p) <= 0)
            lower.pop_back();
        lower.push_back(p);
    }
    for (std::vector<Point>::reverse_iterator i = points.rbegin(); i != points.rend(); ++i) {
        Point p = *i;
        while (upper.size() >= 2 && cross(upper[upper.size() - 2], upper.back(), p) <= 0)
            upper.pop_back();
        upper.push_back(p);
    }
    lower.pop_back();
    upper.pop_back();
    lower.insert(lower.end(), upper.begin(), upper.end());
    int twice = 0;
    std::cout << "hull: " << lower.size() << " points\n";
    for (std::size_t i = 0; i < lower.size(); i++) {
        Point p = lower[i], q = lower[(i + 1) % lower.size()];
        std::cout << '(' << p.first << ", " << p.second << ")\n";
        twice += p.first * q.second - q.first * p.second;
    }
    std::cout << "area: " << twice / 2 << '.' << twice % 2 * 5 << '\n';
}
