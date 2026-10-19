#include <algorithm>
#include <array>
#include <cmath>
#include <functional>
#include <iostream>
#include <limits>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using namespace std;

using Number = long long;

struct Item {
    int id;
    int size;
};

struct Bin {
    vector<Item> items;
    int load = 0;
    int category = 0;

    void put(Item item) {
        items.push_back(item);
        load += item.size;
    }
};

struct Step {
    Item item;
    int bin;
    int inspections;
    bool opened;
    int closed;
    int category;
};

struct Packing {
    string method;
    int parameter;
    vector<Bin> bins;
    vector<Step> steps;
    int inspections = 0;
    int closes = 0;

    string name() const {
        return method + (method == "HARMONIC" || method == "KBOUNDED"
                         ? " k=" + to_string(parameter) : "");
    }

    string header(int capacity, Number total) const {
        string text = name() + " bins=" + to_string(bins.size()) +
                      " inspections=" + to_string(inspections) +
                      " waste=" + to_string(static_cast<Number>(bins.size()) * capacity - total);
        if (method == "KBOUNDED") text += " closes=" + to_string(closes);
        return text;
    }
};

struct BoundRow {
    int alpha;
    int j1;
    int j2;
    int j3;
    int bound;
};

struct Bounds {
    int l1;
    int l2;
    vector<BoundRow> rows;
};

struct Rectangle {
    int id;
    int width;
    int height;
};

struct Placement {
    int id;
    int x;
    int y;
    int width;
    int height;
    bool rotated = false;
};

struct Shelf {
    int bottom;
    int height;
    int used = 0;
    vector<pair<int, int>> items;
};

struct FreeRectangle {
    int x;
    int y;
    int width;
    int height;
};

struct Sheet {
    vector<FreeRectangle> free;
    vector<Placement> placements;
    int area = 0;
};

constexpr array<const char*, 10> METHODS = {
    "NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
    "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD"
};

int ceiling(Number numerator, Number denominator) {
    return static_cast<int>((numerator + denominator - 1) / denominator);
}

string item_text(const Item& item) {
    return to_string(item.id) + ":" + to_string(item.size);
}

vector<Item> descending(vector<Item> items) {
    stable_sort(items.begin(), items.end(), [](const Item& a, const Item& b) {
        return a.size != b.size ? a.size > b.size : a.id < b.id;
    });
    return items;
}

Number total_size(const vector<Item>& items) {
    Number sum = 0;
    for (const Item& item : items) sum += item.size;
    return sum;
}

Packing pack(const vector<Item>& items, int capacity, const string& method, int parameter = 0) {
    Packing result{method, parameter};
    const vector<Item> ordered = (method == "FFD" || method == "BFD" || method == "WFD")
        ? descending(items) : items;
    vector<int> active;
    map<int, int> current;

    for (const Item& item : ordered) {
        const int before = result.inspections;
        int chosen = -1;
        int closed = -1;
        int category = 0;
        const int count = static_cast<int>(result.bins.size());
        if (method == "NEXTFIT") {
            if (count) {
                ++result.inspections;
                if (result.bins.back().load + item.size <= capacity)
                    chosen = count - 1;
            }
        } else if (method == "FIRSTFIT" || method == "FFD" || method == "KBOUNDED") {
            vector<int> candidates;
            if (method == "KBOUNDED") {
                candidates = active;
            } else {
                for (int index = 0; index < count; ++index) candidates.push_back(index);
            }
            for (int index : candidates) {
                ++result.inspections;
                if (result.bins[index].load + item.size <= capacity) {
                    chosen = index;
                    break;
                }
            }
        } else if (method == "HARMONIC") {
            category = min(capacity / item.size, parameter);
            auto it = current.find(category);
            if (it != current.end()) {
                ++result.inspections;
                if (result.bins[it->second].load + item.size <= capacity)
                    chosen = it->second;
            }
        } else {
            result.inspections += count;
            vector<int> fitting;
            for (int index = 0; index < count; ++index) {
                if (result.bins[index].load + item.size <= capacity)
                    fitting.push_back(index);
            }
            if (!fitting.empty()) {
                if (method == "BESTFIT" || method == "BFD") {
                    chosen = fitting.front();
                    for (int index : fitting) {
                        if (result.bins[index].load > result.bins[chosen].load)
                            chosen = index;
                    }
                } else {
                    sort(fitting.begin(), fitting.end(), [&](int a, int b) {
                        return tie(result.bins[a].load, a) < tie(result.bins[b].load, b);
                    });
                    chosen = method == "ALMOSTWORST" && fitting.size() >= 2
                        ? fitting[1] : fitting[0];
                }
            }
        }
        bool opened = chosen == -1;
        if (opened) {
            if (method == "KBOUNDED" && static_cast<int>(active.size()) == parameter) {
                closed = active.front();
                for (int index : active) {
                    if (result.bins[index].load > result.bins[closed].load)
                        closed = index;
                }
                active.erase(find(active.begin(), active.end(), closed));
                ++result.closes;
            }
            chosen = static_cast<int>(result.bins.size());
            Bin bin;
            bin.category = category;
            result.bins.push_back(move(bin));
            if (method == "KBOUNDED") active.push_back(chosen);
            if (method == "HARMONIC") current[category] = chosen;
        }
        result.bins[chosen].put(item);
        result.steps.push_back({
            item, chosen, result.inspections - before, opened, closed, category
        });
    }
    return result;
}

