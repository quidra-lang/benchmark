#include <algorithm>
#include <cstdint>
#include <iostream>
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
using Preference = vector<int>;
using Matching = vector<int>;

struct CommandError : std::runtime_error { using std::runtime_error::runtime_error; };
[[noreturn]] void fail(const string& message) { throw CommandError(message); }
enum class Kind { TwoSided, Roommate, Housing };
enum class Side { Proposer, Receiver };
struct Saved { string source; Matching matching; };

template<class T> int position_of(const vector<T>& values, const T& value) {
    auto found = std::find(values.begin(), values.end(), value);
    return found == values.end() ? -1 : static_cast<int>(found - values.begin());
}
int rank_in(const Preference& preference, int partner) {
    int index = position_of(preference, partner);
    return index < 0 ? static_cast<int>(preference.size()) + 1 : index + 1;
}
vector<int> sequence(int start, int end) {
    vector<int> result(end - start);
    std::iota(result.begin(), result.end(), start);
    return result;
}
vector<string> split(const string& text, char separator = ' ') {
    std::istringstream stream(text);
    vector<string> result;
    for (string word; std::getline(stream, word, separator);) result.push_back(word);
    return result;
}
string join(const vector<string>& parts, const string& separator = " ") {
    string result;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        if (i) result += separator;
        result += parts[i];
    }
    return result;
}
string list_text(const vector<string>& names, const vector<int>& indices) {
    vector<string> parts;
    for (int index : indices) parts.push_back(names[index]);
    return parts.empty() ? "-" : join(parts);
}
struct Market {
    string name;
    Kind kind;
    vector<string> names;
    int proposers;
    vector<string> houses;
    vector<Preference> preferences;
    vector<int> capacities;
    std::optional<Saved> current;

    Market(string name, Kind kind, vector<string> names, int proposers = 0, vector<string> houses = {})
        : name(std::move(name)), kind(kind), names(std::move(names)), proposers(proposers), houses(std::move(houses)),
          preferences(this->names.size()), capacities(this->names.size(), 1) {}
    int size() const { return static_cast<int>(names.size()); }
    void require_kind(Kind expected) const { if (kind != expected) fail("WRONG TYPE " + name); }
    int agent(const string& name, std::optional<Side> side = std::nullopt) const {
        int index = position_of(names, name);
        if (index < 0) fail("UNKNOWN AGENT " + name);
        if (side == Side::Proposer && index >= proposers) fail("NOT PROPOSER " + name);
        if (side == Side::Receiver && index < proposers) fail("NOT RECEIVER " + name);
        return index;
    }
    Preference effective(int agent) const {
        Preference result = preferences[agent];
        int own = position_of(result, agent);
        if (own < 0) result.push_back(agent);
        else result.resize(own + 1);
        return result;
    }
    string partner_name(int partner) const { return partner < 0 ? "*" : names[partner]; }
};
string pair_text(const Market& market, const Matching& matching) {
    vector<string> pairs;
    for (int p = 0; p < market.proposers; ++p) pairs.push_back(market.names[p] + "-" + market.partner_name(matching[p]));
    return join(pairs);
}
string rotation_text(const Market& market, const Matching& matching, const vector<int>& rotation) {
    vector<string> pairs;
    for (int p : rotation) pairs.push_back(market.names[p] + "-" + market.names[matching[p]]);
    return join(pairs);
}
string allocation_text(const Market& market, const vector<int>& allocation) {
    vector<string> parts;
    for (int a = 0; a < market.size(); ++a) parts.push_back(market.names[a] + "-" + (allocation[a] < 0 ? "*" : market.houses[allocation[a]]));
    return join(parts);
}
vector<int> partners_of(const Matching& matching, int receiver) {
    vector<int> partners;
    for (std::size_t p = 0; p < matching.size(); ++p) if (matching[p] == receiver) partners.push_back(static_cast<int>(p));
    return partners;
}

