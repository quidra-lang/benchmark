#include "detector.hpp"
Corners corners(const Gradient &g, const Params &p) {
    Image response(g.gx.width, g.gx.height);
    const I half = (p.harris_window - 1) / 2;
    for (int y = 0; y < response.height; ++y)
        for (int x = 0; x < response.width; ++x) {
            I xx = 0, yy = 0, xy = 0;
            for (I j = -half; j <= half; ++j)
                for (I i = -half; i <= half; ++i) {
                    const I gx = clamped(g.gx, x + i, y + j), gy = clamped(g.gy, x + i, y + j);
                    xx += gx * gx;
                    yy += gy * gy;
                    xy += gx * gy;
                }
            response.at({x, y}) = xx * yy - xy * xy - floor_div((xx + yy) * (xx + yy), 25);
        }
    Corners out;
    for (int y = 0; y < response.height; ++y)
        for (int x = 0; x < response.width; ++x) {
            const Point point{x, y};
            const I value = response.at(point);
            if (value < p.harris_threshold)
                continue;
            bool peak = true;
            for (I dy = -1; dy <= 1 && peak; ++dy)
                for (I dx = -1; dx <= 1; ++dx) {
                    const Point other{x + dx, y + dy};
                    if (other == point || !response.inside(other))
                        continue;
                    const I comparison = response.at(other);
                    if (value < comparison || (value == comparison && other < point)) {
                        peak = false;
                        break;
                    }
                }
            if (peak)
                out.values.push_back({point, value});
        }
    out.candidates = out.values.size();
    std::sort(out.values.begin(), out.values.end(), [](const Corner &a, const Corner &b) {
        return a.response != b.response ? a.response > b.response : a.point < b.point;
    });
    if (out.values.size() > std::size_t(p.corner_count))
        out.values.resize(p.corner_count);
    return out;
}