Bounds bounds(const vector<Item>& items, int capacity) {
    set<int> thresholds{0};
    for (const Item& item : items)
        if (2 * item.size <= capacity) thresholds.insert(item.size);
    Bounds result{ceiling(total_size(items), capacity), 0, {}};
    for (int alpha : thresholds) {
        int first = 0, second = 0, third = 0;
        Number total_second = 0, total_third = 0;
        for (const Item& item : items) {
            int size = item.size;
            if (size > capacity - alpha) {
                ++first;
            } else if (2 * size > capacity) {
                ++second;
                total_second += size;
            }
            if (2 * size <= capacity && size >= alpha) {
                ++third;
                total_third += size;
            }
        }
        Number excess = total_third - (static_cast<Number>(second) * capacity - total_second);
        int bound = first + second + (excess > 0 ? ceiling(excess, capacity) : 0);
        result.l2 = max(result.l2, bound);
        result.rows.push_back({alpha, first, second, third, bound});
    }
    return result;
}

class ExactSearch {
    vector<Item> ordered;
    int capacity;
    int limit;
    int lower;
    vector<Number> remaining;
    vector<Bin> live;
    function<void(string)> emit;

    void visit(int index) {
        if (nodes == limit) {
            status = "limit";
            return;
        }
        ++nodes;
        int count = static_cast<int>(live.size());
        Number used = remaining.front() - remaining[index];
        Number free = static_cast<Number>(count) * capacity - used;
        Number excess = remaining[index] - free;
        int minimum = count + (excess > 0 ? ceiling(excess, capacity) : 0);
        if (minimum >= static_cast<int>(best.size())) return;
        if (index == static_cast<int>(ordered.size())) {
            best = live;
            emit("IMPROVE bins=" + to_string(count) + " nodes=" + to_string(nodes));
            if (count == lower) status = "bound";
            return;
        }
        const Item item = ordered[index];
        set<int> seen_loads;
        for (Bin& bin : live) {
            int old_load = bin.load;
            if (!seen_loads.insert(old_load).second || old_load + item.size > capacity)
                continue;
            bin.put(item);
            visit(index + 1);
            bin.items.pop_back();
            bin.load = old_load;
            if (!status.empty()) return;
        }
        if (count + 1 < static_cast<int>(best.size())) {
            Bin bin;
            bin.put(item);
            live.push_back(move(bin));
            visit(index + 1);
            live.pop_back();
        }
    }

public:
    vector<Bin> best;
    int nodes = 0;
    string status;

    ExactSearch(const vector<Item>& items, int capacity, int limit,
                int lower, vector<Bin> incumbent,
                function<void(string)> output)
        : ordered(descending(items)), capacity(capacity), limit(limit),
          lower(lower), remaining(items.size() + 1, 0),
          emit(move(output)), best(move(incumbent)) {
        for (int index = static_cast<int>(ordered.size()) - 1; index >= 0; --index)
            remaining[index] = remaining[index + 1] + ordered[index].size;
    }

    void run() {
        if (static_cast<int>(best.size()) == lower) status = "bound";
        else visit(0);
        if (status.empty()) status = "complete";
    }
};

class PackingLab {
    vector<Item> items;
    int capacity = 0;
    bool has_items = false;
    vector<string> output;

    template <typename... T>
    void emit(const T&... args) {
        ostringstream stream;
        bool first = true;
        ((stream << (first ? "" : " ") << args, first = false), ...);
        output.push_back(stream.str());
    }

    static void fail(const string& error) { throw runtime_error(error); }
    static int integer(const string& text) { return stoi(text); }
    Number total() const { return total_size(items); }

    void bin_line(int number, const Bin& bin, int cap,
                  bool classes = false, bool over = false) {
        ostringstream out;
        out << "BIN " << number << " load=" << bin.load << '/' << cap << " items=";
        for (size_t i = 0; i < bin.items.size(); ++i) {
            if (i) out << ' ';
            out << item_text(bin.items[i]);
        }
        if (classes) out << " class=" << bin.category;
        if (over) out << " OVER";
        emit(out.str());
    }

