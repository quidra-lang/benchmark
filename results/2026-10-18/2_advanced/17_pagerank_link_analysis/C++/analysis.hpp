#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <functional>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

using Integer = std::int64_t;
using Integers = std::vector<Integer>;
using Nodes = std::vector<int>;
using Adjacency = std::vector<Nodes>;
using Values = std::vector<double>;
using Lines = std::vector<std::string>;
using Link = std::pair<int, int>;
using Links = std::vector<Link>;
using WeightedEdges = std::vector<std::vector<Link>>;
template<class... Parts> std::string text(const Parts&... parts) { std::ostringstream stream; (stream << ... << parts); return stream.str(); }
template<class... Parts> void add(Lines& lines, const Parts&... parts) { lines.push_back(text(parts...)); }
template<class T> std::string join(const std::vector<T>& values, const std::string& separator = " ") {
    std::ostringstream stream;
    for (std::size_t i = 0; i < values.size(); ++i) { if (i) stream << separator; stream << values[i]; }
    return stream.str();
}
struct Page { int id; std::string host, title; Lines words; };
struct LinkRecord { int line, source, target; };
struct Query { int number; Lines words; Nodes seeds; };
struct Settings {
    double damping;
    int iterations;
    double tolerance;
    Values sweep;
    Nodes trusted;
    int spamTop;
    double spamThreshold;
    int hitsIterations, topK, rootLimit, neighborLimit;
};
struct Input { std::vector<Page> pages; std::vector<LinkRecord> records; std::vector<Query> queries; Settings settings; };
Lines split(const std::string& value, char separator);
Input readInput();
Adjacency strongComponents(const Adjacency& adjacency);
std::vector<bool> reachable(const Adjacency& adjacency, const Nodes& starts);
Nodes bfsDistances(const Adjacency& adjacency, const Nodes& starts);
Nodes weakComponents(const Adjacency& adjacency);
struct PageRankResult { Values values, changes; int converged = 0; };
PageRankResult powerIteration(const WeightedEdges& edges, const Nodes& teleport, double damping, int iterations, double tolerance);
std::pair<Values, Values> hits(int count, const Nodes& nodes, const Links& links, int iterations);
std::string fixed(double value, int places = 6);
Integer scaled(double value, int places = 6);
std::string fraction(Integer numerator, Integer denominator);
void writeLines(const std::string& name, const Lines& lines);
