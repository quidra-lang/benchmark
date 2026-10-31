#include "detector.hpp"
Points circle_points(I radius) {
    std::set<Point> points;
    I a = radius, b = 0, error = 1 - radius;
    while (a >= b) {
        for (Point point : Points{{a, b}, {b, a}, {-b, a}, {-a, b}, {-a, -b}, {-b, -a}, {b, -a}, {a, -b}})
            points.insert(point);
        ++b;
        if (error < 0)
            error += 2 * b + 1;
        else {
            --a;
            error += 2 * (b - a) + 1;
        }
    }
    return {points.begin(), points.end()};
}
CircleVotes circle_votes(const Image &edges, const Params &p) {
    CircleVotes out;
    for (I radius = p.r_min; radius <= p.r_max; ++radius) {
        out.offsets.push_back(circle_points(radius));
        out.votes.emplace_back(edges.data.size());
        auto &votes = out.votes.back();
        for (int y = 0; y < edges.height; ++y)
            for (int x = 0; x < edges.width; ++x)
                if (edges.at({x, y}))
                    for (Point offset : out.offsets.back()) {
                        const Point center{x + offset.x, y + offset.y};
                        if (edges.inside(center))
                            ++votes[center.y * edges.width + center.x];
                    }
    }
    for (int radius = 0; radius < int(out.offsets.size()); ++radius) {
        const I count = out.offsets[radius].size();
        for (int y = 0; y < edges.height; ++y)
            for (int x = 0; x < edges.width; ++x) {
                const I value = out.votes[radius][y * edges.width + x];
                if (100 * value < p.circle_percent * count)
                    continue;
                ++out.candidates;
                bool peak = true;
                for (int rr = std::max(0, radius - 2);
                     rr <= std::min(int(out.offsets.size()) - 1, radius + 2) && peak; ++rr)
                    for (int yy = std::max(0, y - 2); yy <= std::min(edges.height - 1, y + 2) && peak; ++yy)
                        for (int xx = std::max(0, x - 2); xx <= std::min(edges.width - 1, x + 2); ++xx) {
                            if (rr == radius && yy == y && xx == x)
                                continue;
                            const I left = value * I(out.offsets[rr].size()),
                                    right = out.votes[rr][yy * edges.width + xx] * count;
                            const bool earlier = std::tie(rr, yy, xx) < std::tie(radius, y, x);
                            if (left < right || (left == right && earlier)) {
                                peak = false;
                                break;
                            }
                        }
                if (peak)
                    out.peaks.push_back({radius + p.r_min, {x, y}, value, count});
            }
    }
    std::sort(out.peaks.begin(), out.peaks.end(), [](const CirclePeak &a, const CirclePeak &b) {
        const I left = a.votes * b.points, right = b.votes * a.points;
        return left != right
                   ? left > right
                   : std::tie(a.radius, a.center.y, a.center.x) < std::tie(b.radius, b.center.y, b.center.x);
    });
    return out;
}
I rho(Point point, I theta, const Trig &trig, const Params &p) {
    return floor_div(point.x * trig[theta][0] + point.y * trig[theta][1], 16384 * p.rho_step);
}
LineVotes line_votes(const Image &edges, const Trig &trig, const Params &p) {
    LineVotes out{0, 0, 0, {}, {}};
    for (I theta = 0; theta < 180; ++theta)
        for (Point point : Points{
                 {0, 0}, {edges.width - 1, 0}, {0, edges.height - 1}, {edges.width - 1, edges.height - 1}}) {
            const I value = rho(point, theta, trig, p);
            out.low = std::min(out.low, value);
            out.high = std::max(out.high, value);
        }
    out.votes = Image(180, out.high - out.low + 1);
    for (int y = 0; y < edges.height; ++y)
        for (int x = 0; x < edges.width; ++x)
            if (edges.at({x, y}))
                for (I theta = 0; theta < 180; ++theta)
                    ++out.votes.at({theta, rho({x, y}, theta, trig, p) - out.low});
    for (I value : out.votes.data)
        out.maximum = std::max(out.maximum, value);
    for (I theta = 0; theta < 180; ++theta)
        for (I r = out.low; r <= out.high; ++r) {
            const I value = out.votes.at({theta, r - out.low});
            if (value < p.vote_threshold)
                continue;
            bool peak = true;
            for (I t = theta - 2; t <= theta + 2 && peak; ++t)
                for (I rr = r - 2; rr <= r + 2; ++rr) {
                    if (t == theta && rr == r)
                        continue;
                    const I other = t >= 0 && t < 180 && rr >= out.low && rr <= out.high
                                        ? out.votes.at({t, rr - out.low})
                                        : 0;
                    const bool earlier = std::tie(t, rr) < std::tie(theta, r);
                    if (value < other || (value == other && earlier)) {
                        peak = false;
                        break;
                    }
                }
            if (peak)
                out.peaks.push_back({theta, r, value});
        }
    std::sort(out.peaks.begin(), out.peaks.end(), [](const LinePeak &a, const LinePeak &b) {
        return a.votes != b.votes ? a.votes > b.votes : std::tie(a.theta, a.rho) < std::tie(b.theta, b.rho);
    });
    return out;
}