    void bin_lines(const vector<Bin>& bins, bool classes = false) {
        for (size_t i = 0; i < bins.size(); ++i)
            bin_line(static_cast<int>(i) + 1, bins[i], capacity, classes);
    }

    Packing method(const string& name, const vector<string>& arguments) {
        int parameter = name == "HARMONIC" || name == "KBOUNDED"
            ? integer(arguments[0]) : 0;
        if ((name == "HARMONIC" || name == "KBOUNDED") && parameter == 0)
            fail("BAD PARAMETER");
        return pack(items, capacity, name, parameter);
    }

    void items_command(const vector<string>& arguments) {
        int next_capacity = integer(arguments[0]);
        if (next_capacity == 0) fail("BAD CAPACITY");
        vector<Item> selected;
        for (size_t i = 1; i < arguments.size(); ++i) {
            int size = integer(arguments[i]);
            if (size == 0 || size > next_capacity)
                fail("BAD ITEM " + to_string(i));
            selected.push_back({static_cast<int>(i), size});
        }
        capacity = next_capacity;
        items = move(selected);
        has_items = true;
        emit("ITEMS count=" + to_string(items.size()) +
             " capacity=" + to_string(capacity) + " total=" + to_string(total()));
    }

    void random_command(const vector<string>& arguments) {
        int count = integer(arguments[0]);
        int next_capacity = integer(arguments[1]);
        Number value = stoll(arguments[2]);
        if (count == 0 || count > 40) fail("BAD COUNT");
        if (next_capacity == 0) fail("BAD CAPACITY");
        if (value == 0 || value >= 2147483647) fail("BAD SEED");
        vector<Item> selected;
        for (int index = 1; index <= count; ++index) {
            value = 48271 * value % 2147483647;
            selected.push_back({index, static_cast<int>(value % next_capacity + 1)});
        }
        capacity = next_capacity;
        items = move(selected);
        has_items = true;
        emit("RANDOM count=" + to_string(count) +
             " capacity=" + to_string(capacity) + " total=" + to_string(total()));
        string sizes = "SIZES";
        for (const Item& item : items) sizes += " " + to_string(item.size);
        emit(sizes);
    }

    void run_method(const string& name, const vector<string>& arguments) {
        Packing result = method(name, arguments);
        emit(result.header(capacity, total()));
        bin_lines(result.bins, name == "HARMONIC");
    }

    void trace(const vector<string>& arguments) {
        vector<string> extra(arguments.begin() + 1, arguments.end());
        Packing result = method(arguments.front(), extra);
        emit("TRACE " + result.header(capacity, total()));
        for (size_t i = 0; i < result.steps.size(); ++i) {
            const Step& step = result.steps[i];
            string text = "STEP " + to_string(i + 1) + " item=" + item_text(step.item) +
                          " bin=" + to_string(step.bin + 1) +
                          " inspected=" + to_string(step.inspections);
            if (step.opened) text += " new";
            if (step.closed != -1) text += " closed=" + to_string(step.closed + 1);
            if (step.category) text += " class=" + to_string(step.category);
            emit(text);
        }
    }

    void reduce(const vector<string>& arguments) {
        vector<string> extra(arguments.begin() + 1, arguments.end());
        Packing result = method(arguments.front(), extra);
        vector<Bin>& bins = result.bins;
        int before = static_cast<int>(bins.size());
        vector<string> events;
        while (true) {
            bool eliminated = false;
            vector<int> sources;
            for (int i = 0; i < static_cast<int>(bins.size()); ++i)
                sources.push_back(i);
            sort(sources.begin(), sources.end(), [&](int a, int b) {
                return tie(bins[a].load, a) < tie(bins[b].load, b);
            });
            for (int source : sources) {
                vector<int> loads;
                for (const Bin& bin : bins) loads.push_back(bin.load);
                vector<pair<Item, int>> moves;
                bool possible = true;
                for (const Item& item : descending(bins[source].items)) {
                    int destination = -1;
                    for (int i = 0; i < static_cast<int>(bins.size()); ++i) {
                        if (i == source || loads[i] + item.size > capacity) continue;
                        if (destination == -1 || loads[i] > loads[destination])
                            destination = i;
                    }
                    if (destination == -1) {
                        possible = false;
                        break;
                    }
                    loads[destination] += item.size;
                    moves.emplace_back(item, destination);
                }
                if (!possible) continue;
                string event = "ELIMINATE bin=" + to_string(source + 1) +
                               " load=" + to_string(bins[source].load) + " moves=";
                for (size_t i = 0; i < moves.size(); ++i) {
                    if (i) event += " ";
                    event += item_text(moves[i].first) + "->" + to_string(moves[i].second + 1);
                }
                events.push_back(move(event));
                for (const auto& [item, destination] : moves)
                    bins[destination].put(item);
                bins.erase(bins.begin() + source);
                eliminated = true;
                break;
            }
            if (!eliminated) break;
        }
        emit("REDUCE " + result.name() + " before=" + to_string(before) +
             " after=" + to_string(bins.size()) +
             " eliminated=" + to_string(before - static_cast<int>(bins.size())));
        for (const string& event : events) emit(event);
        bin_lines(bins, arguments[0] == "HARMONIC");
    }

