#include <algorithm>
#include <array>
#include <cstdint>
#include <iostream>
#include <iterator>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using std::string;
using std::to_string;
using std::vector;
using Field = vector<int>;
using Values = vector<int>;
using Matrix = vector<Values>;
using Relation = vector<vector<bool>>;
using Lines = vector<string>;
struct CommandError : std::runtime_error { using std::runtime_error::runtime_error; };
[[noreturn]] void fail(const string& reason) { throw CommandError(reason); }
template<class T> bool contains(const vector<T>& values, const T& value) { return std::find(values.begin(), values.end(), value) != values.end(); }
template<class Predicate> Field select(const Field& field, Predicate predicate) {
    Field result;
    std::copy_if(field.begin(), field.end(), std::back_inserter(result), predicate);
    return result;
}
Field without(const Field& field, int removed) { return select(field, [=](int candidate) { return candidate != removed; }); }
int sum(const Values& values) { return std::accumulate(values.begin(), values.end(), 0); }
int sum_field(const Field& field, const Values& values) {
    int total = 0;
    for (int candidate : field) total += values[candidate];
    return total;
}
int field_mask(const Field& field) {
    int mask = 0;
    for (int candidate : field) mask |= 1 << candidate;
    return mask;
}
Lines split(const string& line, char delimiter = ' ') {
    std::istringstream input(line);
    Lines words;
    string word;
    while (std::getline(input, word, delimiter)) words.push_back(word);
    return words;
}
string join(const Lines& parts, const string& separator = ", ") {
    string result;
    for (const string& part : parts) { if (!result.empty()) result += separator; result += part; }
    return result;
}
string money(int value) { return to_string(value / 100) + "." + (value % 100 < 10 ? "0" : "") + to_string(value % 100); }
string tie_text(bool tie) { return tie ? " (tie)" : ""; }
struct Ballot { int votes; Field ranking; };
struct Aggregate {
    vector<Ballot> groups;
    Values first, last, borda;
    Matrix positions, pairwise;
    int total = 0, blank = 0;
};
struct Result { Field standings; bool tie; Lines rows; Lines exhausted; };
struct Choice { int candidate; bool tie; };
enum class Kind { Plurality, Runoff, Irv, Coombs, Bucklin, Borda, Baldwin, Nanson, Black, Veto, Condorcet, Copeland, Minimax, Schulze, RankedPairs, Kemeny, Approval, Stv };
enum class Minimax { Winning, Margin, Opposition };
struct Method { Kind kind; int parameter = 0; Minimax score = Minimax::Winning; };
const std::array<string, 18> method_names{"PLURALITY", "RUNOFF", "IRV", "COOMBS", "BUCKLIN", "BORDA", "BALDWIN", "NANSON", "BLACK", "VETO", "CONDORCET", "COPELAND", "MINIMAX", "SCHULZE", "RANKEDPAIRS", "KEMENY", "APPROVAL", "STV"};
Method parse_method(const Lines& words, std::size_t start = 0) {
    auto found = std::find(method_names.begin(), method_names.end(), words[start]);
    Method method{static_cast<Kind>(found - method_names.begin())};
    if (method.kind == Kind::Approval || method.kind == Kind::Stv) method.parameter = std::stoi(words[start + 1]);
    if (method.kind == Kind::Minimax) method.score = words[start + 1] == "WINNING" ? Minimax::Winning : words[start + 1] == "MARGIN" ? Minimax::Margin : Minimax::Opposition;
    return method;
}
string method_text(Method method) {
    string name = method_names[static_cast<std::size_t>(method.kind)];
    if (method.kind == Kind::Minimax) name += string(" ") + (method.score == Minimax::Winning ? "WINNING" : method.score == Minimax::Margin ? "MARGIN" : "OPPOSITION");
    if (method.kind == Kind::Approval || method.kind == Kind::Stv) name += " " + to_string(method.parameter);
    return name;
}
const vector<Method> summary_methods{{Kind::Plurality}, {Kind::Runoff}, {Kind::Irv}, {Kind::Coombs}, {Kind::Bucklin}, {Kind::Borda}, {Kind::Baldwin}, {Kind::Nanson}, {Kind::Black}, {Kind::Veto}, {Kind::Copeland}, {Kind::Minimax}, {Kind::Schulze}, {Kind::RankedPairs}, {Kind::Kemeny}};

