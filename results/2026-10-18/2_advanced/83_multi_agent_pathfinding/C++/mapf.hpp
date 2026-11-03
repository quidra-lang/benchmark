#ifndef MAPF_HPP
#define MAPF_HPP
#include <cstdint>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <tuple>
#include <vector>
using Path = std::vector<int>;
using Plan = std::vector<std::shared_ptr<const Path>>;
struct Agent {
    int start, goal;
};
struct Grid {
    int width, height;
    std::vector<std::string> rows;
    std::vector<Agent> agents;
    std::vector<std::vector<int>> distance;
    bool free(int) const;
    std::vector<int> destinations(int) const;
    std::vector<int> distances(int) const;
};
Grid readGrid();
struct Constraint {
    int agent, time, u, v;
    bool edge;
};
struct Prohibitions {
    std::set<std::pair<int, int>> states;
    std::set<std::tuple<int, int, int>> moves;
    std::map<int, int> permanent;
    bool allowed(int, int, int) const;
    int arrival(int) const;
    void reserve(const Path &, int, bool);
};
Prohibitions prohibitions(const std::vector<Constraint> &);
struct Counters {
    int searches = 0, expansions = 0, limit = 0;
    bool aborted = false;
};
Path lowLevel(const Grid &, int, int, int, int, const Prohibitions &, bool, Counters &);
struct Conflict {
    int time, a, b, u, v;
    bool edge;
    Constraint constraint(int) const;
};
int position(const Path &, int);
std::pair<int, int> costs(const Plan &);
std::vector<Conflict> conflicts(const Plan &);
using ConstraintSet = std::vector<std::shared_ptr<const std::vector<Constraint>>>;
struct TreeNode {
    int number, parent, depth, cost;
    Plan paths;
    ConstraintSet constraints;
    std::vector<Conflict> conflicts;
};
bool nodeLess(const std::shared_ptr<TreeNode> &, const std::shared_ptr<TreeNode> &);
struct RunDefinition {
    std::string solver, costFunction, name;
};
struct Delay {
    int agent, start, length;
};
struct Parameters {
    int horizon = 0, highBudget = 0, lowBudget = 0, window = 0, step = 0, frames = 0;
    std::string animate;
    std::vector<std::vector<int>> orders;
    std::vector<RunDefinition> runs;
    std::vector<Delay> delays;
};
struct AgentMetrics {
    int cost = 0, extra = 0, waits = 0, turns = 0, arrival = -1, leave = 0;
    std::string actions;
};
struct PlanMetrics {
    int soc = 0, makespan = 0, sumExtra = 0, maxExtra = 0, waits = 0, turns = 0;
    std::vector<AgentMetrics> agents;
    std::vector<int> traffic, cellWaits, arrivals, hotspots;
};
struct Execution {
    bool deadlock = false;
    int time = 0, soc = 0, makespan = 0, blocked = 0;
    std::vector<int> finish;
};
struct Run {
    RunDefinition definition;
    std::string reason, end;
    Plan paths;
    Counters counter;
    int high = 0, generated = 0, pruned = 0, open = 0;
    int classes[3] = {0, 0, 0};
    std::vector<std::string> specific, trace;
    std::shared_ptr<TreeNode> answer;
    PlanMetrics metrics;
    Execution execution;
};
struct PriorityResult {
    Plan paths;
    int planned, failed;
};
PriorityResult prioritized(const Grid &, const Parameters &, const std::vector<int> &, int, Run &);
std::vector<std::string> readLines(const std::string &);
std::vector<std::string> words(const std::string &);
std::string join(const std::vector<std::string> &, const std::string &);
std::string cell(const Grid &, int);
std::string conflictText(const Grid &, const Conflict &);
char action(const Grid &, int, int);
std::string actions(const Grid &, const Path &);
std::string fraction(int, int);
std::string integers(const std::vector<int> &);
void writeLines(const std::string &, const std::vector<std::string> &);
#endif