    void show_bounds() {
        Bounds result = bounds(items, capacity);
        emit("BOUNDS total=" + to_string(total()) + " L1=" + to_string(result.l1) +
             " L2=" + to_string(result.l2));
        for (const BoundRow& row : result.rows) {
            emit("ALPHA " + to_string(row.alpha) + " j1=" + to_string(row.j1) +
                 " j2=" + to_string(row.j2) + " j3=" + to_string(row.j3) +
                 " bound=" + to_string(row.bound));
        }
    }

    void compare(const vector<string>& arguments) {
        int parameter = integer(arguments[0]);
        if (parameter == 0) fail("BAD PARAMETER");
        Bounds lower = bounds(items, capacity);
        vector<Packing> results;
        for (const char* name : METHODS) results.push_back(pack(items, capacity, name, parameter));
        sort(results.begin(), results.end(), [](const Packing& a, const Packing& b) {
            return a.bins.size() != b.bins.size() ? a.bins.size() < b.bins.size()
                                                  : a.method < b.method;
        });
        emit("COMPARE k=" + to_string(parameter) + " L1=" + to_string(lower.l1) +
             " L2=" + to_string(lower.l2));
        for (const Packing& result : results) {
            int count = static_cast<int>(result.bins.size());
            emit(result.method + " bins=" + to_string(count) +
                 " gap=" + to_string(count - lower.l2) +
                 " waste=" + to_string(static_cast<Number>(count) * capacity - total()) +
                 " inspections=" + to_string(result.inspections));
        }
    }

    void exact(const vector<string>& arguments) {
        int limit = integer(arguments[0]);
        if (limit == 0) fail("BAD PARAMETER");
        if (items.size() >= 21) fail("TOO MANY ITEMS");
        vector<Bin> incumbent = pack(items, capacity, "FFD").bins;
        int lower = bounds(items, capacity).l2;
        emit("EXACT ffd=" + to_string(incumbent.size()) + " L2=" + to_string(lower));
        ExactSearch search(items, capacity, limit, lower, move(incumbent),
                           [this](const string& message) { emit(message); });
        search.run();
        emit("RESULT bins=" + to_string(search.best.size()) +
             " nodes=" + to_string(search.nodes) + " status=" + search.status);
        bin_lines(search.best);
    }

    void check(const vector<string>& arguments) {
        if (arguments.size() != items.size()) fail("BAD ASSIGNMENT");
        map<int, Bin> bins;
        for (size_t i = 0; i < arguments.size(); ++i) {
            int label = integer(arguments[i]);
            if (label == 0) fail("BAD ASSIGNMENT");
            bins[label].put(items[i]);
        }
        int overfull = 0;
        for (const auto& [label, bin] : bins) overfull += bin.load > capacity;
        int lower = bounds(items, capacity).l2;
        emit("CHECK bins=" + to_string(bins.size()) + " over=" + to_string(overfull) +
             " L2=" + to_string(lower) +
             " status=" + (overfull ? string("invalid") : string("valid")));
        for (const auto& [label, bin] : bins)
            bin_line(label, bin, capacity, false, bin.load > capacity);
    }

    void cover_lines(const string& name, const vector<Bin>& bins) {
        vector<Bin> covered;
        const Bin* rest = nullptr;
        for (const Bin& bin : bins) {
            if (bin.load >= capacity) covered.push_back(bin);
            else rest = &bin;
        }
        emit(name + " covered=" + to_string(covered.size()) +
             " rest=" + to_string(rest ? rest->load : 0));
        bin_lines(covered);
        if (rest) {
            string text = "REST items=";
            for (size_t i = 0; i < rest->items.size(); ++i) {
                if (i) text += " ";
                text += item_text(rest->items[i]);
            }
            emit(text);
        }
    }

    void cover() {
        emit("COVER total=" + to_string(total()) +
             " upper=" + to_string(total() / capacity));
        vector<Bin> sequential;
        for (const Item& item : items) {
            if (sequential.empty() || sequential.back().load >= capacity)
                sequential.emplace_back();
            sequential.back().put(item);
        }
        cover_lines("DNF", sequential);

        vector<Item> available = descending(items);
        vector<Bin> paired;
        while (!available.empty()) {
            Bin bin;
            bin.put(available.front());
            available.erase(available.begin());
            while (bin.load < capacity && !available.empty()) {
                bin.put(available.back());
                available.pop_back();
            }
            paired.push_back(move(bin));
        }
        cover_lines("BIGSMALL", paired);
    }