class Election {
public:
    Lines names;
    int number;
    vector<bool> withdrawn;
    Field priority;
    Values tie_rank;
    vector<vector<Ballot>> entries;
    std::map<int, Aggregate> cache;

    Election(Lines names, int number) : names(std::move(names)), number(number), withdrawn(this->names.size(), false), tie_rank(this->names.size(), 0) {
        Field order(this->names.size());
        std::iota(order.begin(), order.end(), 0);
        std::sort(order.begin(), order.end(), [&](int a, int b) { return this->names[a] < this->names[b]; });
        set_priority(order);
    }
    Values zeros() const { return Values(names.size(), 0); }
    Matrix matrix() const { return Matrix(names.size(), zeros()); }
    Relation relation() const { return Relation(names.size(), vector<bool>(names.size(), false)); }
    Field active() const {
        Field field;
        for (int candidate = 0; candidate < static_cast<int>(names.size()); ++candidate) if (!withdrawn[candidate]) field.push_back(candidate);
        return field;
    }
    int candidate(const string& name) const {
        auto found = std::find(names.begin(), names.end(), name);
        if (found == names.end()) fail("unknown candidate " + name);
        return static_cast<int>(found - names.begin());
    }
    Field checked_names(const Lines& requested) const {
        Field found;
        for (const string& name : requested) {
            int index = candidate(name);
            if (contains(found, index)) fail("duplicate candidate " + name);
            found.push_back(index);
        }
        return found;
    }
    void set_priority(Field order) {
        priority = std::move(order);
        for (int i = 0; i < static_cast<int>(priority.size()); ++i) tie_rank[priority[i]] = i;
    }
    string list(const Field& field, const string& separator = ", ") const {
        Lines parts;
        for (int candidate : field) parts.push_back(names[candidate]);
        return join(parts, separator);
    }
    string values(const Field& field, const Values& values, bool cents = false) const {
        Lines parts;
        for (int candidate : field) parts.push_back(names[candidate] + " " + (cents ? money(values[candidate]) : to_string(values[candidate])));
        return join(parts);
    }
    Field ordered(Field field, const Values& values, bool ascending = false) const {
        std::sort(field.begin(), field.end(), [&](int a, int b) { return values[a] == values[b] ? tie_rank[a] < tie_rank[b] : ascending ? values[a] < values[b] : values[a] > values[b]; });
        return field;
    }
    Field preferred(Field field) const {
        std::sort(field.begin(), field.end(), [&](int a, int b) { return tie_rank[a] < tie_rank[b]; });
        return field;
    }
    const Aggregate& aggregate(const Field& field) {
        int mask = field_mask(field);
        auto found = cache.find(mask);
        if (found != cache.end()) return found->second;
        std::map<Field, int> combined;
        for (const auto& entry : entries) for (const Ballot& group : entry) {
            Field ranking = select(group.ranking, [=](int candidate) { return mask & (1 << candidate); });
            combined[ranking] += group.votes;
        }
        Aggregate result{{}, zeros(), zeros(), zeros(), Matrix(names.size(), Values(field.size(), 0)), matrix()};
        for (const auto& [ranking, votes] : combined) {
            result.groups.push_back({votes, ranking});
            result.total += votes;
            if (ranking.empty()) result.blank += votes;
            else result.first[ranking[0]] += votes;
            Values ranks(names.size(), static_cast<int>(field.size()));
            for (int place = 0; place < static_cast<int>(ranking.size()); ++place) {
                int candidate = ranking[place];
                ranks[candidate] = place;
                result.positions[candidate][place] += votes;
                result.borda[candidate] += votes * (static_cast<int>(field.size()) - place - 1);
            }
            for (int candidate : field) {
                if (ranking.size() < field.size() ? ranks[candidate] == static_cast<int>(field.size()) : candidate == ranking.back()) result.last[candidate] += votes;
                for (int other : field) if (ranks[candidate] < ranks[other]) result.pairwise[candidate][other] += votes;
            }
        }
        return cache.emplace(mask, std::move(result)).first->second;
    }
};

