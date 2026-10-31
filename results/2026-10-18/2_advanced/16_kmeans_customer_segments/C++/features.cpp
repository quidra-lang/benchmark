#include "segments.hpp"

const Lines featureNames{"recency", "frequency", "monetary", "basket", "categories", "tenure"};
const std::array<bool, 6> sqrtFeatures{false, true, true, true, false, false};
Customer::Customer(std::string id, std::vector<const Order*> orders, int day)
    : id(std::move(id)), orders(std::move(orders)), recency(0), frequency(static_cast<int>(this->orders.size())), categories(0), tenure(0), spend(0), basket(0) {
    int first = this->orders.front()->day, last = first;
    for (const Order* order : this->orders) {
        first = std::min(first, order->day);
        last = std::max(last, order->day);
        spend += order->net;
        for (const Transaction* row : order->rows) categorySpend[row->category] += row->amount;
    }
    recency = day - last;
    tenure = day - first;
    basket = (static_cast<double>(spend) / 100) / frequency;
    for (const std::pair<const std::string, Integer>& entry : categorySpend) if (entry.second > 0) ++categories;
}
Point Customer::values() const { return {static_cast<double>(recency), static_cast<double>(frequency), static_cast<double>(spend) / 100, basket, static_cast<double>(categories), static_cast<double>(tenure)}; }
Point Customer::transformed() const {
    Point result = values();
    for (std::size_t i = 0; i < result.size(); ++i) if (sqrtFeatures[i]) result[i] = std::sqrt(result[i]);
    return result;
}
std::vector<Customer> eligibleCustomers(const std::vector<Order>& orders, int day) {
    CustomerOrders grouped = ordersByCustomer(orders, true);
    std::vector<Customer> result;
    for (const std::pair<const std::string, std::vector<const Order*>>& entry : grouped) result.emplace_back(entry.first, entry.second, day);
    return result;
}
double orderedSum(const Point& values) { double total = 0; for (double value : values) total += value; return total; }
double mean(const Point& values) { return orderedSum(values) / values.size(); }
double sampleSd(const Point& values) {
    double average = mean(values), total = 0;
    for (double value : values) { double difference = value - average; total += difference * difference; }
    return std::sqrt(total / (values.size() - 1));
}
std::pair<Point, Point> standardization(const Points& rows) {
    Point means, deviations;
    for (std::size_t f = 0; f < featureNames.size(); ++f) {
        Point column;
        for (const Point& row : rows) column.push_back(row[f]);
        means.push_back(mean(column));
        deviations.push_back(sampleSd(column));
    }
    return {means, deviations};
}
Point standardize(const Point& values, const Point& means, const Point& deviations) {
    Point result;
    for (std::size_t i = 0; i < values.size(); ++i) result.push_back(deviations[i] == 0 ? 0 : (values[i] - means[i]) / deviations[i]);
    return result;
}
double correlation(const Points& points, std::size_t first, std::size_t second) {
    double total = 0;
    for (const Point& point : points) total += point[first] * point[second];
    return total / (points.size() - 1);
}
