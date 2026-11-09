#include "airspace.hpp"
std::optional<Loss> loss_interval(Point p, Point w, double first, double last, double horizontal,
                                  double vertical) {
    double qa = w[0] * w[0] + w[1] * w[1], qb = 2 * (p[0] * w[0] + p[1] * w[1]),
           qc = (p[0] * p[0] + p[1] * p[1]) - horizontal * horizontal, low = first, high = last;
    if (qa < 1e-12) {
        if (qc >= 0)
            return {};
    } else {
        double discriminant = qb * qb - 4 * qa * qc;
        if (discriminant <= 0)
            return {};
        double root = std::sqrt(discriminant);
        low = std::max(low, first + (-qb - root) / (2 * qa));
        high = std::min(high, first + (-qb + root) / (2 * qa));
    }
    if (w[2] == 0) {
        if (std::abs(p[2]) >= vertical)
            return {};
    } else {
        double r1 = (-vertical - p[2]) / w[2], r2 = (vertical - p[2]) / w[2];
        low = std::max(low, first + std::min(r1, r2));
        high = std::min(high, first + std::max(r1, r2));
    }
    if (high - low <= 1e-6)
        return {};
    double time = qa >= 1e-12 ? first + (-qb / (2 * qa)) : first;
    time = std::min(std::max(time, low), high);
    double tau = time - first, ex = p[0] + w[0] * tau, ey = p[1] + w[1] * tau;
    return Loss{low, high, time, std::sqrt(ex * ex + ey * ey), std::abs(p[2] + w[2] * tau)};
}
bool conflict_before(const Conflict &a, const Conflict &b) {
    return std::tie(a.start, a.pair) < std::tie(b.start, b.pair);
}
std::vector<Conflict> pair_conflicts(int first, const Trajectory &ta, int second,
                                     const Trajectory &tb, const Params &params) {
    std::vector<Piece> pieces;
    for (int i = 0; i < int(ta.segments.size()); ++i)
        for (int j = 0; j < int(tb.segments.size()); ++j) {
            const Segment &a = ta.segments[i], &b = tb.segments[j];
            double t1 = std::max(a.start_time, b.start_time), t2 = std::min(a.end_time, b.end_time);
            if (t1 >= t2)
                continue;
            Point pa = position(a, t1), pb = position(b, t1), relative, velocity;
            for (int axis = 0; axis < 3; ++axis) {
                relative[axis] = pa[axis] - pb[axis];
                velocity[axis] = a.velocity[axis] - b.velocity[axis];
            }
            auto interval = loss_interval(relative, velocity, t1, t2, double(params.horizontal),
                                          double(params.vertical));
            if (interval)
                pieces.push_back({i, j, *interval});
        }
    std::stable_sort(pieces.begin(), pieces.end(),
                     [](const Piece &a, const Piece &b) { return a.loss.low < b.loss.low; });
    std::vector<Conflict> out;
    for (const Piece &piece : pieces) {
        if (out.empty() || piece.loss.low - out.back().end > 1e-6)
            out.push_back({{first, second}, piece.loss.low, piece.loss.high, {piece}, piece});
        else {
            Conflict &conflict = out.back();
            conflict.pieces.push_back(piece);
            conflict.end = piece.loss.high;
            if (piece.loss.distance < conflict.closest.loss.distance - 1e-9)
                conflict.closest = piece;
        }
    }
    return out;
}
std::vector<Conflict> all_conflicts(const std::vector<Trajectory> &trajectories,
                                    const Params &params) {
    std::vector<Conflict> out;
    for (int a = 0; a < int(trajectories.size()); ++a)
        for (int b = a + 1; b < int(trajectories.size()); ++b) {
            auto pair = pair_conflicts(a, trajectories[a], b, trajectories[b], params);
            out.insert(out.end(), pair.begin(), pair.end());
        }
    std::stable_sort(out.begin(), out.end(), conflict_before);
    return out;
}