Choice eliminate(const Election& election, const Field& field, const Values& values, const vector<Values>& history) {
    int minimum = values[election.ordered(field, values, true)[0]];
    Field choices = select(field, [&](int candidate) { return values[candidate] == minimum; });
    bool tie = choices.size() > 1;
    for (auto round = history.rbegin(); round != history.rend() && choices.size() > 1; ++round) {
        minimum = (*round)[election.ordered(choices, *round, true)[0]];
        choices = select(choices, [&](int candidate) { return (*round)[candidate] == minimum; });
    }
    return {election.preferred(choices).back(), tie};
}
Result finish(const Election& election, Field standings, bool tie, Lines rows) {
    rows.push_back("winner: " + election.names[standings[0]] + tie_text(tie));
    return {std::move(standings), tie, std::move(rows), {}};
}
Result scored(const Election& election, const Field& field, const Values& values, const string& label, bool ascending = false) {
    Field standings = election.ordered(field, values, ascending);
    bool tie = values[standings[0]] == values[standings[1]];
    return finish(election, standings, tie, {label + ": " + election.values(field, values)});
}
Lines pair_lines(const Election& election, const Field& field, const Matrix& matrix) {
    Lines rows;
    for (std::size_t i = 0; i < field.size(); ++i) for (std::size_t j = i + 1; j < field.size(); ++j) {
        int first = field[i], second = field[j], a = matrix[first][second], b = matrix[second][first];
        string result = a > b ? election.names[first] : b > a ? election.names[second] : "tie";
        rows.push_back(election.names[first] + " vs " + election.names[second] + ": " + to_string(a) + "-" + to_string(b) + " (" + result + ")");
    }
    return rows;
}
Result runoff(Election& election, const Field& field) {
    const Values& first = election.aggregate(field).first;
    Field order = election.ordered(field, first);
    Lines rows{"round 1: " + election.values(field, first)};
    if (2 * first[order[0]] > sum_field(field, first)) return finish(election, order, false, rows);
    Field finalists(order.begin(), order.begin() + 2);
    std::sort(finalists.begin(), finalists.end());
    const Values& second = election.aggregate(finalists).first;
    bool advance = order.size() >= 3 && first[order[1]] == first[order[2]];
    rows.push_back("finalists: " + election.list(finalists) + tie_text(advance));
    rows.push_back("round 2: " + election.values(finalists, second));
    bool tie = second[order[0]] == second[order[1]];
    if (second[order[1]] > second[order[0]]) std::swap(order[0], order[1]);
    return finish(election, order, tie, rows);
}
Result elimination_rounds(Election& election, const Field& field, bool coombs) {
    Field remaining = field, removed;
    vector<Values> history;
    Lines rows, exhausted;
    for (int round = 1; ; ++round) {
        const Aggregate& aggregate = election.aggregate(remaining);
        const Values& values = aggregate.first;
        Field ordered = election.ordered(remaining, values);
        int active = sum_field(remaining, values);
        string row = "round " + to_string(round) + ": " + election.values(remaining, values);
        exhausted.push_back("round " + to_string(round) + ": active " + to_string(active) + ", exhausted " + to_string(aggregate.total - active));
        if (remaining.size() == 1 || 2 * values[ordered[0]] > active) {
            ordered.insert(ordered.end(), removed.rbegin(), removed.rend());
            rows.push_back(row);
            Result result = finish(election, ordered, false, rows);
            result.exhausted = std::move(exhausted);
            return result;
        }
        Choice chosen;
        if (coombs) {
            const Values& last = aggregate.last;
            int maximum = last[election.ordered(remaining, last)[0]];
            Field tied = select(remaining, [&](int candidate) { return last[candidate] == maximum; });
            chosen = {election.ordered(tied, values).back(), tied.size() > 1};
            row += "; last " + election.values(remaining, last);
        } else chosen = eliminate(election, remaining, values, history);
        rows.push_back(row + "; eliminated " + election.names[chosen.candidate] + tie_text(chosen.tie));
        history.push_back(values);
        removed.push_back(chosen.candidate);
        remaining = without(remaining, chosen.candidate);
    }
}
Result bucklin(Election& election, const Field& field) {
    const Aggregate& aggregate = election.aggregate(field);
    int majority = (aggregate.total - aggregate.blank) / 2 + 1;
    vector<Values> history;
    Lines rows{"majority: " + to_string(majority)};
    for (std::size_t depth = 1; depth <= field.size(); ++depth) {
        Values values = election.zeros();
        for (int candidate : field) values[candidate] = std::accumulate(aggregate.positions[candidate].begin(), aggregate.positions[candidate].begin() + depth, 0);
        history.push_back(values);
        rows.push_back("round " + to_string(depth) + ": " + election.values(field, values));
        if (values[election.ordered(field, values)[0]] >= majority) break;
    }
    Field standings = field;
    std::sort(standings.begin(), standings.end(), [&](int a, int b) {
        for (auto round = history.rbegin(); round != history.rend(); ++round) if ((*round)[a] != (*round)[b]) return (*round)[a] > (*round)[b];
        return election.tie_rank[a] < election.tie_rank[b];
    });
    bool tie = history.back()[standings[0]] == history.back()[standings[1]];
    return finish(election, standings, tie, rows);
}
Result borda_rounds(Election& election, const Field& field, bool nanson) {
    Field remaining = field, tail;
    vector<Values> history;
    Lines rows;
    for (int round = 1; remaining.size() >= 2; ++round) {
        const Values& values = election.aggregate(remaining).borda;
        string row = "round " + to_string(round) + ": " + election.values(remaining, values);
        Field removed;
        if (nanson) {
            int total = sum_field(remaining, values);
            removed = select(remaining, [&](int candidate) { return values[candidate] * static_cast<int>(remaining.size()) < total; });
            if (removed.empty()) { rows.push_back(row); break; }
            row += "; eliminated " + election.list(removed);
            removed = election.ordered(removed, values);
        } else {
            Choice chosen = eliminate(election, remaining, values, history);
            removed = {chosen.candidate};
            row += "; eliminated " + election.names[chosen.candidate] + tie_text(chosen.tie);
        }
        tail.insert(tail.begin(), removed.begin(), removed.end());
        remaining = select(remaining, [&](int candidate) { return !contains(removed, candidate); });
        history.push_back(values);
        rows.push_back(row);
    }
    Field order = election.preferred(remaining);
    order.insert(order.end(), tail.begin(), tail.end());
    return finish(election, order, remaining.size() > 1, rows);
}
int condorcet_winner(const Field& field, const Matrix& pairwise, bool loser = false) {
    for (int candidate : field) {
        bool all = true;
        for (int other : field) if (other != candidate) {
            if (loser ? pairwise[candidate][other] >= pairwise[other][candidate] : pairwise[candidate][other] <= pairwise[other][candidate]) all = false;
        }
        if (all) return candidate;
    }
    return -1;
}
Relation closure(const Field& field, Relation edges) {
    for (int middle : field) for (int first : field) for (int second : field) {
        if (edges[first][middle] && edges[middle][second]) edges[first][second] = true;
    }
    return edges;
}
Result condorcet(const Election& election, const Field& field, const Matrix& pairwise) {
    int winner = condorcet_winner(field, pairwise), loser = condorcet_winner(field, pairwise, true);
    Relation weak = election.relation(), strong = election.relation();
    for (int first : field) for (int second : field) {
        weak[first][second] = first == second || pairwise[first][second] >= pairwise[second][first];
        strong[first][second] = first != second && pairwise[first][second] > pairwise[second][first];
    }
    weak = closure(field, weak);
    strong = closure(field, strong);
    Field smith, schwartz;
    for (int candidate : field) {
        bool top = true, unbeaten = true;
        for (int other : field) {
            if (!weak[candidate][other]) top = false;
            if (strong[other][candidate] && !strong[candidate][other]) unbeaten = false;
        }
        if (top) smith.push_back(candidate);
        if (unbeaten) schwartz.push_back(candidate);
    }
    return {{}, false, {"winner: " + (winner < 0 ? string("NONE") : election.names[winner]), "loser: " + (loser < 0 ? string("NONE") : election.names[loser]), "smith: " + election.list(smith), "schwartz: " + election.list(schwartz)}, {}};
}
std::pair<Field, bool> topological(const Election& election, const Field& field, const Relation& beats) {
    Field remaining = field, standings;
    bool tie = false;
    while (!remaining.empty()) {
        Field eligible = select(remaining, [&](int candidate) {
            return std::none_of(remaining.begin(), remaining.end(), [&](int other) { return candidate != other && beats[other][candidate]; });
        });
        if (standings.empty()) tie = eligible.size() > 1;
        int candidate = election.preferred(eligible)[0];
        standings.push_back(candidate);
        remaining = without(remaining, candidate);
    }
    return {standings, tie};
}
Result schulze(const Election& election, const Field& field, const Matrix& pairwise) {
    Matrix strengths = election.matrix();
    for (int first : field) for (int second : field) {
        if (first != second && pairwise[first][second] > pairwise[second][first]) strengths[first][second] = pairwise[first][second];
    }
    for (int middle : field) for (int first : field) if (first != middle) {
        for (int second : field) if (second != middle && second != first) strengths[first][second] = std::max(strengths[first][second], std::min(strengths[first][middle], strengths[middle][second]));
    }
    Relation beats = election.relation();
    for (int first : field) for (int second : field) beats[first][second] = strengths[first][second] > strengths[second][first];
    auto [standings, tie] = topological(election, field, beats);
    Lines rows = pair_lines(election, field, strengths);
    rows.push_back("ranking: " + election.list(standings, " > "));
    return finish(election, standings, tie, rows);
}
Result ranked_pairs(const Election& election, const Field& field, const Matrix& pairwise) {
    vector<std::pair<int, int>> pairs;
    Relation edges = election.relation();
    Lines rows;
    for (int first : field) for (int second : field) if (pairwise[first][second] > pairwise[second][first]) pairs.emplace_back(first, second);
    std::sort(pairs.begin(), pairs.end(), [&](auto first, auto second) {
        auto [a, b] = first;
        auto [c, d] = second;
        if (pairwise[a][b] != pairwise[c][d]) return pairwise[a][b] > pairwise[c][d];
        if (pairwise[b][a] != pairwise[d][c]) return pairwise[b][a] < pairwise[d][c];
        if (a != c) return election.tie_rank[a] < election.tie_rank[c];
        return election.tie_rank[b] < election.tie_rank[d];
    });
    for (auto [first, second] : pairs) {
        bool lock = !closure(field, edges)[second][first];
        if (lock) edges[first][second] = true;
        rows.push_back(string(lock ? "lock " : "skip ") + election.names[first] + ">" + election.names[second] + " " + to_string(pairwise[first][second]) + "-" + to_string(pairwise[second][first]));
    }
    auto [standings, tie] = topological(election, field, edges);
    return finish(election, standings, tie, rows);
}
Result kemeny(const Election& election, const Field& field, const Matrix& pairwise) {
    struct Optimum { int score = 0; int count = 0; Field first; };
    int mask = field_mask(field);
    vector<Optimum> optimum(1 << election.names.size());
    optimum[0].count = 1;
    for (int subset = 1; subset <= mask; ++subset) {
        if ((subset & mask) != subset) continue;
        Optimum& current = optimum[subset];
        current.score = -1;
        for (int candidate : field) if (subset & (1 << candidate)) {
            int rest = subset ^ (1 << candidate), score = optimum[rest].score;
            for (int other : field) if (rest & (1 << other)) score += pairwise[candidate][other];
            if (score > current.score) { current.score = score; current.count = 0; current.first.clear(); }
            if (score == current.score) { current.count += optimum[rest].count; current.first.push_back(candidate); }
        }
    }
    Field standings;
    for (int remaining = mask; remaining != 0;) {
        int candidate = election.preferred(optimum[remaining].first)[0];
        standings.push_back(candidate);
        remaining ^= 1 << candidate;
    }
    const Optimum& best = optimum[mask];
    return finish(election, standings, best.first.size() > 1, {"score: " + to_string(best.score), "optimal: " + to_string(best.count), "ranking: " + election.list(standings, " > ")});
}
Result stv(Election& election, const Field& field, int seats) {
    if (seats >= static_cast<int>(field.size())) fail("too many seats");
    const Aggregate& aggregate = election.aggregate(field);
    vector<Ballot> groups;
    for (const Ballot& group : aggregate.groups) if (!group.ranking.empty()) groups.push_back(group);
    int quota = 100 * (aggregate.total - aggregate.blank) / (seats + 1) + 1;
    Values per_vote(groups.size(), 100);
    Field continuing = field, elected;
    vector<Values> history;
    Lines rows{"quota: " + money(quota)};
    for (int round = 1; ; ++round) {
        Values values = election.zeros();
        Field current(groups.size(), -1);
        int exhausted = 0;
        for (std::size_t i = 0; i < groups.size(); ++i) {
            for (int candidate : groups[i].ranking) if (contains(continuing, candidate)) { current[i] = candidate; break; }
            int value = groups[i].votes * per_vote[i];
            if (current[i] < 0) exhausted += value;
            else values[current[i]] += value;
        }
        string row = "round " + to_string(round) + ": " + election.values(continuing, values, true) + "; exhausted " + money(exhausted);
        Field ordered = election.ordered(continuing, values);
        if (static_cast<int>(continuing.size()) == seats - static_cast<int>(elected.size())) {
            elected.insert(elected.end(), ordered.begin(), ordered.end());
            rows.push_back(row + "; elected " + election.list(ordered));
            break;
        }
        int removed;
        if (values[ordered[0]] >= quota) {
            removed = ordered[0];
            elected.push_back(removed);
            int total = values[removed], surplus = total - quota;
            for (std::size_t i = 0; i < current.size(); ++i) if (current[i] == removed) per_vote[i] = per_vote[i] * surplus / total;
            row += "; elected " + election.names[removed] + " (surplus " + money(surplus) + ")";
        } else {
            Choice chosen = eliminate(election, continuing, values, history);
            removed = chosen.candidate;
            row += "; excluded " + election.names[removed] + tie_text(chosen.tie);
        }
        rows.push_back(row);
        if (static_cast<int>(elected.size()) == seats) break;
        history.push_back(values);
        continuing = without(continuing, removed);
    }
    rows.push_back("elected: " + election.list(elected));
    return {{}, false, std::move(rows), {}};
}
Result tally(Election& election, Method method, const Field& field) {
    const Aggregate& aggregate = election.aggregate(field);
    const Matrix& pairwise = aggregate.pairwise;
    switch (method.kind) {
        case Kind::Plurality: return scored(election, field, aggregate.first, "votes");
        case Kind::Runoff: return runoff(election, field);
        case Kind::Irv: return elimination_rounds(election, field, false);
        case Kind::Coombs: return elimination_rounds(election, field, true);
        case Kind::Bucklin: return bucklin(election, field);
        case Kind::Borda: return scored(election, field, aggregate.borda, "scores");
        case Kind::Baldwin: return borda_rounds(election, field, false);
        case Kind::Nanson: return borda_rounds(election, field, true);
        case Kind::Black: {
            int winner = condorcet_winner(field, pairwise);
            Field ordered = election.ordered(field, aggregate.borda);
            bool tie = winner < 0 && aggregate.borda[ordered[0]] == aggregate.borda[ordered[1]];
            if (winner >= 0) { ordered = without(ordered, winner); ordered.insert(ordered.begin(), winner); }
            return finish(election, ordered, tie, {"condorcet: " + (winner < 0 ? string("NONE") : election.names[winner]), "scores: " + election.values(field, aggregate.borda)});
        }
        case Kind::Veto: return scored(election, field, aggregate.last, "vetoes", true);
        case Kind::Condorcet: return condorcet(election, field, pairwise);
        case Kind::Copeland: {
            Values scores = election.zeros();
            Lines parts;
            for (int candidate : field) {
                int wins = 0, draws = 0, losses = 0;
                for (int other : field) if (other != candidate) {
                    if (pairwise[candidate][other] > pairwise[other][candidate]) ++wins;
                    else if (pairwise[candidate][other] == pairwise[other][candidate]) ++draws;
                    else ++losses;
                }
                int score = 2 * wins + draws;
                scores[candidate] = score;
                parts.push_back(election.names[candidate] + " " + to_string(score / 2) + "." + (score % 2 ? "5" : "0") + " (" + to_string(wins) + "-" + to_string(draws) + "-" + to_string(losses) + ")");
            }
            Field standings = election.ordered(field, scores);
            return finish(election, standings, scores[standings[0]] == scores[standings[1]], {"scores: " + join(parts)});
        }
        case Kind::Minimax: {
            Values scores = election.zeros();
            for (int candidate : field) for (int other : field) if (candidate != other) {
                int opposition = pairwise[other][candidate], support = pairwise[candidate][other];
                if (method.score == Minimax::Opposition) scores[candidate] = std::max(scores[candidate], opposition);
                else if (opposition > support) scores[candidate] = std::max(scores[candidate], method.score == Minimax::Margin ? opposition - support : opposition);
            }
            return scored(election, field, scores, "scores", true);
        }
        case Kind::Schulze: return schulze(election, field, pairwise);
        case Kind::RankedPairs: return ranked_pairs(election, field, pairwise);
        case Kind::Kemeny: return kemeny(election, field, pairwise);
        case Kind::Approval: {
            Values approvals = election.zeros();
            int depth = std::min(method.parameter, static_cast<int>(field.size()));
            for (int candidate : field) approvals[candidate] = std::accumulate(aggregate.positions[candidate].begin(), aggregate.positions[candidate].begin() + depth, 0);
            return scored(election, field, approvals, "approvals");
        }
        case Kind::Stv: return stv(election, field, method.parameter);
    }
    throw std::logic_error("Unknown method");
}
Lines reports(Election& election, const string& command, const Lines& args, const Field& field) {
    const Aggregate& aggregate = election.aggregate(field);
    if (command == "STATUS") {
        Field withdrawn;
        for (int candidate = 0; candidate < static_cast<int>(election.names.size()); ++candidate) if (election.withdrawn[candidate]) withdrawn.push_back(candidate);
        return {"election " + to_string(election.number), "active: " + election.list(field), "withdrawn: " + (withdrawn.empty() ? "none" : election.list(withdrawn)), "tiebreak: " + election.list(election.priority), "ballots: " + to_string(aggregate.total) + " in " + to_string(election.entries.size()) + " entries"};
    }
    if (command == "BALLOTS") {
        vector<std::pair<int, string>> groups;
        for (const Ballot& group : aggregate.groups) groups.emplace_back(group.votes, group.ranking.empty() ? "-" : election.list(group.ranking, ">"));
        std::sort(groups.begin(), groups.end(), [](const auto& a, const auto& b) { return a.first == b.first ? a.second < b.second : a.first > b.first; });
        Lines rows{"total " + to_string(aggregate.total) + ", blank " + to_string(aggregate.blank) + ", distinct " + to_string(groups.size())};
        for (const auto& [votes, notation] : groups) rows.push_back(to_string(votes) + " " + notation);
        return rows;
    }
    if (command == "PROFILE") {
        Lines rows;
        for (int candidate : field) {
            Lines counts;
            for (int count : aggregate.positions[candidate]) counts.push_back(to_string(count));
            rows.push_back(election.names[candidate] + ": " + join(counts, " ") + " unranked " + to_string(aggregate.total - sum(aggregate.positions[candidate])));
        }
        return rows;
    }
    if (command == "PAIRWISE") return pair_lines(election, field, aggregate.pairwise);
    if (command == "EXHAUSTED") return elimination_rounds(election, field, false).exhausted;
    if (command == "RANKING" || command == "SPOILERS") {
        Method method = parse_method(args);
        if (method.kind == Kind::Condorcet || method.kind == Kind::Stv) fail("not rankable");
        if (command == "SPOILERS" && field.size() < 3) fail("too few candidates");
        Field standings = tally(election, method, field).standings;
        if (command == "RANKING") return {election.list(standings, " > ")};
        int winner = standings[0];
        Lines rows{"winner: " + election.names[winner]};
        for (int excluded : field) if (excluded != winner) {
            int other = tally(election, method, without(field, excluded)).standings[0];
            rows.push_back("without " + election.names[excluded] + ": " + election.names[other] + (other != winner ? " (changed)" : ""));
        }
        return rows;
    }
    if (command == "SUMMARY") {
        Values wins = election.zeros();
        Lines rows;
        for (Method method : summary_methods) {
            int winner = tally(election, method, field).standings[0];
            ++wins[winner];
            rows.push_back(method_text(method) + ": " + election.names[winner]);
        }
        rows.push_back("wins: " + election.values(field, wins));
        return rows;
    }
    if (command == "COMPARE") {
        Field candidates;
        for (const string& name : args) {
            int candidate = election.candidate(name);
            if (election.withdrawn[candidate]) fail("withdrawn candidate " + name);
            candidates.push_back(candidate);
        }
        int first = candidates[0], second = candidates[1];
        if (first == second) fail("same candidate");
        int a = aggregate.pairwise[first][second], b = aggregate.pairwise[second][first];
        std::array<Lines, 2> ahead;
        for (Method method : summary_methods) {
            Field standings = tally(election, method, field).standings;
            int side = std::find(standings.begin(), standings.end(), first) < std::find(standings.begin(), standings.end(), second) ? 0 : 1;
            ahead[side].push_back(method_text(method));
        }
        return {args[0] + " " + to_string(a) + ", " + args[1] + " " + to_string(b) + ", neither " + to_string(aggregate.total - a - b), args[0] + " ahead: " + (ahead[0].empty() ? "none" : join(ahead[0])), args[1] + " ahead: " + (ahead[1].empty() ? "none" : join(ahead[1]))};
    }
    Lines words{command};
    words.insert(words.end(), args.begin(), args.end());
    return tally(election, parse_method(words), field).rows;
}