struct DeferredResult { Matching matching; int proposals; vector<string> history; };
DeferredResult deferred(const Market& market, bool reverse = false, bool verbose = false) {
    vector<int> next(market.size()), counts(market.size());
    vector<vector<int>> holding(market.size());
    vector<bool> queued(market.size());
    auto able = [&](int agent) {
        return counts[agent] < market.capacities[agent] && next[agent] < static_cast<int>(market.preferences[agent].size());
    };
    vector<int> proposing = reverse ? sequence(market.proposers, market.size()) : sequence(0, market.proposers);
    vector<int> queue;
    for (int agent : proposing) if (able(agent)) { queue.push_back(agent); queued[agent] = true; }
    DeferredResult result{Matching(market.proposers, -1), 0, {}};
    for (std::size_t head = 0; head < queue.size(); ++head) {
        int proposer = queue[head];
        queued[proposer] = false;
        int receiver = market.preferences[proposer][next[proposer]++];
        const Preference& preference = market.preferences[receiver];
        ++result.proposals;
        string action = "REJECT";
        if (position_of(preference, proposer) >= 0) {
            if (holding[receiver].size() < static_cast<std::size_t>(market.capacities[receiver])) {
                holding[receiver].push_back(proposer);
                ++counts[proposer];
                action = "HOLD";
            } else {
                auto worst = std::max_element(holding[receiver].begin(), holding[receiver].end(), [&](int a, int b) {
                    return rank_in(preference, a) < rank_in(preference, b);
                });
                int rejected = *worst;
                if (rank_in(preference, proposer) < rank_in(preference, rejected)) {
                    *worst = proposer;
                    ++counts[proposer];
                    --counts[rejected];
                    action = "HOLD REJECT " + market.names[rejected];
                    if (able(rejected) && !queued[rejected]) { queue.push_back(rejected); queued[rejected] = true; }
                }
            }
        }
        if (verbose) result.history.push_back("PROPOSE " + market.names[proposer] + " " + market.names[receiver] + " " + action);
        if (able(proposer)) { queue.push_back(proposer); queued[proposer] = true; }
    }
    vector<int> receiving = reverse ? sequence(0, market.proposers) : sequence(market.proposers, market.size());
    for (int receiver : receiving) {
        for (int proposer : holding[receiver]) {
            if (reverse) result.matching[receiver] = proposer;
            else result.matching[proposer] = receiver;
        }
    }
    return result;
}
struct BostonResult { Matching matching; int applications; };
BostonResult boston(const Market& market) {
    BostonResult result{Matching(market.proposers, -1), 0};
    vector<int> remaining = market.capacities;
    int rounds = 0;
    for (int p = 0; p < market.proposers; ++p) rounds = std::max(rounds, static_cast<int>(market.preferences[p].size()));
    for (int round = 0; round < rounds; ++round) {
        vector<int> applied(market.proposers, -1);
        for (int p = 0; p < market.proposers; ++p) {
            if (result.matching[p] < 0 && round < static_cast<int>(market.preferences[p].size())) {
                applied[p] = market.preferences[p][round];
                ++result.applications;
            }
        }
        for (int r = market.proposers; r < market.size(); ++r) {
            for (int p : market.preferences[r]) {
                if (remaining[r] > 0 && applied[p] == r) {
                    result.matching[p] = r;
                    --remaining[r];
                }
            }
        }
    }
    return result;
}

