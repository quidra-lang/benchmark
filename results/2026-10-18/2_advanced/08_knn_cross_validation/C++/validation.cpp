#include "knn.hpp"
#include <algorithm>
#include <cmath>
#include <numeric>
#include <set>
#include <tuple>

std::string Model::notation() const { return "k=" + std::to_string(k) + " metric=" + metric + " weighting=" + weighting + " scaling=" + scaling; }
std::vector<Indices> stratifiedFolds(const Rows& rows, int count) {
    Indices ordered(rows.size()); std::iota(ordered.begin(),ordered.end(),0);
    std::sort(ordered.begin(),ordered.end(),[&](int a, int b) { return std::tie(rows[a]->label,rows[a]->id) < std::tie(rows[b]->label,rows[b]->id); });
    std::vector<Indices> folds(count);
    for (int j = 0; j < static_cast<int>(ordered.size()); ++j) folds[j % count].push_back(ordered[j]);
    for (Indices& fold : folds) std::sort(fold.begin(),fold.end()); return folds;
}
Rows without(const Rows& rows, const Indices& excluded) {
    std::set<int> skipped(excluded.begin(),excluded.end()); Rows result;
    for (int j = 0; j < static_cast<int>(rows.size()); ++j) if (!skipped.count(j)) result.push_back(rows[j]); return result;
}
Rows selected(const Rows& rows, const Indices& indices) { Rows result; for (int index : indices) result.push_back(rows[index]); return result; }
std::vector<Order> neighborOrders(const Rows& training, const Rows& queries, const std::string& method, const std::string& metric, const Indices& features) {
    Scaling scaling = computeScaling(training,method); std::vector<std::pair<Vector, const Row*>> references;
    for (const Row* row : training) references.push_back({scaling.transform(*row,features),row});
    std::vector<Order> orders; for (const Row* query : queries) orders.push_back(neighborOrder(scaling.transform(*query,features),references,metric)); return orders;
}
Prediction predictionFromOrder(const Order& order, int k, const std::string& weighting) {
    Order nearest(order.begin(),order.begin() + std::min<int>(k,order.size())); return {vote(nearest,weighting),estimate(nearest,weighting),nearest};
}
std::vector<Prediction> predictRows(const Model& model, const Rows& training, const Rows& queries, const Indices& features) {
    std::vector<Prediction> result; for (const Order& order : neighborOrders(training,queries,model.scaling,model.metric,features)) result.push_back(predictionFromOrder(order,model.k,model.weighting)); return result;
}
double rmse(const Vector& errors) { double total = 0; for (double error : errors) total += error * error; return std::sqrt(total / errors.size()); }
double mae(const Vector& errors) { double total = 0; for (double error : errors) total += std::abs(error); return total / errors.size(); }
double rSquared(const Vector& errors, const Vector& targets) {
    double total = 0; for (double target : targets) total += target; double mean = total / targets.size();
    double residual = 0; for (double error : errors) residual += error * error;
    double spread = 0; for (double target : targets) spread += (target - mean) * (target - mean); return 1 - residual / spread;
}