    void machine_lines(const vector<Bin>& machines) {
        for (size_t i = 0; i < machines.size(); ++i) {
            const Bin& bin = machines[i];
            string text = "MACHINE " + to_string(i + 1) + " load=" + to_string(bin.load) +
                          " items=";
            if (bin.items.empty()) text += "-";
            for (size_t j = 0; j < bin.items.size(); ++j) {
                if (j) text += " ";
                text += item_text(bin.items[j]);
            }
            emit(text);
        }
    }

    void multifit(const vector<string>& arguments) {
        int count = integer(arguments[0]);
        if (count == 0) fail("BAD PARAMETER");
        int largest = 0;
        for (const Item& item : items) largest = max(largest, item.size);
        int lower = max(ceiling(total(), count), largest);
        int upper = max(ceiling(2 * total(), count), largest);
        emit("MULTIFIT m=" + to_string(count) + " lower=" + to_string(lower) +
             " upper=" + to_string(upper));
        while (lower < upper) {
            int middle = (lower + upper) / 2;
            int n = static_cast<int>(pack(items, middle, "FFD").bins.size());
            bool success = n <= count;
            emit("TRY cap=" + to_string(middle) + " bins=" + to_string(n) +
                 (success ? " ok" : " fail"));
            if (success) upper = middle;
            else lower = middle + 1;
        }
        vector<Bin> machines = pack(items, upper, "FFD").bins;
        machines.resize(count);
        int makespan = 0;
        for (const Bin& bin : machines) makespan = max(makespan, bin.load);
        emit("RESULT cap=" + to_string(upper) + " makespan=" + to_string(makespan));
        machine_lines(machines);

        vector<Bin> lpt(count);
        for (const Item& item : descending(items)) {
            int chosen = 0;
            for (int i = 1; i < count; ++i)
                if (lpt[i].load < lpt[chosen].load) chosen = i;
            lpt[chosen].put(item);
        }
        makespan = 0;
        for (const Bin& bin : lpt) makespan = max(makespan, bin.load);
        emit("LPT makespan=" + to_string(makespan));
        machine_lines(lpt);
    }

    struct Pattern {
        vector<int> counts;
        int trim;
    };

    static vector<Pattern> maximal_patterns(int length, const vector<pair<int, int>>& pieces) {
        vector<Pattern> patterns;
        vector<int> prefix;
        function<void(int, int)> enumerate = [&](int index, int remaining) {
            int size = pieces[index].first;
            int maximum = remaining / size;
            if (index + 1 == static_cast<int>(pieces.size())) {
                prefix.push_back(maximum);
                patterns.push_back({prefix, remaining - maximum * size});
                prefix.pop_back();
                return;
            }
            for (int count = maximum; count >= 0; --count) {
                prefix.push_back(count);
                enumerate(index + 1, remaining - count * size);
                prefix.pop_back();
            }
        };
        enumerate(0, length);
        return patterns;
    }

