#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Lines = std::vector<std::string>;
using Point = std::vector<double>;
using Points = std::vector<Point>;
using Indices = std::vector<std::size_t>;
using Labels = std::vector<int>;
template<class... Parts> std::string text(const Parts&... parts) {
    std::ostringstream stream;
    (stream << ... << parts);
    return stream.str();
}
template<class... Parts> void add(Lines& lines, const Parts&... parts) { lines.push_back(text(parts...)); }
template<class T> std::string join(const std::vector<T>& values, const std::string& separator = " ") {
    std::ostringstream stream;
    for (std::size_t i = 0; i < values.size(); ++i) { if (i) stream << separator; stream << values[i]; }
    return stream.str();
}
extern const Lines featureNames;
extern const std::array<bool, 6> sqrtFeatures;
struct Params {
    int referenceDay, snapshotDay, outcomeDays, kMin, kMax;
    Lines methods;
    int restarts, maxIterations;
    Integer seed;
    int subsamples, subsamplePercent;
    double outlierSd;
    int overdueFactor;
    std::vector<Integer> orderBins;
    int topCategories, topCustomers, periodDays, periods;
};
struct Transaction { std::string customer; int day; std::string orderId, category; Integer amount; };
struct TransactionData { int rowCount = 0, duplicates = 0, free = 0; std::vector<Transaction> validRows; std::set<std::string> customers; };
struct Order { std::string id, customer; int day; Integer net = 0; std::vector<const Transaction*> rows; };
using CustomerOrders = std::map<std::string, std::vector<const Order*>>;
Lines readLines(const std::string& path);
Lines split(const std::string& value, char separator);
Params readParams(const std::string& path);
TransactionData readTransactions(const std::string& path);
std::vector<Order> groupOrders(const std::vector<Transaction>& rows, int first, int last);
CustomerOrders ordersByCustomer(const std::vector<Order>& orders, bool validOnly = false);
struct Customer {
    std::string id;
    std::vector<const Order*> orders;
    int recency, frequency, categories, tenure;
    Integer spend;
    double basket;
    std::map<std::string, Integer> categorySpend;
    Customer(std::string id, std::vector<const Order*> orders, int day);
    Point values() const;
    Point transformed() const;
};
std::vector<Customer> eligibleCustomers(const std::vector<Order>& orders, int day);
double orderedSum(const Point& values);
double mean(const Point& values);
double sampleSd(const Point& values);
std::pair<Point, Point> standardization(const Points& rows);
Point standardize(const Point& values, const Point& means, const Point& deviations);
double correlation(const Points& points, std::size_t first, std::size_t second);
double squaredDistance(const Point& first, const Point& second);
std::pair<Labels, Point> assign(const Points& points, const Points& centers);
Point meanPoint(const Points& points);
Labels clusterSizes(const Labels& labels, int k);
Point clusterCenter(const Points& points, const Labels& labels, int center);
Points clusterCenters(const Points& points, const Labels& labels, int k);
struct LloydResult { Labels labels; Points centers; int iterations; bool converged; int reseeds; };
LloydResult lloyd(const Points& points, const Points& initial, int limit);
double sse(const Points& points, const Labels& labels, const Points& centers);
Points distanceTable(const Points& points);
Point silhouettes(const Points& table, const Labels& labels, const Labels& sizes);
double calinskiHarabasz(const Points& points, const Points& centers, const Labels& sizes, double within);
double daviesBouldin(const Points& points, const Labels& labels, const Points& centers, const Labels& sizes);
double elbow(int k, int first, int last, double within, double withinFirst, double withinLast);
double hartigan(double within, double next, int count, int k);
double adjustedRandIndex(const Labels& first, const Labels& second);
struct NamingCondition { std::size_t feature; bool greater; double threshold; };
struct NamingRule { std::string name; std::vector<NamingCondition> conditions; };
std::vector<NamingRule> readRules(const std::string& path);
int ruleNumber(const std::vector<NamingRule>& rules, const Point& center);
Point originalScale(const Point& center, const Point& means, const Point& deviations);
std::string realText(double value);
std::string reals(const Point& values);
Integer fourDecimal(double value);
std::string amount(Integer cents);
void writeLines(const std::string& path, const Lines& lines);
