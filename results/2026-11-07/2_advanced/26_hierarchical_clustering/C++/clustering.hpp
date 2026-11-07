#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Values = std::vector<double>;
using Matrix = std::vector<Values>;
using Indices = std::vector<int>;
using Lines = std::vector<std::string>;
using Table = std::vector<std::vector<Integer>>;
template<class... Parts> std::string text(const Parts&... parts) { std::ostringstream stream; (stream << ... << parts); return stream.str(); }
template<class... Parts> void add(Lines& lines, const Parts&... parts) { lines.push_back(text(parts...)); }
struct Settings {
    std::string distance, standardize, compareLinkage, inconsistencyDepthText;
    Lines linkages;
    Values cutHeights;
    Indices cutCounts;
    Integer inconsistencyDepth, seed;
    int inconsistencyCount, gapMaxK, listSize, width, replicates, percent, refineIterations;
};
struct Dataset { Lines features, ids, labels; Matrix raw; Settings settings; };
Dataset readDataset();
void writeLines(const std::string& name, const Lines& lines);
double sequentialSum(const Values& values);
double squaredDistance(const Values& first, const Values& second);
std::pair<Values, Values> featureStatistics(const Matrix& rows);
Matrix standardize(const Matrix& rows, const Values& means, const Values& deviations);
double distance(const Values& first, const Values& second, const std::string& kind);
Matrix distanceMatrix(const Matrix& vectors, const std::string& kind);
struct Merge { int a, b; double height; int size; };
struct Edge { int parent, child; double weight; };
std::vector<Merge> agglomerate(const Matrix& delta, const std::string& method);
std::vector<Edge> minimumSpanningTree(const Matrix& delta);
std::vector<std::pair<int, int>> orderedChildren(const std::vector<Merge>& merges, int count);
Indices leafOrder(const std::vector<std::pair<int, int>>& children, int count);
int columnPosition(double height, double maximum, int width);
Lines dendrogramRows(const std::vector<Merge>& merges, const std::vector<std::pair<int, int>>& children, const Indices& order, const Lines& ids, const Lines& labels, double maximum, const Indices& cuts, int width);
double correlation(const Values& first, const Values& second);
Table contingencyTable(const Indices& first, const Indices& second, int rows, int columns);
struct Fraction {
    Integer numerator = 0, denominator = 1;
    Fraction(Integer a = 0, Integer b = 1);
    double value() const;
    bool operator>(const Fraction& other) const;
};
Fraction adjustedRandIndex(const Table& table);
Values silhouetteValues(const Indices& partition, int groups, const Matrix& delta);
