#include "detector.hpp"
Canny canny(const Gradient &g, const Params &p) {
    const int w = g.gx.width, h = g.gx.height;
    Canny out{Image(w, h), Image(w, h), Image(w, h), {}};
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            const Point point{x, y};
            const I gx = g.gx.at(point), gy = g.gy.at(point), ax = std::abs(gx), ay = std::abs(gy);
            const I direction = 29 * ay <= 12 * ax ? 0 : 29 * ay >= 70 * ax ? 90 : gx * gy < 0 ? 45 : 135;
            out.direction.at(point) = direction;
            if (x == 0 || y == 0 || x == w - 1 || y == h - 1)
                continue;
            Point a, b;
            if (direction == 0) {
                a = {x - 1, y};
                b = {x + 1, y};
            } else if (direction == 45) {
                a = {x + 1, y - 1};
                b = {x - 1, y + 1};
            } else if (direction == 90) {
                a = {x, y - 1};
                b = {x, y + 1};
            } else {
                a = {x - 1, y - 1};
                b = {x + 1, y + 1};
            }
            const I m = g.magnitude.at(point);
            if (m > g.magnitude.at(a) && m >= g.magnitude.at(b))
                out.nms.at(point) = m;
        }
    Points queue;
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            Point point{x, y};
            const I value = out.nms.at(point);
            if (value >= p.high) {
                ++out.strong;
                out.edges.at(point) = 1;
                queue.push_back(point);
            } else if (value >= p.low)
                ++out.weak;
        }
    for (std::size_t head = 0; head < queue.size(); ++head) {
        const Point point = queue[head];
        for (int dy = -1; dy <= 1; ++dy)
            for (int dx = -1; dx <= 1; ++dx) {
                const Point next{point.x + dx, point.y + dy};
                if (out.edges.inside(next) && !out.edges.at(next) && out.nms.at(next) >= p.low) {
                    out.edges.at(next) = 1;
                    queue.push_back(next);
                }
            }
    }
    Image visited(w, h);
    for (int y = 0; y < h; ++y)
        for (int x = 0; x < w; ++x) {
            const Point first{x, y};
            if (!out.edges.at(first) || visited.at(first))
                continue;
            Points component{first};
            visited.at(first) = 1;
            for (std::size_t head = 0; head < component.size(); ++head) {
                const Point point = component[head];
                for (int dy = -1; dy <= 1; ++dy)
                    for (int dx = -1; dx <= 1; ++dx) {
                        const Point next{point.x + dx, point.y + dy};
                        if (out.edges.inside(next) && out.edges.at(next) && !visited.at(next)) {
                            visited.at(next) = 1;
                            component.push_back(next);
                        }
                    }
            }
            out.components.push_back(std::move(component));
        }
    return out;
}
