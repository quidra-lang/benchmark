#include "knn.hpp"
#include <algorithm>
#include <cmath>

double distance(const Vector& a, const Vector& b, const std::string& metric) {
    double total = 0, first = 0, second = 0;
    for (int j = 0; j < static_cast<int>(a.size()); ++j) {
        double delta = a[j] - b[j];
        if (metric == "squared_euclidean") total += delta * delta;
        else if (metric == "manhattan") total += std::abs(delta);
        else if (metric == "chebyshev") total = std::max(total,std::abs(delta));
        else { total += a[j] * b[j]; first += a[j] * a[j]; second += b[j] * b[j]; }
    }
    if (metric != "cosine") return total;
    double na = std::sqrt(first), nb = std::sqrt(second); return na == 0 || nb == 0 ? 1 : 1 - total / (na * nb);
}
Order neighborOrder(const Vector& query, const std::vector<std::pair<Vector, const Row*>>& references, const std::string& metric) {
    Order order; for (const auto& reference : references) order.push_back({distance(query,reference.first,metric),reference.second});
    std::sort(order.begin(),order.end(),[](const Neighbor& a, const Neighbor& b) { return a.distance != b.distance ? a.distance < b.distance : a.row->id < b.row->id; }); return order;
}
Vote vote(const Order& nearest, const std::string& weighting) {
    struct Tally { std::string label; int count = 0; double distances = 0, weights = 0; };
    std::map<std::string, Tally> tallies; double total = 0;
    for (const Neighbor& neighbor : nearest) {
        double weight = 1 / (neighbor.distance + 0.000000001); Tally& tally = tallies[neighbor.row->label];
        tally.label = neighbor.row->label; ++tally.count; tally.distances += neighbor.distance; tally.weights += weight; total += weight;
    }
    std::vector<Tally> ranked; for (const auto& entry : tallies) ranked.push_back(entry.second);
    std::sort(ranked.begin(),ranked.end(),[&](const Tally& a, const Tally& b) {
        if (weighting == "uniform" && a.count != b.count) return a.count > b.count;
        if (weighting == "distance" && a.weights != b.weights) return a.weights > b.weights;
        return a.distances != b.distances ? a.distances < b.distances : a.label < b.label;
    });
    auto share = [&](const Tally& tally) { return weighting == "uniform" ? static_cast<double>(tally.count) / nearest.size() : tally.weights / total; };
    return {ranked[0].label,ranked.size() == 1 ? "" : ranked[1].label,share(ranked[0]),ranked.size() == 1 ? 0 : share(ranked[1])};
}
double estimate(const Order& nearest, const std::string& weighting) {
    double total = 0, weights = 0;
    for (const Neighbor& neighbor : nearest) {
        if (weighting == "uniform") total += *neighbor.row->target;
        else { double weight = 1 / (neighbor.distance + 0.000000001); total += weight * *neighbor.row->target; weights += weight; }
    }
    return weighting == "uniform" ? total / nearest.size() : total / weights;
}
