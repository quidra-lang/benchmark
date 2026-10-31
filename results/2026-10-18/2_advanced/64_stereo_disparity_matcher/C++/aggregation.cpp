#include "stereo.hpp"
const std::array<std::pair<int, int>, 8> directions{
    {{1, 0}, {-1, 0}, {0, 1}, {0, -1}, {1, 1}, {-1, -1}, {-1, 1}, {1, -1}}};
Volume path_costs(const Volume &base, const PGM &left, std::pair<int, int> direction,
                  const Params &p) {
    int width = left.width, height = left.height, rx = direction.first, ry = direction.second,
        count = p.maximum - p.minimum + 1;
    Volume out(base.size(), Image(count));
    for (int iy = 0; iy < height; ++iy) {
        int y = ry >= 0 ? iy : height - 1 - iy;
        for (int ix = 0; ix < width; ++ix) {
            int x = rx >= 0 ? ix : width - 1 - ix, index = y * width + x, qx = x - rx, qy = y - ry;
            if (qx < 0 || qx >= width || qy < 0 || qy >= height) {
                out[index] = base[index];
                continue;
            }
            int previous = qy * width + qx;
            I minimum = *std::min_element(out[previous].begin(), out[previous].end()),
              penalty = std::max(
                  p.p1, p.p2 * p.gamma /
                            (p.gamma + std::llabs(left.pixels[index] - left.pixels[previous])));
            for (int d = 0; d < count; ++d) {
                I best = std::min(out[previous][d], minimum + penalty);
                if (d > 0)
                    best = std::min(best, out[previous][d - 1] + p.p1);
                if (d + 1 < count)
                    best = std::min(best, out[previous][d + 1] + p.p1);
                out[index][d] = base[index][d] + best - minimum;
            }
        }
    }
    return out;
}
std::vector<Volume> cumulative_costs(const Volume &base, const PGM &left, const Params &p) {
    Volume total(base.size(), Image(base[0].size(), 0));
    std::vector<Volume> out;
    for (int i = 0; i < p.paths; ++i) {
        Volume costs = path_costs(base, left, directions[i], p);
        for (int index = 0; index < int(base.size()); ++index)
            for (int d = 0; d < int(base[0].size()); ++d)
                total[index][d] += costs[index][d];
        out.push_back(total);
    }
    return out;
}
