#include "segments.hpp"

Points distanceTable(const Points& points) {
    Points table(points.size(), Point(points.size()));
    for (std::size_t i = 0; i < points.size(); ++i) for (std::size_t j = i + 1; j < points.size(); ++j) table[i][j] = table[j][i] = std::sqrt(squaredDistance(points[i], points[j]));
    return table;
}
Point silhouettes(const Points& table, const Labels& labels, const Labels& sizes) {
    Point values;
    for (std::size_t i = 0; i < labels.size(); ++i) {
        int own = labels[i];
        if (sizes[own] == 1) { values.push_back(0); continue; }
        Point totals(sizes.size());
        for (std::size_t j = 0; j < labels.size(); ++j) if (i != j) totals[labels[j]] += table[i][j];
        double inner = totals[own] / (sizes[own] - 1), outer = 0;
        bool found = false;
        for (int j = 0; j < static_cast<int>(sizes.size()); ++j) if (j != own) {
            double value = totals[j] / sizes[j];
            if (!found || value < outer) { outer = value; found = true; }
        }
        double largest = std::max(inner, outer);
        values.push_back(largest == 0 ? 0 : (outer - inner) / largest);
    }
    return values;
}
double calinskiHarabasz(const Points& points, const Points& centers, const Labels& sizes, double within) {
    Point overall = meanPoint(points);
    double between = 0;
    for (std::size_t j = 0; j < centers.size(); ++j) between += sizes[j] * squaredDistance(centers[j], overall);
    return (between / (centers.size() - 1)) / (within / (points.size() - centers.size()));
}
double daviesBouldin(const Points& points, const Labels& labels, const Points& centers, const Labels& sizes) {
    Point spreads(centers.size());
    for (std::size_t i = 0; i < points.size(); ++i) spreads[labels[i]] += std::sqrt(squaredDistance(points[i], centers[labels[i]]));
    for (std::size_t j = 0; j < centers.size(); ++j) spreads[j] /= sizes[j];
    double total = 0;
    for (std::size_t a = 0; a < centers.size(); ++a) {
        double worst = 0;
        for (std::size_t e = 0; e < centers.size(); ++e) if (e != a) worst = std::max(worst, (spreads[a] + spreads[e]) / std::sqrt(squaredDistance(centers[a], centers[e])));
        total += worst;
    }
    return total / centers.size();
}
double elbow(int k, int first, int last, double within, double withinFirst, double withinLast) {
    double x = static_cast<double>(k - first) / (last - first);
    double y = (within - withinLast) / (withinFirst - withinLast);
    return ((1 - x) - y) / std::sqrt(2.0);
}
double hartigan(double within, double next, int count, int k) { return (within / next - 1) * (count - k - 1); }
static Integer pairs(Integer count) { return count * (count - 1) / 2; }
double adjustedRandIndex(const Labels& first, const Labels& second) {
    std::map<std::pair<int, int>, Integer> joint;
    std::map<int, Integer> a, b;
    for (std::size_t i = 0; i < first.size(); ++i) { ++joint[{first[i], second[i]}]; ++a[first[i]]; ++b[second[i]]; }
    Integer total = pairs(static_cast<Integer>(first.size())), shared = 0, firstPairs = 0, secondPairs = 0;
    for (const std::pair<const std::pair<int, int>, Integer>& entry : joint) shared += pairs(entry.second);
    for (const std::pair<const int, Integer>& entry : a) firstPairs += pairs(entry.second);
    for (const std::pair<const int, Integer>& entry : b) secondPairs += pairs(entry.second);
    Integer numerator = 2 * (total * shared - firstPairs * secondPairs);
    Integer denominator = total * (firstPairs + secondPairs) - 2 * firstPairs * secondPairs;
    return denominator == 0 ? 1 : static_cast<double>(numerator) / denominator;
}
