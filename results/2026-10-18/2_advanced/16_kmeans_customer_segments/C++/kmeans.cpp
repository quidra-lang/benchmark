#include "segments.hpp"

double squaredDistance(const Point& first, const Point& second) {
    double total = 0;
    for (std::size_t i = 0; i < first.size(); ++i) { double difference = first[i] - second[i]; total += difference * difference; }
    return total;
}
std::pair<Labels, Point> assign(const Points& points, const Points& centers) {
    Labels labels;
    Point errors;
    for (const Point& point : points) {
        int best = 0;
        double nearest = squaredDistance(point, centers[0]);
        for (int j = 1; j < static_cast<int>(centers.size()); ++j) {
            double distance = squaredDistance(point, centers[j]);
            if (distance < nearest) { best = j; nearest = distance; }
        }
        labels.push_back(best);
        errors.push_back(nearest);
    }
    return {labels, errors};
}
Point meanPoint(const Points& points) {
    Point totals(points.front().size());
    for (const Point& point : points) for (std::size_t f = 0; f < totals.size(); ++f) totals[f] += point[f];
    for (double& total : totals) total /= points.size();
    return totals;
}
Labels clusterSizes(const Labels& labels, int k) { Labels result(k); for (int label : labels) ++result[label]; return result; }
Point clusterCenter(const Points& points, const Labels& labels, int center) {
    Points chosen;
    for (std::size_t i = 0; i < points.size(); ++i) if (labels[i] == center) chosen.push_back(points[i]);
    return meanPoint(chosen);
}
Points clusterCenters(const Points& points, const Labels& labels, int k) {
    Points result;
    for (int j = 0; j < k; ++j) result.push_back(clusterCenter(points, labels, j));
    return result;
}
static int refill(Labels& labels, Point& errors, int k) {
    Labels sizes = clusterSizes(labels, k);
    int reseeds = 0;
    for (int j = 0; j < k; ++j) {
        if (sizes[j]) continue;
        std::size_t chosen = labels.size();
        for (std::size_t i = 0; i < labels.size(); ++i) if (sizes[labels[i]] >= 2 && (chosen == labels.size() || errors[i] > errors[chosen])) chosen = i;
        --sizes[labels[chosen]];
        ++sizes[j];
        labels[chosen] = j;
        errors[chosen] = 0;
        ++reseeds;
    }
    return reseeds;
}
LloydResult lloyd(const Points& points, const Points& initial, int limit) {
    std::pair<Labels, Point> assignment = assign(points, initial);
    Labels labels = std::move(assignment.first);
    Point errors = std::move(assignment.second);
    int iterations = 0, reseeds = 0, k = static_cast<int>(initial.size());
    bool converged = false;
    while (iterations < limit && !converged) {
        reseeds += refill(labels, errors, k);
        Points centers = clusterCenters(points, labels, k);
        ++iterations;
        assignment = assign(points, centers);
        converged = assignment.first == labels;
        labels = std::move(assignment.first);
        errors = std::move(assignment.second);
    }
    reseeds += refill(labels, errors, k);
    return {labels, clusterCenters(points, labels, k), iterations, converged, reseeds};
}
double sse(const Points& points, const Labels& labels, const Points& centers) {
    double total = 0;
    for (std::size_t i = 0; i < points.size(); ++i) total += squaredDistance(points[i], centers[labels[i]]);
    return total;
}