class VoteCounter {
    std::optional<Election> election_;
    int number_ = 0;
public:
    Lines execute(const string& line) {
        Lines words = split(line), args(words.begin() + 1, words.end());
        const string& command = words[0];
        if (command == "CANDIDATES") {
            if (args.size() < 2) fail("too few candidates");
            std::set<string> seen;
            for (const string& name : args) if (!seen.insert(name).second) fail("duplicate candidate " + name);
            election_.emplace(args, ++number_);
            return {"election " + to_string(number_) + ": " + to_string(args.size()) + " candidates"};
        }
        if (!election_) fail("no election");
        Election& election = *election_;
        Field field = election.active();
        if (command == "BALLOT") {
            Field ranking = args[1] == "-" ? Field{} : election.checked_names(split(args[1], '>'));
            election.entries.push_back({{std::stoi(args[0]), ranking}});
            election.cache.clear();
            return {};
        }
        if (command == "RANDOM") {
            std::int64_t state = std::stoll(args[1]);
            auto draw = [&]() { state = 48271 * state % 2147483647; return state; };
            vector<Ballot> groups;
            for (int group = 0; group < std::stoi(args[0]); ++group) {
                Field ranking = field;
                for (int index = static_cast<int>(ranking.size()) - 1; index >= 1; --index) {
                    int other = static_cast<int>(draw() % (index + 1));
                    std::swap(ranking[index], ranking[other]);
                }
                ranking.resize(static_cast<std::size_t>(draw() % static_cast<int>(ranking.size()) + 1));
                groups.push_back({1, std::move(ranking)});
            }
            election.entries.push_back(std::move(groups));
            election.cache.clear();
            return {};
        }
        if (command == "UNDO") {
            if (election.entries.empty()) fail("nothing to undo");
            election.entries.pop_back();
            election.cache.clear();
            return {};
        }
        if (command == "WITHDRAW" || command == "RESTORE") {
            int candidate = election.candidate(args[0]);
            if (command == "WITHDRAW") {
                if (election.withdrawn[candidate]) fail("already withdrawn " + args[0]);
                if (field.size() <= 2) fail("too few candidates");
                election.withdrawn[candidate] = true;
            } else {
                if (!election.withdrawn[candidate]) fail("not withdrawn " + args[0]);
                election.withdrawn[candidate] = false;
            }
            return {};
        }
        if (command == "TIEBREAK") {
            Field order = election.checked_names(args);
            if (order.size() != election.names.size()) fail("incomplete tiebreak");
            election.set_priority(order);
            return {};
        }
        if (command != "STATUS" && election.entries.empty()) fail("no ballots");
        Lines rows = reports(election, command, args, field);
        rows.insert(rows.begin(), "[" + line + "]");
        return rows;
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int count;
    std::cin >> count;
    string line;
    std::getline(std::cin, line);
    VoteCounter counter;
    for (int index = 0; index < count; ++index) {
        std::getline(std::cin, line);
        try {
            for (const string& row : counter.execute(line)) std::cout << row << '\n';
        } catch (const CommandError& error) {
            std::cout << "ERROR " << error.what() << '\n';
        }
    }
}
