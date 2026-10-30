#pragma once
#include <algorithm>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <optional>
#include <queue>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>
using Value = std::int64_t;
using Lines = std::vector<std::string>;
using Plan = std::vector<int>;
using Layers = std::vector<Plan>;
constexpr Value infinity = Value{1} << 60;
struct State {
    std::array<std::uint64_t, 4> words{};
    bool has(int fact) const;
    void put(int fact);
    State united(State other) const;
    State without(State other) const;
    State intersected(State other) const;
    bool contains(State other) const;
    bool intersects(State other) const;
    Plan numbers() const;
    bool operator<(const State &other) const { return words < other.words; }
    bool operator==(const State &other) const { return words == other.words; }
    bool operator!=(const State &other) const { return !(*this == other); }
};
struct Typed {
    std::string name, type;
};
struct Atom {
    std::string predicate;
    Lines terms;
    std::string text() const;
};
struct Literal {
    Atom atom;
    bool negative = false;
    std::string text() const;
};
struct Predicate {
    std::string name;
    Lines types;
};
struct Schema {
    std::string name;
    std::vector<Typed> parameters;
    std::vector<Literal> conditions, effects;
    Value cost = 1;
};
struct Domain {
    std::string name;
    Lines types{"object"}, diagnostics;
    std::map<std::string, std::string> parents;
    std::vector<Predicate> predicates;
    std::map<std::string, int> predicateIndex;
    std::vector<Schema> actions;
    std::set<std::string> fluent;
    bool subtype(std::string type, const std::string &expected) const;
    void classify();
};
struct Problem {
    std::string name;
    std::vector<Typed> objects;
    std::vector<Atom> initial, goals;
    Lines diagnostics;
};
using AtomSet = std::map<std::string, Atom>;
struct GroundAction {
    int schema = 0;
    Lines arguments;
    Value cost = 1;
    State pre, neg, add, del;
    std::string text(const Domain &domain) const;
};
struct SchemaCount {
    int assignments = 1, candidates = 0, reachable = 0;
};
struct Heuristic {
    Value goalcount = 0, hmax = 0, hadd = 0, ff = 0, lmcount = 0;
    Plan relaxed, helpful;
    State landmarks;
    Value value(const std::string &name) const;
};
struct GroundProblem {
    const Domain *domain = nullptr;
    const Problem *problem = nullptr;
    std::vector<Atom> facts, unreachable;
    std::map<std::string, int> factIndex;
    std::vector<GroundAction> actions;
    State initial, goal;
    std::vector<SchemaCount> counts;
    int candidateCount = 0, staticFacts = 0;
    std::map<State, Heuristic> cache;
    const Heuristic &heuristics(State state);
};
struct SearchSettings {
    std::string algorithm, heuristic;
    std::string tag() const { return algorithm + " " + heuristic; }
};
struct Settings {
    int budget = 0, weight = 0, levelLimit = 0;
    std::vector<SearchSettings> runs;
    SearchSettings repair;
};
struct Step {
    std::string name;
    Lines arguments;
    std::string text() const { return Atom{name, arguments}.text(); }
};
struct CandidatePlan {
    std::string problem, label;
    std::vector<Step> steps;
};
struct SearchResult {
    std::string status;
    Plan plan;
    Value expanded = 0, generated = 0;
};
struct GraphElement {
    int action = -1, fact = -1;
    State pre, add, del;
};
struct GraphPlanResult {
    std::string status;
    Plan plan;
    Layers layers;
    Value searched = 0, memoHits = 0, tried = 0;
    Lines logs;
};
Lines readLines(const std::string &path);
Lines splitWords(const std::string &text);
std::string join(const Lines &items, const std::string &separator);
std::string intList(const Plan &items, const std::string &separator);
Domain readDomain();
std::vector<Problem> readProblems();
Atom substitute(const Atom &atom, const std::map<std::string, std::string> &assignment);
std::map<std::string, std::string> objectTypes(const Problem &problem);
Lines objectsOfType(const Domain &domain, const Problem &problem, const std::string &type);
GroundProblem ground(const Domain &domain, const Problem &problem);
bool applicable(const GroundAction &action, State state);
State apply(const GroundAction &action, State state);
SearchResult search(GroundProblem &problem, State start, const SearchSettings &settings, int budget,
                    int weight);
GraphPlanResult graphPlan(const std::vector<GraphElement> &actions, State initial, State goal,
                          int limit);