vector<vector<int>> exposed_rotations(const Market& market, const Matching& matching) {
    vector<int> owner(market.size(), -1), successor(market.proposers, -1);
    for (int p = 0; p < market.proposers; ++p) if (matching[p] >= 0) owner[matching[p]] = p;
    for (int p = 0; p < market.proposers; ++p) {
        if (matching[p] < 0) continue;
        const Preference& preference = market.preferences[p];
        for (std::size_t i = rank_in(preference, matching[p]); i < preference.size(); ++i) {
            int r = preference[i];
            const Preference& ranking = market.preferences[r];
            if (position_of(ranking, p) >= 0 && (owner[r] < 0 || rank_in(ranking, p) < rank_in(ranking, owner[r]))) {
                successor[p] = owner[r];
                break;
            }
        }
    }
    vector<bool> covered(market.proposers);
    vector<vector<int>> rotations;
    for (int start = 0; start < market.proposers; ++start) {
        if (covered[start]) continue;
        vector<int> path;
        int point = start;
        while (point >= 0 && position_of(path, point) < 0) { path.push_back(point); point = successor[point]; }
        if (point == start) {
            for (int p : path) covered[p] = true;
            rotations.push_back(path);
        }
    }
    return rotations;
}
struct Metrics { int cost = 0; int regret = 0; };
Metrics metrics(const Market& market, const Matching& matching) {
    Metrics result;
    for (int p = 0; p < market.proposers; ++p) {
        int r = matching[p];
        if (r < 0) continue;
        int first = rank_in(market.preferences[p], r), second = rank_in(market.preferences[r], p);
        result.cost += first + second;
        result.regret = std::max({result.regret, first, second});
    }
    return result;
}
struct Entry { Matching matching; int origin; int via; };
struct Lattice { vector<Entry> entries; vector<string> rotations; };
Lattice enumerate(const Market& market) {
    for (int r = market.proposers; r < market.size(); ++r) if (market.capacities[r] != 1) fail("NOT ONE TO ONE");
    Lattice result{{{deferred(market).matching, 0, 0}}, {}};
    std::set<Matching> seen{result.entries.front().matching};
    for (std::size_t index = 0; index < result.entries.size(); ++index) {
        Matching matching = result.entries[index].matching;
        for (const vector<int>& rotation : exposed_rotations(market, matching)) {
            string notation = rotation_text(market, matching, rotation);
            int identifier = position_of(result.rotations, notation);
            if (identifier < 0) { identifier = static_cast<int>(result.rotations.size()); result.rotations.push_back(notation); }
            Matching following = matching;
            for (std::size_t i = 0; i < rotation.size(); ++i) following[rotation[i]] = matching[rotation[(i + 1) % rotation.size()]];
            if (seen.count(following)) continue;
            if (result.entries.size() == 50) fail("TOO MANY MATCHINGS");
            seen.insert(following);
            result.entries.push_back({following, static_cast<int>(index) + 1, identifier + 1});
        }
    }
    return result;
}
vector<string> check_pairs(const Market& market, const vector<string>& pairs) {
    if (market.kind == Kind::Housing) fail("WRONG TYPE " + market.name);
    Matching matching(market.size(), -1);
    vector<int> counts(market.size());
    for (const string& word : pairs) {
        vector<string> pair = split(word, '-');
        std::optional<Side> first_side = market.kind == Kind::TwoSided ? std::optional<Side>(Side::Proposer) : std::nullopt;
        std::optional<Side> second_side = market.kind == Kind::TwoSided ? std::optional<Side>(Side::Receiver) : std::nullopt;
        int first = market.agent(pair[0], first_side);
        int second = market.agent(pair[1], second_side);
        if (matching[first] >= 0) fail("DUPLICATE AGENT " + pair[0]);
        if (market.kind == Kind::TwoSided) {
            if (++counts[second] > market.capacities[second]) fail("OVER CAPACITY " + pair[1]);
        } else {
            if (first == second || matching[second] >= 0) fail("DUPLICATE AGENT " + pair[1]);
            matching[second] = first;
        }
        matching[first] = second;
    }
    vector<string> unacceptable, blocking;
    if (market.kind == Kind::TwoSided) {
        for (int p = 0; p < market.proposers; ++p) {
            int r = matching[p];
            const Preference& preference = market.preferences[p];
            if (r >= 0 && (position_of(preference, r) < 0 || position_of(market.preferences[r], p) < 0)) {
                unacceptable.push_back("UNACCEPTABLE " + market.names[p] + " " + market.names[r]);
            }
            for (int other = market.proposers; other < market.size(); ++other) {
                const Preference& ranking = market.preferences[other];
                if (r == other || position_of(preference, other) < 0 || position_of(ranking, p) < 0) continue;
                if (rank_in(preference, other) >= rank_in(preference, r)) continue;
                int worst = 0;
                for (int partner = 0; partner < market.proposers; ++partner) {
                    if (matching[partner] == other) worst = std::max(worst, rank_in(ranking, partner));
                }
                if (counts[other] < market.capacities[other] || rank_in(ranking, p) < worst) {
                    blocking.push_back("BLOCKING " + market.names[p] + " " + market.names[other]);
                }
            }
        }
    } else {
        for (int first = 0; first < market.size(); ++first) {
            for (int second = first + 1; second < market.size(); ++second) {
                bool mutual = position_of(market.preferences[first], second) >= 0 && position_of(market.preferences[second], first) >= 0;
                string notation = market.names[first] + " " + market.names[second];
                if (matching[first] == second) {
                    if (!mutual) unacceptable.push_back("UNACCEPTABLE " + notation);
                } else if (mutual && rank_in(market.preferences[first], second) < rank_in(market.preferences[first], matching[first])
                    && rank_in(market.preferences[second], first) < rank_in(market.preferences[second], matching[second])) {
                    blocking.push_back("BLOCKING " + notation);
                }
            }
        }
    }
    if (unacceptable.empty() && blocking.empty()) return {"CHECK " + market.name + " STABLE"};
    vector<string> result{"CHECK " + market.name + " UNSTABLE unacceptable=" + to_string(unacceptable.size()) + " blocking=" + to_string(blocking.size())};
    result.insert(result.end(), unacceptable.begin(), unacceptable.end());
    result.insert(result.end(), blocking.begin(), blocking.end());
    return result;
}
void remove_pair(vector<Preference>& lists, int first, int second) {
    auto erase = [&](int a, int b) { lists[a].erase(std::remove(lists[a].begin(), lists[a].end(), b), lists[a].end()); };
    erase(first, second);
    erase(second, first);
}
int empty_list(const vector<Preference>& lists) {
    for (std::size_t i = 0; i < lists.size(); ++i) if (lists[i].empty()) return static_cast<int>(i);
    return -1;
}
void append_table(vector<string>& output, const Market& market, const vector<Preference>& lists) {
    for (int a = 0; a < market.size(); ++a) output.push_back("TABLE " + market.names[a] + " " + list_text(market.names, lists[a]));
}
vector<string> roommates(const Market& market, bool verbose) {
    market.require_kind(Kind::Roommate);
    for (int a = 0; a < market.size(); ++a) {
        if (static_cast<int>(market.preferences[a].size()) < market.size() - 1) fail("INCOMPLETE " + market.names[a]);
    }
    vector<Preference> lists = market.preferences;
    vector<int> held(market.size(), -1), queue = sequence(0, market.size());
    int proposals = 0, failure = -1;
    for (std::size_t head = 0; head < queue.size(); ++head) {
        int proposer = queue[head], receiver = lists[proposer].front();
        if (held[receiver] >= 0) queue.push_back(held[receiver]);
        held[receiver] = proposer;
        ++proposals;
        Preference preference = lists[receiver];
        for (std::size_t i = position_of(preference, proposer) + 1; i < preference.size(); ++i) remove_pair(lists, receiver, preference[i]);
        failure = empty_list(lists);
        if (failure >= 0) break;
    }
    vector<string> history;
    if (failure < 0 && verbose) append_table(history, market, lists);
    int rotations = 0;
    while (failure < 0) {
        int point = -1;
        for (int a = 0; a < market.size(); ++a) if (lists[a].size() >= 2) { point = a; break; }
        if (point < 0) break;
        vector<int> path;
        while (position_of(path, point) < 0) { path.push_back(point); point = lists[lists[point][1]].back(); }
        vector<int> rotation(path.begin() + position_of(path, point), path.end()), front;
        vector<string> pairs;
        for (int a : rotation) { front.push_back(lists[a].front()); pairs.push_back(market.names[a] + "-" + market.names[lists[a].front()]); }
        history.push_back("ROTATION " + to_string(++rotations) + " " + join(pairs));
        vector<std::pair<int, int>> removals;
        for (std::size_t i = 0; i < rotation.size(); ++i) {
            int receiver = front[(i + 1) % front.size()];
            const Preference& preference = lists[receiver];
            for (std::size_t j = position_of(preference, rotation[i]) + 1; j < preference.size(); ++j) removals.emplace_back(receiver, preference[j]);
        }
        for (auto [first, second] : removals) remove_pair(lists, first, second);
        if (verbose) append_table(history, market, lists);
        failure = empty_list(lists);
    }
    vector<string> result{"ROOMMATES " + market.name + " proposals=" + to_string(proposals)};
    result.insert(result.end(), history.begin(), history.end());
    if (failure >= 0) { result.push_back("NO STABLE MATCHING " + market.names[failure]); return result; }
    vector<string> pairs;
    for (int a = 0; a < market.size(); ++a) if (a < lists[a].front()) pairs.push_back(market.names[a] + "-" + market.names[lists[a].front()]);
    result.push_back("MATCHING " + join(pairs));
    return result;
}