    void cutstock(const vector<string>& arguments) {
        int length = integer(arguments[0]);
        if (length == 0) fail("BAD CAPACITY");
        vector<pair<int, int>> pieces;
        set<int> seen;
        for (size_t i = 1; i < arguments.size(); ++i) {
            const string& token = arguments[i];
            size_t colon = token.find(':');
            int size = integer(token.substr(0, colon));
            int demand = integer(token.substr(colon + 1));
            if (size == 0 || size > length || demand == 0)
                fail("BAD PIECE " + to_string(i));
            if (!seen.insert(size).second)
                fail("DUPLICATE PIECE " + to_string(i));
            pieces.emplace_back(size, demand);
        }
        sort(pieces.begin(), pieces.end(), greater<pair<int, int>>());
        vector<Pattern> patterns = maximal_patterns(length, pieces);
        vector<int> remaining;
        for (const auto& [size, demand] : pieces) remaining.push_back(demand);
        vector<int> uses(patterns.size(), 0);
        while (any_of(remaining.begin(), remaining.end(), [](int x) { return x > 0; })) {
            int chosen = 0, best = -1;
            for (int index = 0; index < static_cast<int>(patterns.size()); ++index) {
                int useful = 0;
                for (size_t j = 0; j < pieces.size(); ++j)
                    useful += min(patterns[index].counts[j], remaining[j]);
                if (useful > best) {
                    best = useful;
                    chosen = index;
                }
            }
            ++uses[chosen];
            for (size_t j = 0; j < pieces.size(); ++j)
                remaining[j] = max(0, remaining[j] - patterns[chosen].counts[j]);
        }
        vector<int> cut(pieces.size(), 0);
        for (size_t i = 0; i < patterns.size(); ++i)
            for (size_t j = 0; j < pieces.size(); ++j)
                cut[j] += uses[i] * patterns[i].counts[j];
        Number quantity = 0;
        for (const auto& [size, demand] : pieces)
            quantity += static_cast<Number>(size) * demand;
        int bars = accumulate(uses.begin(), uses.end(), 0);

        emit("CUTSTOCK L=" + to_string(length) + " pieces=" +
             to_string(pieces.size()) + " patterns=" + to_string(patterns.size()));
        for (size_t i = 0; i < patterns.size(); ++i) {
            const Pattern& pattern = patterns[i];
            string breakdown;
            for (size_t j = 0; j < pieces.size(); ++j) {
                int count = pattern.counts[j];
                if (count) {
                    if (!breakdown.empty()) breakdown += "+";
                    breakdown += to_string(count) + "x" + to_string(pieces[j].first);
                }
            }
            emit("PATTERN " + to_string(i + 1) + " " + breakdown +
                 " rest=" + to_string(pattern.trim));
        }
        for (size_t i = 0; i < uses.size(); ++i)
            if (uses[i]) emit("USE " + to_string(i + 1) + " bars=" + to_string(uses[i]));
        for (size_t j = 0; j < pieces.size(); ++j) {
            emit("PIECE " + to_string(pieces[j].first) +
                 " demand=" + to_string(pieces[j].second) + " cut=" + to_string(cut[j]));
        }
        Number trim = 0, surplus = 0;
        for (size_t i = 0; i < patterns.size(); ++i)
            trim += static_cast<Number>(uses[i]) * patterns[i].trim;
        for (size_t j = 0; j < pieces.size(); ++j)
            surplus += cut[j] - pieces[j].second;
        emit("TOTAL bars=" + to_string(bars) + " trim=" + to_string(trim) +
             " surplus=" + to_string(surplus) +
             " waste=" + to_string(static_cast<Number>(bars) * length - quantity));

        vector<Item> expanded;
        for (const auto& [size, demand] : pieces) {
            for (int j = 0; j < demand; ++j)
                expanded.push_back({static_cast<int>(expanded.size()) + 1, size});
        }
        int comparison = static_cast<int>(pack(expanded, length, "FIRSTFIT").bins.size());
        emit("FFD bars=" + to_string(comparison) +
             " waste=" + to_string(static_cast<Number>(comparison) * length - quantity));
        emit("LOWER bars=" + to_string(ceiling(quantity, length)));
    }

    static vector<Rectangle> rectangles(const vector<string>& tokens, size_t first) {
        vector<Rectangle> result;
        for (size_t i = first; i < tokens.size(); ++i) {
            size_t middle = tokens[i].find('x');
            int width = integer(tokens[i].substr(0, middle));
            int height = integer(tokens[i].substr(middle + 1));
            result.push_back({static_cast<int>(i - first + 1), width, height});
        }
        return result;
    }

    void drawing(int width, int height, const vector<Placement>& placements) {
        vector<string> cells(height, string(width, '.'));
        for (const Placement& p : placements)
            for (int y = p.y; y < p.y + p.height; ++y)
                for (int x = p.x; x < p.x + p.width; ++x)
                    cells[y][x] = static_cast<char>('A' + p.id - 1);
        for (int row = height - 1; row >= 0; --row) emit(cells[row]);
    }

    void shelf_method(const string& method, int width,
                      const vector<Rectangle>& rectangles, int area) {
        vector<Shelf> shelves;
        vector<Placement> placements;
        for (const Rectangle& rectangle : rectangles) {
            int chosen = -1;
            if (method == "NFDH") {
                if (!shelves.empty() &&
                    shelves.back().used + rectangle.width <= width)
                    chosen = static_cast<int>(shelves.size()) - 1;
            } else {
                for (int i = 0; i < static_cast<int>(shelves.size()); ++i) {
                    if (shelves[i].used + rectangle.width > width) continue;
                    if (chosen == -1 || (method == "BFDH" && shelves[i].used > shelves[chosen].used))
                        chosen = i;
                    if (method == "FFDH") break;
                }
            }
            if (chosen == -1) {
                int bottom = shelves.empty() ? 0 : shelves.back().bottom + shelves.back().height;
                chosen = static_cast<int>(shelves.size());
                shelves.push_back({bottom, rectangle.height});
            }
            Shelf& shelf = shelves[chosen];
            shelf.items.emplace_back(rectangle.id, shelf.used);
            placements.push_back({
                rectangle.id, shelf.used, shelf.bottom, rectangle.width, rectangle.height, false
            });
            shelf.used += rectangle.width;
        }
        int height = shelves.back().bottom + shelves.back().height;
        emit(method + " height=" + to_string(height) +
             " shelves=" + to_string(shelves.size()) +
             " util=" + to_string(static_cast<Number>(area) * 100 / (width * height)));
        for (size_t i = 0; i < shelves.size(); ++i) {
            const Shelf& shelf = shelves[i];
            string line = "LEVEL " + to_string(i + 1) + " y=" + to_string(shelf.bottom) +
                          " h=" + to_string(shelf.height) +
                          " used=" + to_string(shelf.used) + " items=";
            for (size_t j = 0; j < shelf.items.size(); ++j) {
                if (j) line += " ";
                line += string(1, static_cast<char>('A' + shelf.items[j].first - 1)) +
                        "@" + to_string(shelf.items[j].second);
            }
            emit(line);
        }
        drawing(width, height, placements);
    }

