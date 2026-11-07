#ifndef REINFORCEMENT_HPP
#define REINFORCEMENT_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <numeric>
#include <queue>
#include <sstream>
#include <set>
#include <string>
#include <utility>
#include <vector>
using Integer = std::int64_t;
using Values = std::vector<Integer>;
using Policy = std::vector<int>;
using Table = std::vector<std::array<Integer, 4>>;
using Lines = std::vector<std::string>;
Integer floor_div(Integer a, Integer b);
Integer absolute(Integer value);
Lines read_lines(const std::string &path);
std::string number(Integer value);
std::string join(const Lines &lines, const std::string &separator);
struct World {
    int rows = 0, cols = 0, start = 0;
    std::string cells;
    std::vector<int> states, terminals, index, terminal_index, wind;
    Values rewards;
    std::vector<std::array<int, 4>> moves;
};
World read_world();
int move_cell(const World &w, int cell, int direction);
Integer reward(const World &w, int cell, Integer step_reward);
bool terminal(const World &w, int cell);
std::string ending(const World &w, int cell);
struct Transition {
    int cell;
    Integer weight;
};
struct Model {
    const World *world;
    Integer q, floor_slip, ice_slip, step_reward;
    std::vector<Transition> transitions(int state, int action) const;
};
struct Random {
    Integer value;
    Integer draw();
};
std::pair<int, Integer> step(const Model &model, int state, int action, Random &random);
int first_maximum(const std::array<Integer, 4> &values);
Integer bellman(const Model &model, const Values &values, int state, int action, Integer gamma);
Table action_values(const Model &model, const Values &values, Integer gamma);
Policy greedy(const Table &values);
struct Iteration {
    Values values, deltas;
    Table actions;
    Policy policy;
};
Iteration value_iteration(const Model &model, Integer gamma, Integer theta);
std::pair<Values, int> in_place(const Model &model, Integer gamma, Integer theta);
std::pair<Values, int> evaluate(const Model &model, const Policy &policy, Values values, Integer gamma,
                                Integer theta);
struct Round {
    int sweeps, changed;
    Integer start;
};
struct PolicyIteration {
    Values values;
    Policy policy;
    std::vector<Round> rounds;
};
PolicyIteration policy_iteration(const Model &model, Integer gamma, Integer theta);
int choose(const Table &q, int state, Integer epsilon, Random &random);
Integer next_value(const Table &q, int state, Integer epsilon, bool expected);
void td_update(const Model &model, Table &q, int state, int action, int next, Integer r, Integer gamma,
               Integer alpha, Integer next_value);
struct Sample {
    int state, action;
    Integer reward;
};
struct Dyna {
    std::vector<std::array<bool, 4>> known;
    std::vector<std::array<std::pair<int, Integer>, 4>> entries;
    std::vector<std::pair<int, int>> observed;
    explicit Dyna(std::size_t n) : known(n), entries(n) {
    }
    void record(int state, int action, int next, Integer reward);
    void plan(const Model &model, Table &q, int count, Integer gamma, Integer alpha, Random &random);
};
void monte_carlo(const std::vector<Sample> &steps, Table &q, Table &sums, Table &counts, Integer gamma);
Integer discounted(const Values &rewards, Integer gamma);
std::string fixed(Integer value);
std::string average(Integer total, Integer count);
std::string cell_text(const World &w, int cell);
std::string cells_text(const World &w, const std::vector<int> &cells);
Lines grid(const World &w, const Lines &fields, const std::string &separator);
Lines value_grid(const World &w, const Values &values);
Lines policy_grid(const World &w, const Policy &policy);
Lines q_rows(const World &w, const std::string &name, const Table &q, const Table *visits);
Lines parts(const std::vector<Lines> &parts);
void write_lines(const std::string &name, const Lines &lines);
#endif