vector<string> ttc(const Market& market) {
    std::set<int> remaining;
    for (int a = 0; a < market.size(); ++a) remaining.insert(a);
    vector<int> allocation(market.size(), -1);
    vector<string> cycles;
    while (!remaining.empty()) {
        vector<int> pointing(market.size(), -1);
        for (int a : remaining) {
            for (int house : market.effective(a)) if (remaining.count(house)) { pointing[a] = house; break; }
        }
        vector<int> path;
        int point = *remaining.begin();
        while (position_of(path, point) < 0) { path.push_back(point); point = pointing[point]; }
        vector<int> cycle(path.begin() + position_of(path, point), path.end());
        vector<string> parts;
        for (int a : cycle) {
            allocation[a] = pointing[a];
            remaining.erase(a);
            parts.push_back(market.names[a] + ":" + market.houses[allocation[a]]);
        }
        cycles.push_back("CYCLE " + to_string(cycles.size() + 1) + " " + join(parts));
    }
    vector<string> result{"TTC " + market.name + " cycles=" + to_string(cycles.size())};
    result.insert(result.end(), cycles.begin(), cycles.end());
    result.push_back("ALLOCATION " + allocation_text(market, allocation));
    return result;
}
vector<string> serial(const Market& market, const vector<string>& names) {
    vector<int> order;
    for (const string& name : names) {
        int a = market.agent(name);
        if (position_of(order, a) >= 0) fail("DUPLICATE AGENT " + name);
        order.push_back(a);
    }
    if (order.size() != market.names.size()) fail("BAD ORDER");
    vector<bool> remaining(market.size(), true);
    vector<int> allocation(market.size(), -1);
    int assigned = 0;
    for (int a : order) {
        for (int house : market.preferences[a]) {
            if (remaining[house]) { allocation[a] = house; remaining[house] = false; ++assigned; break; }
        }
    }
    vector<int> worse;
    for (int a = 0; a < market.size(); ++a) if (position_of(market.effective(a), allocation[a]) < 0) worse.push_back(a);
    return {"SERIAL " + market.name + " assigned=" + to_string(assigned), "ALLOCATION " + allocation_text(market, allocation), "WORSE " + list_text(market.names, worse)};
}
vector<string> hospital_report(const Market& market) {
    Matching resident = deferred(market).matching, hospital = deferred(market, true).matching;
    vector<int> unmatched;
    bool rural = true;
    for (int p = 0; p < market.proposers; ++p) {
        if (resident[p] < 0) unmatched.push_back(p);
        if ((resident[p] >= 0) != (hospital[p] >= 0)) rural = false;
    }
    vector<string> result{
        "HR " + market.name + " residents=" + to_string(market.proposers) + " hospitals=" + to_string(market.size() - market.proposers),
        "RESIDENT-OPTIMAL " + pair_text(market, resident), "HOSPITAL-OPTIMAL " + pair_text(market, hospital),
        "UNMATCHED " + list_text(market.names, unmatched),
    };
    for (int r = market.proposers; r < market.size(); ++r) {
        vector<int> first = partners_of(resident, r), second = partners_of(hospital, r);
        int capacity = market.capacities[r];
        bool same = first == second;
        result.push_back("HOSPITAL " + market.names[r] + " cap=" + to_string(capacity) + " resident=" + to_string(first.size())
            + " hospital=" + to_string(second.size()) + " same=" + (same ? "YES" : "NO"));
        if (first.size() != second.size() || (first.size() < static_cast<std::size_t>(capacity) && !same)) rural = false;
    }
    result.push_back(rural ? "RURAL HOLDS" : "RURAL FAILS");
    return result;
}
vector<string> manipulate(const Market& market, int proposer) {
    const Preference& truth = market.preferences[proposer];
    int baseline_b = boston(market).matching[proposer], baseline_g = deferred(market).matching[proposer];
    int swaps = std::max(0, static_cast<int>(truth.size()) - 1);
    vector<string> output{"MANIPULATE " + market.name + " " + market.names[proposer] + " boston=" + market.partner_name(baseline_b)
        + " gs=" + market.partner_name(baseline_g) + " swaps=" + to_string(swaps)};
    for (int i = 0; i < swaps; ++i) {
        Market trial = market;
        std::swap(trial.preferences[proposer][i], trial.preferences[proposer][i + 1]);
        struct Outcome { string label; int partner; int baseline; };
        vector<Outcome> outcomes{{"BOSTON", boston(trial).matching[proposer], baseline_b}, {"GS", deferred(trial).matching[proposer], baseline_g}};
        for (const Outcome& result : outcomes) {
            if (rank_in(truth, result.partner) < rank_in(truth, result.baseline)) {
                output.push_back("IMPROVE " + result.label + " " + to_string(i + 1) + " " + market.names[truth[i]] + " " + market.names[truth[i + 1]]
                    + " result=" + market.partner_name(result.partner));
            }
        }
    }
    if (output.size() == 1) output.push_back("NO IMPROVEMENT");
    return output;
}
vector<string> statistics(const Market& market) {
    if (!market.current) fail("NO MATCHING");
    const Saved& saved = *market.current;
    vector<int> proposer_ranks, receiver_ranks;
    std::set<int> occupied;
    for (int p = 0; p < market.proposers; ++p) {
        int r = saved.matching[p];
        if (r < 0) continue;
        proposer_ranks.push_back(rank_in(market.preferences[p], r));
        receiver_ranks.push_back(rank_in(market.preferences[r], p));
        occupied.insert(r);
    }
    int pairs = static_cast<int>(proposer_ranks.size());
    vector<string> output{"STATS " + market.name + " source=" + saved.source + " pairs=" + to_string(pairs)};
    struct Summary { string label; vector<int> ranks; int unmatched; };
    vector<Summary> sides{{"PROPOSERS", proposer_ranks, market.proposers - pairs},
        {"RECEIVERS", receiver_ranks, market.size() - market.proposers - static_cast<int>(occupied.size())}};
    for (const Summary& side : sides) {
        int sum = std::accumulate(side.ranks.begin(), side.ranks.end(), 0);
        int first = static_cast<int>(std::count(side.ranks.begin(), side.ranks.end(), 1));
        string average = "-", truncated = "-";
        if (pairs > 0) {
            int divisor = std::gcd(sum, pairs), cents = 100 * sum / pairs;
            average = to_string(sum / divisor) + "/" + to_string(pairs / divisor);
            truncated = to_string(cents / 100) + "." + (cents % 100 < 10 ? "0" : "") + to_string(cents % 100);
        }
        output.push_back(side.label + " sum=" + to_string(sum) + " average=" + average + " truncated=" + truncated
            + " first=" + to_string(first) + " unmatched=" + to_string(side.unmatched));
    }
    return output;
}

