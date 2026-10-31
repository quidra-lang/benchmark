#include "tracker.hpp"
double squared_distance(Position a, Position b) {
    double x = a[0] - b[0], y = a[1] - b[1];
    return x * x + y * y;
}
double distance(Position a, Position b) { return std::sqrt(squared_distance(a, b)); }
double ospa(const std::vector<Position> &a, const std::vector<Position> &b, double cutoff) {
    if (a.empty() && b.empty())
        return 0;
    if (a.empty() || b.empty())
        return cutoff;
    const std::vector<Position> &small = a.size() <= b.size() ? a : b,
                                &large = a.size() <= b.size() ? b : a;
    Matrix costs = zeros(int(small.size()), int(large.size()));
    for (int i = 0; i < int(small.size()); ++i)
        for (int j = 0; j < int(large.size()); ++j) {
            double value = std::min(cutoff, distance(small[i], large[j]));
            costs[i][j] = value * value;
        }
    double sum = 0;
    for (Pair pair : minimum_matching(costs))
        sum += costs[pair.first][pair.second];
    return std::sqrt((sum + cutoff * cutoff * (large.size() - small.size())) / large.size());
}
Continuity continuity(const std::vector<int> &labels) {
    Continuity out;
    int previous = -1, groups = 0;
    bool adjacent = false;
    for (int i = 0; i < int(labels.size()); ++i) {
        int label = labels[i];
        if (label < 0) {
            adjacent = false;
            continue;
        }
        ++out.covered;
        if (out.delay < 0)
            out.delay = i;
        if (!adjacent)
            ++groups;
        if (previous >= 0 && previous != label)
            ++out.swaps;
        previous = label;
        adjacent = true;
    }
    out.breaks = std::max(0, groups - 1);
    return out;
}
std::string real(double value) {
    std::ostringstream out;
    out << std::fixed << std::setprecision(4) << value;
    std::string text = out.str();
    if (text == "-0.0000")
        text = "0.0000";
    return text;
}
