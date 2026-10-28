#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
using Vector = std::vector<double>;
using Matrix = std::vector<Vector>;
using Ints = std::vector<int>;
using Lines = std::vector<std::string>;
struct Rating {
    int user = 0, item = 0, rating = 0;
    std::int64_t time = 0;
};
struct Item {
    int id;
    std::string title, genre_list;
    Lines genres;
};
struct Params {
    int neighbors = 0, shrinkage = 0, factors = 0, epochs = 0, iterations = 0, top = 0, buckets = 0, list = 0;
    double minimum = 0, item_reg = 0, user_reg = 0, rate = 0, regularization = 0, als_reg = 0;
    std::int64_t seed = 0;
    Ints cutoffs, grid, user_groups, item_groups, users, items;
};
struct Data {
    std::vector<Rating> train, test;
    std::vector<Item> catalog, items;
    Ints users, user_count, item_count, user_sum, item_sum;
    Vector user_mean, item_mean;
    std::vector<Ints> ratings;
    double mean = 0;
    Params params;
};
Data read_input();
struct Similarities {
    std::vector<std::vector<std::optional<double>>> user, item;
    std::vector<Ints> user_common, common, difference;
};
Similarities similarities(const Data &data);
struct Neighbor {
    int index;
    double similarity;
};
std::vector<Neighbor> select_neighbors(std::vector<Neighbor> candidates, int count);
struct Training {
    std::string method;
    int epoch;
    double rmse;
};
struct Factors {
    Matrix p, q, x, y;
    Vector user_bias, item_bias;
    std::vector<Training> log;
};
double factor_dot(const Vector &a, const Vector &b);
Vector solve(const Matrix &a, const Vector &w);
Factors train_factors(const Data &data, const Vector &user_bias, const Vector &item_bias);
double clip(double value);
double rmse(const Vector &errors);
double mae(const Vector &errors);
double rank_weight(int rank);
struct RankingMetrics {
    int hits = 0;
    double recall = 0, ndcg = 0, ap = 0, rr = 0;
};
RankingMetrics ranking_metrics(const Ints &list, const std::set<int> &relevant, int length);
std::string real(double value);
std::string optional_real(std::optional<double> value);
void write_lines(const std::string &name, const Lines &lines);
