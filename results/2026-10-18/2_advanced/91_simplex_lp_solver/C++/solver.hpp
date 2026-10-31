#pragma once
#include <algorithm>
#include <array>
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
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>
using Lines = std::vector<std::string>;
template <class... Parts> std::string text(const Parts &...parts) {
    std::ostringstream out;
    (out << ... << parts);
    return out.str();
}
std::string join(const Lines &items, const std::string &separator = " ");
void append(Lines &to, const Lines &from);
struct Rational {
    std::int64_t numerator = 0, denominator = 1;
    Rational() = default;
    Rational(std::int64_t numerator, std::int64_t denominator = 1);
    Rational operator+(Rational other) const;
    Rational operator-(Rational other) const;
    Rational operator*(Rational other) const;
    Rational operator/(Rational other) const;
    Rational operator-() const;
    int compare(Rational other) const;
    Rational abs() const;
    std::int64_t floor() const;
    std::int64_t ceil() const;
    bool whole() const { return denominator == 1; }
    std::string str() const;
    std::string approx() const;
};
std::ostream &operator<<(std::ostream &out, const Rational &value);
using Values = std::vector<Rational>;
using Bound = std::optional<Rational>;
using Bounds = std::vector<Bound>;
std::optional<Rational> readNumber(const std::string &word, bool signedNumber);
std::string boundText(const Bound &bound, bool lower);
struct ModelError {
    int line;
    std::string message;
};
struct Term {
    std::string name;
    Rational coefficient;
};
using Terms = std::vector<Term>;
struct Constraint {
    std::string name, comparison;
    int line = 0;
    Terms terms;
    Rational rhs;
    Values coefficients;
};
enum class BoundKind { Lower, Upper, Both };
struct BoundLine {
    int line;
    std::string name;
    BoundKind kind;
    Bound lower, upper;
};
struct Declaration {
    int line;
    Lines names;
};
struct RawModel {
    std::string name, direction;
    Terms objective;
    std::vector<Constraint> constraints;
    std::vector<BoundLine> bounds;
    std::vector<Declaration> integers, binaries;
    std::optional<ModelError> error;
};
struct Settings {
    int level = 0, limit = 1;
    std::map<std::string, int> logs, limits;
};
std::vector<RawModel> readModels();
Settings readSettings();
struct Model {
    std::string name, direction;
    Lines variables;
    Values cost;
    std::vector<Constraint> constraints;
    Bounds lower, upper;
    std::vector<bool> integer;
    std::optional<ModelError> error;
};
int integerCount(const Model &model);
struct Tableau {
    std::vector<Values> values;
    Values beta;
    std::vector<int> basis;
    std::pair<Values, Rational> reduced(const Values &cost) const;
    void pivot(int row, int column);
    Lines display(const std::string &heading, const Lines &columns, const Lines &rows,
                  const Values &cost, Rational constant, int sign) const;
};
struct PhaseResult {
    int iterations = 0, entering = -1;
    Lines lines;
};
PhaseResult phase(Tableau &tableau, const Values &cost, const std::vector<bool> &candidates,
                  const Lines &columns, const Lines &rows,
                  const std::function<Rational(Rational)> &objective);
enum class MapKind { Shift, Reflect, Split };
struct VariableMap {
    MapKind kind = MapKind::Shift;
    Rational offset;
    std::vector<int> columns;
    int upperRow = -1;
};
struct Standard {
    Lines columns, rows, comparisons;
    std::vector<int> columnVariable, directions, sigma, initial, slack;
    std::vector<bool> artificial;
    Values costs1, costs2;
    std::vector<VariableMap> maps;
    Rational constant;
    int sign = 1;
    Tableau tableau;
    Values originalValues(const Values &columns, bool direction) const;
    Values solution() const;
};
struct LPResult {
    std::string status;
    Rational objective, w, rate;
    Standard standard;
    Values solution, farkas, ray;
    int phase1 = 0, phase2 = 0, drives = 0, redundant = 0;
    Lines log;
    int pivots() const { return phase1 + phase2 + drives; }
};
using Solve = std::function<LPResult(const Bounds &, const Bounds &, int)>;
struct ModelResult {
    std::string status;
    Rational objective;
    bool hasSolution = false;
    Values solution;
    std::vector<LPResult> solves;
    Lines tree;
};
ModelResult branchBound(const Model &model, int limit, const Solve &solve);