    void shelf(const vector<string>& arguments) {
        int width = integer(arguments[0]);
        if (width == 0) fail("BAD CAPACITY");
        vector<Rectangle> ordered = rectangles(arguments, 1);
        for (const Rectangle& rectangle : ordered) {
            if (rectangle.width == 0 || rectangle.height == 0 || rectangle.width > width)
                fail("BAD RECT " + to_string(rectangle.id));
        }
        sort(ordered.begin(), ordered.end(), [](const Rectangle& a, const Rectangle& b) {
            return tie(a.height, a.width, b.id) > tie(b.height, b.width, a.id);
        });
        int area = 0;
        for (const Rectangle& rectangle : ordered)
            area += rectangle.width * rectangle.height;
        emit("SHELF W=" + to_string(width) +
             " rects=" + to_string(ordered.size()) + " area=" + to_string(area));
        for (const string& method : {"NFDH", "FFDH", "BFDH"})
            shelf_method(method, width, ordered, area);

        vector<int> heights(width, 0);
        vector<Placement> placements;
        for (const Rectangle& rectangle : ordered) {
            int best = numeric_limits<int>::max();
            int x = 0;
            for (int candidate = 0; candidate <= width - rectangle.width; ++candidate) {
                int y = *max_element(heights.begin() + candidate,
                                     heights.begin() + candidate + rectangle.width);
                if (y < best) {
                    best = y;
                    x = candidate;
                }
            }
            fill(heights.begin() + x, heights.begin() + x + rectangle.width,
                 best + rectangle.height);
            placements.push_back({
                rectangle.id, x, best, rectangle.width, rectangle.height, false
            });
        }
        int height = *max_element(heights.begin(), heights.end());
        emit("SKYLINE height=" + to_string(height) +
             " util=" + to_string(static_cast<Number>(area) * 100 / (width * height)));
        for (const Placement& p : placements) {
            emit("PLACE " + string(1, static_cast<char>('A' + p.id - 1)) +
                 " x=" + to_string(p.x) + " y=" + to_string(p.y) +
                 " w=" + to_string(p.width) + " h=" + to_string(p.height));
        }
        drawing(width, height, placements);
    }

    static optional<pair<int, int>> free_rectangle(const vector<Sheet>& sheets,
                                                   int width, int height,
                                                   bool rotate, const string& rule) {
        optional<pair<int, int>> chosen;
        tuple<Number, int, int> best;
        for (int sheet = 0; sheet < static_cast<int>(sheets.size()); ++sheet) {
            for (int i = 0; i < static_cast<int>(sheets[sheet].free.size()); ++i) {
                const FreeRectangle& r = sheets[sheet].free[i];
                bool fits = width <= r.width && height <= r.height;
                bool rotated = rotate && height <= r.width && width <= r.height;
                if (!fits && !rotated) continue;
                if (rule == "FIRST") return pair{sheet, i};
                auto key = make_tuple(static_cast<Number>(r.width) * r.height, sheet, i);
                if (!chosen || key < best) {
                    chosen = pair{sheet, i};
                    best = key;
                }
            }
        }
        return chosen;
    }