vector<string> show_market(const Market& market) {
    string header = "SHOW " + market.name;
    if (market.kind == Kind::TwoSided) header += " MARKET proposers=" + to_string(market.proposers) + " receivers=" + to_string(market.size() - market.proposers);
    else header += string(market.kind == Kind::Roommate ? " ROOMS" : " HOUSES") + " agents=" + to_string(market.size());
    vector<string> rows{header};
    for (int a = 0; a < market.size(); ++a) {
        string prefix;
        if (market.kind == Kind::TwoSided) prefix = a < market.proposers ? "PROPOSER " + market.names[a]
            : "RECEIVER " + market.names[a] + " cap=" + to_string(market.capacities[a]);
        else {
            prefix = "AGENT " + market.names[a];
            if (market.kind == Kind::Housing) prefix += " house=" + market.houses[a];
        }
        rows.push_back(prefix + " " + list_text(market.kind == Kind::Housing ? market.houses : market.names, market.preferences[a]));
    }
    if (market.kind == Kind::TwoSided) rows.push_back("CURRENT " + (market.current ? market.current->source : "-"));
    return rows;
}
Market new_market(const string& command, const string& name, const vector<string>& args) {
    if (command == "RANDOM") {
        int count = std::stoi(args[0]);
        std::int64_t state = std::stoll(args[1]);
        vector<string> names;
        for (const string& prefix : {string("P"), string("R")}) {
            for (int i = 1; i <= count; ++i) names.push_back(prefix + to_string(i));
        }
        Market market(name, Kind::TwoSided, names, count);
        for (int agent = 0; agent < market.size(); ++agent) {
            Preference preference = agent < count ? sequence(count, 2 * count) : sequence(0, count);
            for (int length = count; length >= 2; --length) {
                state = 48271 * state % 2147483647;
                int index = static_cast<int>(state % length);
                std::swap(preference[length - 1], preference[index]);
            }
            market.preferences[agent] = preference;
        }
        return market;
    }
    Kind kind = command == "ROOMS" ? Kind::Roommate : command == "HOUSES" ? Kind::Housing : Kind::TwoSided;
    vector<string> names, houses;
    int proposers = 0;
    for (const string& word : args) {
        if (word == "|") { proposers = static_cast<int>(names.size()); continue; }
        vector<string> pair = split(word, ':');
        if (position_of(names, pair[0]) >= 0) fail("DUPLICATE AGENT " + pair[0]);
        if (kind == Kind::Housing) {
            if (position_of(houses, pair[1]) >= 0) fail("DUPLICATE HOUSE " + pair[1]);
            houses.push_back(pair[1]);
        }
        names.push_back(pair[0]);
    }
    return Market(name, kind, names, proposers, houses);
}
class Laboratory {
    std::map<string, Market> markets_;
public:
    vector<string> execute(const string& line) {
        vector<string> words = split(line);
        string command = words[0], name = words[1];
        vector<string> args(words.begin() + 2, words.end());
        if (command == "MARKET" || command == "ROOMS" || command == "HOUSES" || command == "RANDOM") {
            if (markets_.count(name)) fail("DUPLICATE MARKET " + name);
            Market market = new_market(command, name, args);
            string response;
            if (command == "RANDOM") response = "RANDOM " + name + " n=" + to_string(market.proposers) + " seed=" + args[1];
            else if (command == "MARKET") response = "MARKET " + name + " proposers=" + to_string(market.proposers) + " receivers=" + to_string(market.size() - market.proposers);
            else response = command + " " + name + " agents=" + to_string(market.size());
            markets_.emplace(name, std::move(market));
            return {response};
        }
        auto found = markets_.find(name);
        if (found == markets_.end()) fail("UNKNOWN MARKET " + name);
        Market& market = found->second;
        if (command == "SHOW") return show_market(market);
        if (command == "PREF") {
            int agent = market.agent(args[0]);
            const vector<string>& names = market.kind == Kind::Housing ? market.houses : market.names;
            Preference preference;
            for (std::size_t i = 1; i < args.size(); ++i) {
                int choice = position_of(names, args[i]);
                if (choice < 0 || (market.kind == Kind::Roommate && choice == agent)
                    || (market.kind == Kind::TwoSided && ((agent < market.proposers) == (choice < market.proposers)))) fail("BAD CHOICE " + args[i]);
                if (position_of(preference, choice) >= 0) fail("DUPLICATE CHOICE " + args[i]);
                preference.push_back(choice);
            }
            market.preferences[agent] = preference;
            if (market.kind == Kind::TwoSided) market.current.reset();
            return {"PREF " + name + " " + args[0] + " length=" + to_string(preference.size())};
        }
        if (command == "CHECK") return check_pairs(market, args);
        if (command == "ROOMMATES") return roommates(market, args.size() == 1);
        if (command == "TTC" || command == "SERIAL") {
            market.require_kind(Kind::Housing);
            return command == "TTC" ? ttc(market) : serial(market, args);
        }
        market.require_kind(Kind::TwoSided);
        if (command == "CAPACITY") {
            int receiver = market.agent(args[0], Side::Receiver), capacity = std::stoi(args[1]);
            market.capacities[receiver] = capacity;
            market.current.reset();
            return {"CAPACITY " + name + " " + args[0] + " " + to_string(capacity)};
        }
        if (command == "GS" || command == "GSR") {
            DeferredResult run = deferred(market, command == "GSR", args.size() == 1);
            market.current = Saved{command, run.matching};
            vector<string> result{command + " " + name + " proposals=" + to_string(run.proposals)};
            result.insert(result.end(), run.history.begin(), run.history.end());
            result.push_back("MATCHING " + pair_text(market, run.matching));
            return result;
        }
        if (command == "BOSTON") {
            BostonResult run = boston(market);
            market.current = Saved{command, run.matching};
            return {"BOSTON " + name + " applications=" + to_string(run.applications), "MATCHING " + pair_text(market, run.matching)};
        }
        if (command == "HR") return hospital_report(market);
        if (command == "MANIPULATE") return manipulate(market, market.agent(args[0], Side::Proposer));
        if (command == "STATS") return statistics(market);
        Lattice lattice = enumerate(market);
        if (command == "LATTICE") {
            vector<string> result{"LATTICE " + name + " matchings=" + to_string(lattice.entries.size()) + " rotations=" + to_string(lattice.rotations.size())};
            for (std::size_t i = 0; i < lattice.entries.size(); ++i) {
                const Entry& entry = lattice.entries[i];
                Metrics measure = metrics(market, entry.matching);
                string origin = i == 0 ? "-" : to_string(entry.origin), via = i == 0 ? "-" : to_string(entry.via);
                result.push_back("MATCHING " + to_string(i + 1) + " from=" + origin + " via=" + via + " cost=" + to_string(measure.cost)
                    + " regret=" + to_string(measure.regret) + " " + pair_text(market, entry.matching));
            }
            for (std::size_t i = 0; i < lattice.rotations.size(); ++i) result.push_back("ROTATION " + to_string(i + 1) + " " + lattice.rotations[i]);
            return result;
        }
        vector<int> values;
        for (const Entry& entry : lattice.entries) {
            Metrics measure = metrics(market, entry.matching);
            values.push_back(command == "EGALITARIAN" ? measure.cost : measure.regret);
        }
        int best = static_cast<int>(std::min_element(values.begin(), values.end()) - values.begin());
        const Matching& matching = lattice.entries[best].matching;
        market.current = Saved{command, matching};
        string label = command == "EGALITARIAN" ? "cost" : "regret";
        return {command + " " + name + " matching=" + to_string(best + 1) + " " + label + "=" + to_string(values[best]), "MATCHING " + pair_text(market, matching)};
    }
};

int main() {
    std::ios::sync_with_stdio(false);
    std::cin.tie(nullptr);
    int count;
    std::cin >> count;
    string line;
    std::getline(std::cin, line);
    Laboratory laboratory;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        try {
            for (const string& result : laboratory.execute(line)) std::cout << result << '\n';
        } catch (const CommandError& error) {
            std::cout << "ERROR " << error.what() << '\n';
        }
    }
}
