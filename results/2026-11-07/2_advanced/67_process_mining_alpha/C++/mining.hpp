#ifndef MINING_HPP
#define MINING_HPP
#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
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
#include <tuple>
#include <utility>
#include <vector>
using I = long long;
using Names = std::vector<std::string>;
using Trace = Names;
using NamePair = std::pair<std::string, std::string>;
using Counts = std::map<NamePair, I>;
using Log = std::vector<std::pair<Trace, I>>;
using Lines = std::vector<std::string>;
using Relation = std::function<std::string(const std::string &, const std::string &)>;
struct Fraction {
    I numerator = 0, denominator = 1;
    Fraction(I numerator = 0, I denominator = 1);
};
Fraction operator+(Fraction a, Fraction b), operator-(Fraction a, Fraction b),
                                            operator*(Fraction a, Fraction b),
                                            operator/(Fraction a, Fraction b);
bool operator<(Fraction a, Fraction b), operator==(Fraction a, Fraction b);
inline bool operator>(Fraction a, Fraction b) { return b < a; }
inline bool operator>=(Fraction a, Fraction b) { return !(a < b); }
inline bool operator<=(Fraction a, Fraction b) { return !(b < a); }
std::string fraction(Fraction value), percentage(I count, I total), names(const Names &values);
void save(const std::string &name, const Lines &lines);
struct Row {
    int line;
    std::string case_id, activity, timestamp, resource;
};
struct Event {
    int line;
    std::string case_id, activity, timestamp, resource;
    I time;
};
struct Case {
    std::string id;
    std::vector<Event> events;
    Trace trace;
    I duration = 0;
};
struct Input {
    std::vector<Row> rows;
    std::map<std::string, std::string> parameters;
};
Input read_inputs();
std::optional<I> timestamp_minutes(const std::string &timestamp);
std::vector<Case> group_cases(const std::vector<Event> &events);
Fraction median(std::vector<I> values);
I count(const Counts &counts, const std::string &a, const std::string &b);
Counts directly_follows(const Log &log), triangle_counts(const Log &log);
std::string basic_relation(const Counts &counts, const std::string &a, const std::string &b),
    plus_relation(const Counts &counts, const Counts &triangles, const std::string &a,
                  const std::string &b);
Lines table(const std::vector<Names> &rows, int width),
    footprint(const Names &activities, const Relation &relation);
struct Candidate {
    unsigned first, second;
    bool operator<(const Candidate &other) const {
        return std::tie(first, second) < std::tie(other.first, other.second);
    }
};
std::optional<Candidate> extend_pair(Candidate pair, int activity, int side,
                                     const Names &activities, const Relation &relation);
bool pair_order(Candidate a, Candidate b);
Names mask_names(unsigned mask, const Names &activities);
Fraction dependency(const Counts &counts, const std::string &a, const std::string &b),
    loop_measure(I count),
    split_measure(const Counts &counts, const std::string &a, const std::string &b,
                  const std::string &c),
    join_measure(const Counts &counts, const std::string &a, const std::string &b,
                 const std::string &c);
using Marking = std::vector<int>;
struct Net {
    Names places, transitions;
    std::set<NamePair> arcs;
    int initial = 0, final = 0;
    std::vector<std::vector<int>> inputs, outputs;
    std::vector<std::vector<int>> routes;
    Net() = default;
    Net(Names places, Names transitions, std::set<NamePair> arcs, const std::string &initial,
        const std::string &final);
    bool enabled(const Marking &marking, int transition) const;
    Marking fire(Marking marking, int transition) const;
    Marking initial_marking() const;
    Marking final_marking() const;
    std::vector<int> enabled_transitions(const Marking &marking) const;
    int transition_index(const std::string &name) const;
};
Net read_model();
struct Replay {
    I missing = 0, remaining = 0, consumed = 0, produced = 0, skipped = 0;
    std::vector<I> place_missing, place_remaining, deviating;
    std::vector<std::vector<I>> waiting;
    std::vector<std::map<std::string, I>> routes;
    explicit Replay(int places = 0);
    Fraction fitness() const;
};
template <class... T> void line(Lines &lines, const T &...values) {
    std::ostringstream out;
    (out << ... << values);
    lines.push_back(out.str());
}
#endif