    void guillotine(const vector<string>& arguments) {
        int width = integer(arguments[0]), height = integer(arguments[1]);
        const string& mode = arguments[2], &rule = arguments[3];
        if (width == 0 || height == 0) fail("BAD CAPACITY");
        vector<Rectangle> ordered = rectangles(arguments, 4);
        bool rotate = mode == "ROTATE";
        for (const Rectangle& rectangle : ordered) {
            bool fits = rectangle.width <= width && rectangle.height <= height;
            bool rotated = rotate && rectangle.height <= width && rectangle.width <= height;
            if (rectangle.width == 0 || rectangle.height == 0 || (!fits && !rotated))
                fail("BAD RECT " + to_string(rectangle.id));
        }
        sort(ordered.begin(), ordered.end(), [](const Rectangle& a, const Rectangle& b) {
            int aa = a.width * a.height, bb = b.width * b.height;
            return aa != bb ? aa > bb : a.id < b.id;
        });
        vector<Sheet> sheets;
        int rotated_count = 0;
        for (const Rectangle& rectangle : ordered) {
            auto choice = free_rectangle(sheets, rectangle.width, rectangle.height, rotate, rule);
            if (!choice) {
                Sheet sheet;
                sheet.free.push_back({0, 0, width, height});
                sheets.push_back(move(sheet));
                choice = pair{static_cast<int>(sheets.size()) - 1, 0};
            }
            auto [sheet_number, index] = *choice;
            Sheet& sheet = sheets[sheet_number];
            FreeRectangle region = sheet.free[index];
            sheet.free.erase(sheet.free.begin() + index);
            bool rotated = !(rectangle.width <= region.width &&
                             rectangle.height <= region.height);
            int pw = rotated ? rectangle.height : rectangle.width;
            int ph = rotated ? rectangle.width : rectangle.height;
            rotated_count += rotated;
            sheet.placements.push_back({
                rectangle.id, region.x, region.y, pw, ph, rotated
            });
            sheet.area += rectangle.width * rectangle.height;
            int rw = region.width - pw, rh = region.height - ph;
            FreeRectangle top, right;
            if (rw <= rh) {
                top = {region.x, region.y + ph, region.width, rh};
                right = {region.x + pw, region.y, rw, ph};
            } else {
                top = {region.x, region.y + ph, pw, rh};
                right = {region.x + pw, region.y, rw, region.height};
            }
            if (top.width > 0 && top.height > 0) sheet.free.push_back(top);
            if (right.width > 0 && right.height > 0) sheet.free.push_back(right);
        }
        int area = 0;
        for (const Sheet& sheet : sheets) area += sheet.area;
        emit("GUILLOTINE W=" + to_string(width) + " H=" + to_string(height) +
             " mode=" + mode + " rule=" + rule +
             " rects=" + to_string(ordered.size()) +
             " sheets=" + to_string(sheets.size()) +
             " rotated=" + to_string(rotated_count) +
             " util=" + to_string(static_cast<Number>(area) * 100 /
                                   (sheets.size() * width * height)));
        for (size_t i = 0; i < sheets.size(); ++i) {
            const Sheet& sheet = sheets[i];
            emit("SHEET " + to_string(i + 1) +
                 " placed=" + to_string(sheet.placements.size()) +
                 " area=" + to_string(sheet.area));
            for (const Placement& p : sheet.placements) {
                emit("PLACE " + string(1, static_cast<char>('A' + p.id - 1)) +
                     " x=" + to_string(p.x) + " y=" + to_string(p.y) +
                     " w=" + to_string(p.width) + " h=" + to_string(p.height) +
                     (p.rotated ? " rotated" : ""));
            }
            string line = "FREE";
            if (sheet.free.empty()) line += " none";
            for (const FreeRectangle& r : sheet.free) {
                line += " " + to_string(r.x) + "," + to_string(r.y) + "," +
                        to_string(r.width) + "x" + to_string(r.height);
            }
            emit(line);
            drawing(width, height, sheet.placements);
        }
    }

public:
    void execute(const string& line) {
        istringstream input(line);
        string command, word;
        input >> command;
        vector<string> arguments;
        while (input >> word) arguments.push_back(word);
        try {
            if (command != "ITEMS" && command != "RANDOM" && command != "CUTSTOCK" &&
                command != "SHELF" && command != "GUILLOTINE" && !has_items)
                fail("NO ITEMS");
            if (find_if(METHODS.begin(), METHODS.end(), [&](const char* name) {
                    return name == command;
                }) != METHODS.end()) {
                run_method(command, arguments);
            } else if (command == "ITEMS") items_command(arguments);
            else if (command == "RANDOM") random_command(arguments);
            else if (command == "TRACE") trace(arguments);
            else if (command == "REDUCE") reduce(arguments);
            else if (command == "BOUNDS") show_bounds();
            else if (command == "COMPARE") compare(arguments);
            else if (command == "EXACT") exact(arguments);
            else if (command == "CHECK") check(arguments);
            else if (command == "COVER") cover();
            else if (command == "MULTIFIT") multifit(arguments);
            else if (command == "CUTSTOCK") cutstock(arguments);
            else if (command == "SHELF") shelf(arguments);
            else if (command == "GUILLOTINE") guillotine(arguments);
        } catch (const runtime_error& error) {
            emit("ERROR", error.what());
        }
    }

    void print() const {
        for (const string& line : output) cout << line << '\n';
    }
};

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    int count;
    cin >> count;
    cin.ignore(numeric_limits<streamsize>::max(), '\n');
    PackingLab lab;
    string line;
    for (int i = 0; i < count; ++i) {
        getline(cin, line);
        lab.execute(line);
    }
    lab.print();
}
