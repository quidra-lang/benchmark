#pragma once
#include <map>
#include <optional>
#include <string>
#include <vector>

using Lines = std::vector<std::string>;
using Indices = std::vector<int>;
using Vector = std::vector<double>;
struct Row { std::string id; Vector values; std::string label; std::optional<double> target; };
using Rows = std::vector<const Row*>;
struct Settings { Lines scalings, metrics, weightings; Indices ks, curve; Vector bins; int folds, editK, top; };
struct Dataset { Lines features; std::vector<Row> train, test; Settings settings; };
Dataset readDataset();
struct Scaling {
    Vector centers, scales;
    Vector transform(const Row& row, const Indices& features) const;
};
Scaling computeScaling(const Rows& rows, const std::string& method);
struct Neighbor { double distance; const Row* row; };
using Order = std::vector<Neighbor>;
double distance(const Vector& first, const Vector& second, const std::string& metric);
Order neighborOrder(const Vector& query, const std::vector<std::pair<Vector, const Row*>>& references, const std::string& metric);
struct Vote { std::string label, runner; double share, runnerShare; };
Vote vote(const Order& nearest, const std::string& weighting);
double estimate(const Order& nearest, const std::string& weighting);
struct Model {
    int k;
    std::string metric, weighting, scaling;
    std::string notation() const;
};
struct Prediction { Vote result; double estimate; Order neighbors; };
std::vector<Indices> stratifiedFolds(const Rows& rows, int count);
Rows without(const Rows& rows, const Indices& excluded);
Rows selected(const Rows& rows, const Indices& indices);
std::vector<Order> neighborOrders(const Rows& training, const Rows& queries, const std::string& scaling, const std::string& metric, const Indices& features);
Prediction predictionFromOrder(const Order& order, int k, const std::string& weighting);
std::vector<Prediction> predictRows(const Model& model, const Rows& training, const Rows& queries, const Indices& features);
double rmse(const Vector& errors);
double mae(const Vector& errors);
double rSquared(const Vector& errors, const Vector& targets);
std::string fixed(double value, int places = 4);
double fourDecimal(double value);
std::string ratio(int numerator, int denominator);
std::string fraction(int numerator, int denominator);
void writeLines(const std::string& name, const Lines& lines);
