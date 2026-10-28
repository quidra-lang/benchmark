#ifndef SAT_HPP
#define SAT_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Lines = std::vector<std::string>;
using Clause = std::vector<int>;
using Model = std::vector<int>;
struct Formula {
    int variables = 0;
    std::vector<Clause> clauses;
};
Lines read_lines(const std::string &path);
Lines words(const std::string &line);
bool well_number(const std::string &text, int maximum_length = 6);
struct CnfInput {
    Formula formula;
    std::string error;
};
CnfInput read_cnf(const std::string &name);
Lines model_lines(const Model &model);
struct Graph {
    std::string name, error;
    int vertices = 0;
    std::vector<std::pair<int, int>> edges;
    std::vector<int> degrees;
};
Formula queens_formula(int n);
Formula pigeon_formula(int pigeons, int holes);
Formula color_formula(const Graph &graph, int colors);
std::vector<int> decode(const Model &model, int rows, int columns);
struct WorkingClause {
    int id;
    Clause literals;
};
struct Preprocess {
    std::vector<WorkingClause> clauses;
    Model fixed;
    bool pure = false, conflict = false;
    int empty_clause = 0, tautologies = 0, duplicate_literals = 0, unit_fixed = 0, unit_removed = 0,
        subsumed = 0, pure_fixed = 0, pure_removed = 0;
    std::array<std::vector<int>, 4> removed;
    int removed_count() const;
};
Preprocess preprocess(const Formula &formula, bool pure);
struct Statistics {
    int decisions = 0, propagations = 0, conflicts = 0, max_depth = 0;
    void add(const Statistics &other);
};
struct Round {
    bool sat = false;
    Model values;
    Statistics stats;
    Lines events;
};
Round dpll_round(int variables, std::vector<Clause> clauses);
std::string number(int value);
std::string number_list(const std::vector<int> &values);
std::string frequency_list(const std::map<int, int> &counts);
std::string items(const std::string &prefix, const std::vector<std::pair<std::string, std::string>> &values);
Lines board_lines(const std::vector<int> &columns);
void write_paragraphs(const std::string &name, const std::vector<Lines> &paragraphs);
void write_lines(const std::string &name, const Lines &lines);
#endif
