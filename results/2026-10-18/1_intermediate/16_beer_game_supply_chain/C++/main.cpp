#include <algorithm>
#include <array>
#include <deque>
#include <functional>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <numeric>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using namespace std;

using Number = long long;
constexpr array<const char*, 4> NAMES = {
    "RETAILER", "WHOLESALER", "DISTRIBUTOR", "FACTORY"
};

const map<string, int> PARAMETERS = {
    {"FIXED", 1}, {"PASS", 0}, {"BASESTOCK", 1}, {"MINMAX", 2},
    {"MOVAVG", 2}, {"SMOOTH", 2}, {"STERMAN", 4}
};

Number number(const string& text) { return stoll(text); }
string integer(Number value) { return to_string(value); }

string money(Number cents) {
    ostringstream output;
    output << cents / 100 << '.' << setfill('0') << setw(2) << cents % 100;
    return output.str();
}

string decimal(Number numerator, Number denominator, int places) {
    Number whole = numerator / denominator;
    Number remainder = numerator % denominator;
    string answer = to_string(whole) + ".";
    for (int digit = 0; digit < places; ++digit) {
        remainder *= 10;
        answer += static_cast<char>('0' + remainder / denominator);
        remainder %= denominator;
    }
    return answer;
}

Number total(const vector<Number>& values) {
    return accumulate(values.begin(), values.end(), Number{0});
}

Number variation(const vector<Number>& values) {
    Number squares = 0;
    for (Number value : values) squares += value * value;
    return static_cast<Number>(values.size()) * squares - total(values) * total(values);
}

string joined(const deque<Number>& values) {
    string answer;
    for (Number value : values) {
        if (!answer.empty()) answer += ",";
        answer += to_string(value);
    }
    return answer;
}

string aligned(const string& value, int width) {
    return value.size() < static_cast<size_t>(width)
        ? string(width - value.size(), ' ') + value : value;
}

string combined(const vector<string>& values, const string& separator = " ") {
    string answer;
    bool first = true;
    for (const string& value : values) {
        if (!first) answer += separator;
        first = false;
        answer += value;
    }
    return answer;
}

struct Policy {
    string name;
    vector<Number> args;
    string text;
};

Policy parse_policy(const vector<string>& tokens) {
    const string& name = tokens[0];
    auto it = PARAMETERS.find(name);
    if (it == PARAMETERS.end()) throw runtime_error("unknown policy " + name);
    int count = it->second;
    if (static_cast<int>(tokens.size()) - 1 != count)
        throw runtime_error(name + " needs " + to_string(count) + " parameters");
    Policy result{name, {}, combined(tokens)};
    for (int i = 0; i < count; ++i) {
        string token = tokens[i + 1];
        if (name == "STERMAN" && i < 3) {
            token.erase(remove(token.begin(), token.end(), '.'), token.end());
        }
        result.args.push_back(number(token));
    }
    const auto& a = result.args;
    bool valid = false;
    if (name == "FIXED") valid = a[0] <= 1000;
    else if (name == "PASS") valid = true;
    else if (name == "BASESTOCK") valid = a[0] <= 10000;
    else if (name == "MINMAX") valid = a[0] < a[1] && a[1] <= 10000;
    else if (name == "MOVAVG") valid = 1 <= a[0] && a[0] <= 52 && a[1] <= 10000;
    else if (name == "SMOOTH") valid = 1 <= a[0] && a[0] <= 10 && a[1] <= 10000;
    else if (name == "STERMAN")
        valid = a[0] <= 100 && a[1] <= 100 && a[2] <= 100 && a[3] <= 10000;
    if (!valid) throw runtime_error("invalid parameter for " + name);
    return result;
}

struct Setting {
    Number inventory;
    Number quantity;
    int shipping;
    int orders;
    Number holding;
    Number backlog;
    Policy policy;
};

struct Record {
    Number received = 0;
    Number incoming = 0;
    Number shipped = 0;
    Number before = 0;
    Number ontime = 0;
    Number inventory = 0;
    Number backlog = 0;
    Number order = 0;
    Number holding = 0;
    Number backlog_cost = 0;
    Number cost = 0;
};

struct PlantRecord {
    Number incoming;
    Number produced;
    Number backlog;
};

struct Stage {
    Number inventory = 0;
    Number backlog = 0;
    deque<Number> shipping;
    deque<Number> orders;
    Policy policy;
    Number expected = 0;
    Number holding = 0;
    Number backlog_rate = 0;
    int lot = 1;
    optional<Number> capacity;
    vector<Record> records;

    Stage() = default;

    explicit Stage(const Setting& initial)
        : inventory(initial.inventory), backlog(0),
          shipping(initial.shipping, initial.quantity),
          orders(initial.orders, initial.quantity), policy(initial.policy),
          expected(100 * initial.quantity), holding(initial.holding),
          backlog_rate(initial.backlog) {}

    Number cost() const {
        Number value = 0;
        for (const Record& record : records) value += record.cost;
        return value;
    }
};

struct Pipeline {
    array<Number, 4> supply{};
    array<Number, 4> position{};
};

class Simulation {
    vector<Setting> initials;

public:
    int week = 0;
    vector<Number> demands;
    array<Stage, 4> stages;
    Number plant_backlog = 0;
    optional<Number> plant_capacity;
    vector<PlantRecord> plant_records;
    string visibility = "OFF";

    Simulation() = default;

    Simulation(vector<Setting> settings, vector<Number> demand)
        : initials(move(settings)), demands(move(demand)) {
        for (int index = 0; index < 4; ++index) stages[index] = Stage(initials[index]);
    }

    Number signal(int index, int queried_week,
                  const array<Number, 4>* current = nullptr) const {
        if (visibility == "ON") return demands[queried_week - 1];
        if (current && queried_week == week + 1) return (*current)[index];
        return stages[index].records[queried_week - 1].incoming;
    }

    void set_policy(int index, const Policy& policy) {
        Stage& stage = stages[index];
        stage.policy = policy;
        if (policy.name == "STERMAN")
            stage.expected = 100 * (week ? signal(index, week) : initials[index].quantity);
    }

    Pipeline positions() const {
        Pipeline result;
        for (int index = 0; index < 4; ++index) {
            const Stage& stage = stages[index];
            Number upstream_backlog = index < 3 ? stages[index + 1].backlog : plant_backlog;
            Number line = upstream_backlog;
            for (Number quantity : stage.orders) line += quantity;
            for (Number quantity : stage.shipping) line += quantity;
            result.supply[index] = line;
            result.position[index] = stage.inventory + line - stage.backlog;
        }
        return result;
    }

    Number policy_order(int index, const array<Number, 4>& incoming,
                        Number line, Number position) {
        Stage& stage = stages[index];
        const Policy& policy = stage.policy;
        const auto& a = policy.args;
        int t = week + 1;
        Number demand = signal(index, t, &incoming);
        if (policy.name == "FIXED") return a[0];
        if (policy.name == "PASS") return incoming[index];
        if (policy.name == "BASESTOCK") return max(Number{0}, a[0] - position);
        if (policy.name == "MINMAX") return position <= a[0] ? a[1] - position : 0;
        if (policy.name == "MOVAVG") {
            int count = static_cast<int>(min(a[0], static_cast<Number>(t)));
            Number demand_sum = 0;
            for (int u = t - count + 1; u <= t; ++u)
                demand_sum += signal(index, u, &incoming);
            Number forecast = demand_sum / count;
            Number delay = initials[index].shipping + initials[index].orders;
            return max(Number{0}, a[1] + forecast * delay - position);
        }
        if (policy.name == "SMOOTH")
            return max(Number{0}, demand + static_cast<Number>(floor_div(a[1] - position, a[0])));

        Number theta = a[0], alpha = a[1], beta = a[2], target = a[3];
        stage.expected = (100 * theta * demand +
                          (100 - theta) * stage.expected) / 100;
        Number net = stage.inventory - stage.backlog;
        return max(Number{0}, floor_div(
            100 * stage.expected + alpha * (100 * (target - net) - beta * line), 10000));
    }

    array<Record, 4> step() {
        array<Number, 4> received{};
        for (int index = 0; index < 4; ++index) {
            Stage& stage = stages[index];
            Number quantity = stage.shipping.front();
            stage.shipping.pop_front();
            stage.inventory += quantity;
            received[index] = quantity;
        }
        array<Number, 4> incoming{
            demands[week], stages[0].orders.front(),
            stages[1].orders.front(), stages[2].orders.front()
        };
        Number plant_incoming = stages[3].orders.front();
        for (Stage& stage : stages) stage.orders.pop_front();

        array<Record, 4> records{};
        for (int index = 0; index < 4; ++index) {
            Stage& stage = stages[index];
            Number before = stage.backlog;
            Number requested = before + incoming[index];
            Number shipped = min(stage.inventory, requested);
            if (stage.capacity) shipped = min(shipped, *stage.capacity);
            stage.inventory -= shipped;
            stage.backlog = requested - shipped;
            if (index) stages[index - 1].shipping.push_back(shipped);
            Record& record = records[index];
            record.received = received[index];
            record.incoming = incoming[index];
            record.shipped = shipped;
            record.before = before;
            record.ontime = min(max(Number{0}, shipped - before), incoming[index]);
            record.inventory = stage.inventory;
            record.backlog = stage.backlog;
        }

        Number plant_requested = plant_backlog + plant_incoming;
        Number produced = plant_capacity ? min(plant_requested, *plant_capacity) : plant_requested;
        plant_backlog = plant_requested - produced;
        stages[3].shipping.push_back(produced);

        Pipeline pipeline = positions();
        array<Number, 4> orders{};
        for (int index = 0; index < 4; ++index)
            orders[index] = policy_order(index, incoming,
                                         pipeline.supply[index], pipeline.position[index]);
        for (int index = 0; index < 4; ++index) {
            Stage& stage = stages[index];
            Number quantity = (orders[index] + stage.lot - 1) / stage.lot * stage.lot;
            stage.orders.push_back(quantity);
            Record& record = records[index];
            record.order = quantity;
            record.holding = stage.holding * stage.inventory;
            record.backlog_cost = stage.backlog_rate * stage.backlog;
            record.cost = record.holding + record.backlog_cost;
            stage.records.push_back(record);
        }
        plant_records.push_back({plant_incoming, produced, plant_backlog});
        ++week;
        return records;
    }

    array<Number, 4> costs() const {
        array<Number, 4> result{};
        for (int index = 0; index < 4; ++index)
            result[index] = stages[index].cost();
        return result;
    }

private:
    static Number floor_div(Number numerator, Number denominator) {
        Number quotient = numerator / denominator;
        return quotient - (numerator % denominator < 0);
    }
};

class Game {
    vector<Setting> initials;
    vector<Number> base;
    Simulation simulation;
    map<string, Simulation> snapshots;
    vector<string> output;

    template <typename... T>
    void emit(const T&... args) {
        ostringstream line;
        bool first = true;
        ((line << (first ? "" : " ") << args, first = false), ...);
        output.push_back(line.str());
    }

    static void fail(const string& message) { throw runtime_error(message); }

    static int stage_index(const string& name) {
        for (int index = 0; index < 4; ++index)
            if (name == NAMES[index]) return index;
        fail("unknown stage " + name);
        return -1;
    }

    static vector<int> target(const string& name) {
        if (name == "ALL") return {0, 1, 2, 3};
        return {stage_index(name)};
    }

    void require_weeks() const {
        if (simulation.week == 0) fail("no weeks simulated");
    }

    static pair<int, int> range_check(const vector<string>& a, int limit) {
        if (a.empty()) return {1, limit};
        int first = stoi(a[0]), last = stoi(a[1]);
        if (!(1 <= first && first <= last && last <= limit))
            fail("bad range " + a[0] + " " + a[1]);
        return {first, last};
    }

    static void mode_check(const string& name) {
        if (name != "ORDERS" && name != "INV" && name != "BACK" && name != "NET")
            fail("unknown mode " + name);
    }

    vector<Number> values(int index, const string& mode) const {
        vector<Number> result;
        for (const Record& record : simulation.stages[index].records) {
            if (mode == "ORDERS") result.push_back(record.order);
            else if (mode == "INV") result.push_back(record.inventory);
            else if (mode == "BACK") result.push_back(record.backlog);
            else result.push_back(record.inventory - record.backlog);
        }
        return result;
    }

    void initialize(const vector<Number>* demands = nullptr) {
        if (demands) base = *demands;
        simulation = Simulation(initials, base);
    }

    Simulation trial(const array<Policy, 4>& policies) const {
        Simulation result(initials, simulation.demands);
        result.visibility = simulation.visibility;
        result.plant_capacity = simulation.plant_capacity;
        for (int index = 0; index < 4; ++index) {
            Stage& stage = result.stages[index];
            const Stage& current = simulation.stages[index];
            stage.lot = current.lot;
            stage.capacity = current.capacity;
            stage.holding = current.holding;
            stage.backlog_rate = current.backlog_rate;
            result.set_policy(index, policies[index]);
        }
        while (result.week < static_cast<int>(result.demands.size())) result.step();
        return result;
    }

    void demand(const vector<Number>& values) {
        initialize(&values);
        emit("DEMAND", "weeks", values.size(), "total", total(values),
             "min", *min_element(values.begin(), values.end()),
             "max", *max_element(values.begin(), values.end()));
    }

    void generate(const vector<string>& a) {
        int weeks = stoi(a[0]);
        Number baseline = number(a[1]), spread = number(a[2]), seed = number(a[3]);
        struct Change {
            string kind;
            int week;
            Number amount;
        };
        vector<Change> changes;
        for (size_t i = 4; i < a.size(); i += 3) {
            Change change{a[i], stoi(a[i + 1]), number(a[i + 2])};
            if (change.week < 1 || change.week > weeks)
                fail("week " + to_string(change.week) + " outside horizon");
            changes.push_back(move(change));
        }
        vector<Number> levels;
        for (int t = 1; t <= weeks; ++t) {
            Number level = baseline;
            for (const Change& change : changes) {
                if (change.kind == "STEP" && t >= change.week) level += change.amount;
                else if (change.kind == "PULSE" && t == change.week) level += change.amount;
                else if (change.kind == "RAMP" && t >= change.week)
                    level += change.amount * (t - change.week + 1);
            }
            if (level < 0) fail("negative level at week " + to_string(t));
            levels.push_back(level);
        }
        vector<Number> generated;
        for (Number level : levels) {
            seed = 48271 * seed % 2147483647;
            generated.push_back(level + seed % spread);
        }
        demand(generated);
    }

    void show_status() {
        emit("STATUS", "week", simulation.week, "of", simulation.demands.size());
        Pipeline p = simulation.positions();
        for (int index = 0; index < 4; ++index) {
            const Stage& stage = simulation.stages[index];
            string text = string(NAMES[index]) + " inv " + integer(stage.inventory) +
                          " back " + integer(stage.backlog) +
                          " transit " + joined(stage.shipping) +
                          " pending " + joined(stage.orders) +
                          " supply " + integer(p.supply[index]) +
                          " position " + integer(p.position[index]) +
                          " policy " + stage.policy.text;
            if (stage.policy.name == "STERMAN") text += " expect " + money(stage.expected);
            emit(text);
        }
        emit("PLANT", "back", simulation.plant_backlog);
    }

    void show_week(int week) {
        emit("WEEK", week, "demand", simulation.demands[week - 1]);
        for (int index = 0; index < 4; ++index) {
            const Record& r = simulation.stages[index].records[week - 1];
            emit(NAMES[index], "recv", r.received, "in", r.incoming,
                 "ship", r.shipped, "inv", r.inventory, "back", r.backlog,
                 "order", r.order, "cost", money(r.cost));
        }
        const PlantRecord& r = simulation.plant_records[week - 1];
        emit("PLANT", "in", r.incoming, "made", r.produced, "back", r.backlog);
    }

    void show_table(int index, int first, int last) {
        emit("TABLE", NAMES[index], to_string(first) + "-" + to_string(last));
        const vector<string> labels{"week", "in", "ship", "recv", "inv", "back", "order", "cost"};
        const array<int, 8> widths{4, 6, 6, 6, 6, 6, 6, 9};
        vector<string> parts;
        for (int i = 0; i < 8; ++i) parts.push_back(aligned(labels[i], widths[i]));
        emit(combined(parts));
        for (int week = first; week <= last; ++week) {
            const Record& r = simulation.stages[index].records[week - 1];
            vector<string> values{
                to_string(week), integer(r.incoming), integer(r.shipped),
                integer(r.received), integer(r.inventory), integer(r.backlog),
                integer(r.order), money(r.cost)
            };
            parts.clear();
            for (int i = 0; i < 8; ++i) parts.push_back(aligned(values[i], widths[i]));
            emit(combined(parts));
        }
    }

    void show_costs() {
        emit("COSTS", "week", simulation.week);
        Number holding_total = 0, backlog_total = 0;
        for (int index = 0; index < 4; ++index) {
            const Stage& stage = simulation.stages[index];
            Number holding = 0, backlog = 0;
            for (const Record& r : stage.records) {
                holding += r.holding;
                backlog += r.backlog_cost;
            }
            holding_total += holding;
            backlog_total += backlog;
            emit(NAMES[index], "holding", money(holding),
                 "backlog", money(backlog), "total", money(holding + backlog));
        }
        emit("TOTAL", "holding", money(holding_total),
             "backlog", money(backlog_total),
             "total", money(holding_total + backlog_total));
    }

    struct Fill {
        Number ordered;
        Number ontime;
        string fill;
    };

    static Fill fill_text(const vector<Record>& records) {
        Number ordered = 0, ontime = 0;
        for (const Record& r : records) {
            ordered += r.incoming;
            ontime += r.ontime;
        }
        string ratio = ordered == 0 ? "n/a" : decimal(ontime * 100, ordered, 2) + "%";
        return {ordered, ontime, ratio};
    }

    void show_bullwhip() {
        int n = simulation.week;
        vector<Number> demands(simulation.demands.begin(), simulation.demands.begin() + n);
        Number demand_var = variation(demands);
        emit("BULLWHIP", "weeks", "1-" + to_string(n), "demand",
             "mean", decimal(total(demands), n, 4),
             "var", decimal(demand_var, static_cast<Number>(n) * n, 4));
        Number previous = demand_var;
        for (int index = 0; index < 4; ++index) {
            vector<Number> orders;
            for (const Record& r : simulation.stages[index].records)
                orders.push_back(r.order);
            Number current = variation(orders);
            emit(NAMES[index], "mean", decimal(total(orders), n, 4),
                 "var", decimal(current, static_cast<Number>(n) * n, 4),
                 "ratio", demand_var == 0 ? "n/a" : decimal(current, demand_var, 4),
                 "step", previous == 0 ? "n/a" : decimal(current, previous, 4));
            previous = current;
        }
    }

    void show_peaks() {
        emit("PEAKS", "weeks", "1-" + to_string(simulation.week));
        for (int index = 0; index < 4; ++index) {
            vector<Number> inventories, backlogs;
            for (const Record& r : simulation.stages[index].records) {
                inventories.push_back(r.inventory);
                backlogs.push_back(r.backlog);
            }
            Number max_inventory = *max_element(inventories.begin(), inventories.end());
            Number max_backlog = *max_element(backlogs.begin(), backlogs.end());
            int longest = 0, run = 0, start = 0, best_first = 0, best_last = 0;
            for (int week = 1; week <= static_cast<int>(backlogs.size()); ++week) {
                if (backlogs[week - 1] > 0) {
                    if (run == 0) start = week;
                    ++run;
                    if (run > longest) {
                        longest = run;
                        best_first = start;
                        best_last = week;
                    }
                } else {
                    run = 0;
                }
            }
            string inv_week = max_inventory == 0 ? "-" :
                to_string(find(inventories.begin(), inventories.end(), max_inventory) -
                          inventories.begin() + 1);
            string back_week = max_backlog == 0 ? "-" :
                to_string(find(backlogs.begin(), backlogs.end(), max_backlog) -
                          backlogs.begin() + 1);
            string stockout = longest == 0 ? "0" :
                to_string(longest) + " weeks " + to_string(best_first) + "-" + to_string(best_last);
            emit(NAMES[index], "max_inv", max_inventory, "week", inv_week,
                 "max_back", max_backlog, "week", back_week,
                 "longest_stockout", stockout);
        }
    }

    void show_leadtime(int index) {
        const Stage& stage = simulation.stages[index];
        const Setting& initial = initials[index];
        int nominal = initial.shipping + initial.orders;
        vector<Number> cumulative;
        Number received = 0;
        for (const Record& record : stage.records) {
            received += record.received;
            cumulative.push_back(received - nominal * initial.quantity);
        }
        Number ordered = 0;
        int count = 0;
        vector<Number> leads;
        for (int t = 0; t < static_cast<int>(stage.records.size()); ++t) {
            const Record& record = stage.records[t];
            ordered += record.order;
            if (record.order == 0) continue;
            ++count;
            for (int u = t + 1; u < static_cast<int>(stage.records.size()); ++u) {
                if (cumulative[u] >= ordered) {
                    leads.push_back(u - t);
                    break;
                }
            }
        }
        emit("LEADTIME", NAMES[index], "nominal", nominal,
             "orders", count, "completed", leads.size(),
             "open", count - static_cast<int>(leads.size()),
             "min", leads.empty() ? "-" : integer(*min_element(leads.begin(), leads.end())),
             "avg", leads.empty() ? "-" : decimal(total(leads), leads.size(), 2),
             "max", leads.empty() ? "-" : integer(*max_element(leads.begin(), leads.end())));
    }

    void show_plot(int index, const string& mode, int first, int last) {
        vector<Number> all = values(index, mode);
        vector<Number> v(all.begin() + first - 1, all.begin() + last);
        Number maximum = *max_element(v.begin(), v.end());
        string period = to_string(first) + "-" + to_string(last);
        if (mode == "NET") {
            emit("PLOT", NAMES[index], mode, period,
                 "min", *min_element(v.begin(), v.end()), "max", maximum);
            Number scale = 0;
            for (Number value : v) scale = max(scale, abs(value));
            for (int week = first; week <= last; ++week) {
                Number value = v[week - first];
                int width = scale ? static_cast<int>(abs(value) * 25 / scale) : 0;
                string left = value < 0
                    ? string(25 - width, ' ') + string(width, '-')
                    : string(25, ' ');
                string right = value > 0 ? string(width, '+') : "";
                emit(aligned(to_string(week), 3) + " " + left + "|" +
                     right + " " + integer(value));
            }
        } else {
            emit("PLOT", NAMES[index], mode, period, "max", maximum);
            for (int week = first; week <= last; ++week) {
                Number value = v[week - first];
                int width = maximum ? static_cast<int>(value * 50 / maximum) : 0;
                emit(aligned(to_string(week), 3) + " |" +
                     string(width, '#') + " " + integer(value));
            }
        }
    }

    void show_histogram(int index, const string& mode, Number width) {
        vector<Number> observed = values(index, mode);
        map<Number, int> counts;
        for (Number value : observed) {
            Number bucket = value / width - (value % width < 0);
            ++counts[bucket];
        }
        emit("HISTOGRAM", NAMES[index], mode, "width", width,
             "weeks", "1-" + to_string(simulation.week));
        for (Number bucket = counts.begin()->first; bucket <= counts.rbegin()->first; ++bucket) {
            int count = counts[bucket];
            string text = integer(bucket * width) + ".." +
                          integer(bucket * width + width - 1) + " " + to_string(count);
            if (count) text += " " + string(count, '*');
            emit(text);
        }
    }

    void execute(const string& command, const vector<string>& a) {
        if (command == "DEMAND") {
            vector<Number> data;
            for (const string& value : a) data.push_back(number(value));
            demand(data);
        } else if (command == "GENERATE") {
            generate(a);
        } else if (command == "RUN") {
            if (simulation.week == static_cast<int>(simulation.demands.size()))
                fail("horizon reached at week " + to_string(simulation.demands.size()));
            int first = simulation.week + 1;
            int count = min(stoi(a[0]), static_cast<int>(simulation.demands.size()) - simulation.week);
            Number cost = 0;
            for (int t = 0; t < count; ++t) {
                auto records = simulation.step();
                for (int index = 0; index < 4; ++index) {
                    const Record& r = records[index];
                    cost += r.cost;
                    if (r.before == 0 && r.backlog > 0)
                        emit("STOCKOUT", NAMES[index], "week", simulation.week,
                             "backlog", r.backlog);
                    else if (r.before > 0 && r.backlog == 0)
                        emit("RECOVER", NAMES[index], "week", simulation.week);
                }
            }
            Number demand_total = 0;
            for (int t = first; t <= simulation.week; ++t)
                demand_total += simulation.demands[t - 1];
            emit("RUN", to_string(first) + "-" + to_string(simulation.week),
                 "demand", demand_total, "cost", money(cost));
            if (simulation.week == static_cast<int>(simulation.demands.size()))
                emit("HORIZON", simulation.week);
        } else if (command == "RESET") {
            initialize();
            emit("RESET", "week", 0);
        } else if (command == "SAVE") {
            snapshots[a[0]] = simulation;
            emit("SAVE", a[0], "week", simulation.week);
        } else if (command == "LOAD") {
            auto it = snapshots.find(a[0]);
            if (it == snapshots.end()) fail("no snapshot " + a[0]);
            simulation = it->second;
            emit("LOAD", a[0], "week", simulation.week);
        } else if (command == "SET") {
            vector<int> indices = target(a[0]);
            Policy policy = parse_policy(vector<string>(a.begin() + 1, a.end()));
            for (int index : indices) simulation.set_policy(index, policy);
            emit("SET", a[0], policy.text);
        } else if (command == "BATCH") {
            int index = stage_index(a[0]), lot = stoi(a[1]);
            if (lot < 1 || lot > 100) fail("invalid batch size " + a[1]);
            simulation.stages[index].lot = lot;
            emit("BATCH", a[0], lot);
        } else if (command == "CAPACITY") {
            int index = a[0] == "PLANT" ? -1 : stage_index(a[0]);
            optional<Number> capacity = a[1] == "OFF" ? nullopt :
                optional<Number>(number(a[1]));
            if (capacity && *capacity > 10000) fail("invalid capacity " + a[1]);
            if (index == -1) simulation.plant_capacity = capacity;
            else simulation.stages[index].capacity = capacity;
            emit("CAPACITY", a[0], a[1]);
        } else if (command == "COST") {
            int index = stage_index(a[0]);
            Number holding = number(a[1]), backlog = number(a[2]);
            if (holding > 1000 || backlog > 1000) fail("invalid cost");
            simulation.stages[index].holding = holding;
            simulation.stages[index].backlog_rate = backlog;
            emit("COST", a[0], "holding", holding, "backlog", backlog);
        } else if (command == "VISIBILITY") {
            if (a[0] != "ON" && a[0] != "OFF")
                fail("unknown visibility " + a[0]);
            simulation.visibility = a[0];
            emit("VISIBILITY", a[0]);
        } else if (command == "SHOCK") {
            int week = stoi(a[0]);
            Number demand = number(a[1]);
            if (week < 1 || week > static_cast<int>(simulation.demands.size()))
                fail("week " + a[0] + " outside horizon");
            if (week <= simulation.week) fail("week " + a[0] + " already simulated");
            Number old = simulation.demands[week - 1];
            simulation.demands[week - 1] = demand;
            emit("SHOCK", "week", week, old, "->", demand);
        } else if (command == "STATUS") {
            show_status();
        } else if (command == "SETTINGS") {
            emit("SETTINGS");
            for (int index = 0; index < 4; ++index) {
                const Stage& stage = simulation.stages[index];
                const Setting& initial = initials[index];
                emit(NAMES[index], "holding", stage.holding,
                     "backlog", stage.backlog_rate, "batch", stage.lot,
                     "capacity", stage.capacity ? integer(*stage.capacity) : "OFF",
                     "delays", initial.shipping, initial.orders);
            }
            emit("PLANT", "capacity", simulation.plant_capacity
                 ? integer(*simulation.plant_capacity) : "OFF");
            emit("VISIBILITY", simulation.visibility);
        } else if (command == "WEEK") {
            require_weeks();
            int week = stoi(a[0]);
            if (week < 1 || week > simulation.week) fail("bad week " + a[0]);
            show_week(week);
        } else if (command == "TABLE") {
            int index = stage_index(a[0]);
            require_weeks();
            auto [first, last] = range_check(
                vector<string>(a.begin() + 1, a.end()), simulation.week);
            show_table(index, first, last);
        } else if (command == "CHAIN") {
            require_weeks();
            auto [first, last] = range_check(a, simulation.week);
            emit("CHAIN", to_string(first) + "-" + to_string(last));
            vector<string> header{aligned("week", 4), aligned("demand", 6)};
            for (const char* stage : NAMES) header.push_back(aligned(stage, 11));
            emit(combined(header));
            for (int week = first; week <= last; ++week) {
                vector<string> values{
                    aligned(to_string(week), 4),
                    aligned(integer(simulation.demands[week - 1]), 6)
                };
                for (const Stage& stage : simulation.stages)
                    values.push_back(aligned(integer(stage.records[week - 1].order), 11));
                emit(combined(values));
            }
        } else if (command == "DEMANDS") {
            auto [first, last] = range_check(a, simulation.demands.size());
            vector<Number> values(simulation.demands.begin() + first - 1,
                                  simulation.demands.begin() + last);
            emit("DEMANDS", to_string(first) + "-" + to_string(last),
                 "total", total(values),
                 "min", *min_element(values.begin(), values.end()),
                 "max", *max_element(values.begin(), values.end()));
            vector<string> parts;
            for (Number value : values) parts.push_back(integer(value));
            emit(combined(parts));
        } else if (command == "COSTS") {
            show_costs();
        } else if (command == "SUMMARY") {
            require_weeks();
            emit("SUMMARY", "weeks", "1-" + to_string(simulation.week));
            for (int index = 0; index < 4; ++index) {
                Number inventory = 0, backlog = 0, order_total = 0;
                Number smallest = numeric_limits<Number>::max(), largest = 0;
                int zero_weeks = 0;
                for (const Record& r : simulation.stages[index].records) {
                    inventory += r.inventory;
                    backlog += r.backlog;
                    order_total += r.order;
                    smallest = min(smallest, r.order);
                    largest = max(largest, r.order);
                    zero_weeks += r.order == 0;
                }
                emit(NAMES[index], "avg_inv", decimal(inventory, simulation.week, 2),
                     "avg_back", decimal(backlog, simulation.week, 2),
                     "orders", order_total, "min", smallest, "max", largest,
                     "zero_weeks", zero_weeks);
            }
        } else if (command == "BALANCE") {
            emit("BALANCE", "week", simulation.week);
            Number initial_goods = 0, produced = 0, delivered = 0, stock = 0, transit = 0;
            for (int index = 0; index < 4; ++index) {
                const Stage& stage = simulation.stages[index];
                Number received = 0, shipped = 0;
                for (const Record& r : stage.records) {
                    received += r.received;
                    shipped += r.shipped;
                }
                emit(NAMES[index], "start", initials[index].inventory,
                     "received", received, "shipped", shipped,
                     "end", stage.inventory, "owed", stage.backlog);
                initial_goods += initials[index].inventory +
                                 initials[index].quantity * initials[index].shipping;
                if (index == 0) delivered = shipped;
                stock += stage.inventory;
                for (Number amount : stage.shipping) transit += amount;
            }
            for (const PlantRecord& record : simulation.plant_records)
                produced += record.produced;
            emit("SYSTEM", "initial", initial_goods, "produced", produced,
                 "delivered", delivered, "stock", stock, "transit", transit);
        } else if (command == "FILLRATE") {
            require_weeks();
            emit("FILLRATE", "weeks", "1-" + to_string(simulation.week));
            for (int index = 0; index < 4; ++index) {
                const auto& records = simulation.stages[index].records;
                Fill f = fill_text(records);
                int stockouts = 0;
                for (const Record& record : records) stockouts += record.backlog > 0;
                emit(NAMES[index], "fill", f.fill,
                     "ontime", f.ontime, "ordered", f.ordered,
                     "stockout_weeks", stockouts,
                     "service", decimal(100LL * (simulation.week - stockouts),
                                        simulation.week, 2) + "%");
            }
        } else if (command == "BULLWHIP") {
            require_weeks();
            show_bullwhip();
        } else if (command == "PEAKS") {
            require_weeks();
            show_peaks();
        } else if (command == "LEADTIME") {
            int index = stage_index(a[0]);
            require_weeks();
            show_leadtime(index);
        } else if (command == "PLOT" || command == "HISTOGRAM") {
            int index = stage_index(a[0]);
            mode_check(a[1]);
            Number width = 0;
            if (command == "HISTOGRAM") {
                width = number(a[2]);
                if (width < 1 || width > 100)
                    fail("invalid width " + a[2]);
            }
            require_weeks();
            if (command == "PLOT") {
                auto [first, last] = range_check(
                    vector<string>(a.begin() + 2, a.end()), simulation.week);
                show_plot(index, a[1], first, last);
            } else {
                show_histogram(index, a[1], width);
            }
        } else if (command == "COMPARE") {
            vector<Policy> policies;
            size_t start = 0;
            for (size_t end = 0; end <= a.size(); ++end) {
                if (end == a.size() || a[end] == "/") {
                    policies.push_back(parse_policy(
                        vector<string>(a.begin() + start, a.begin() + end)));
                    start = end + 1;
                }
            }
            struct Row {
                Number cost;
                size_t index;
                string policy;
                string fill;
                string ratio;
            };
            vector<Row> rows;
            for (size_t i = 0; i < policies.size(); ++i) {
                array<Policy, 4> selected;
                selected.fill(policies[i]);
                Simulation s = trial(selected);
                Number cost = total(vector<Number>(s.costs().begin(), s.costs().end()));
                Fill f = fill_text(s.stages[0].records);
                Number demand_var = variation(s.demands);
                vector<Number> factory_orders;
                for (const Record& r : s.stages[3].records)
                    factory_orders.push_back(r.order);
                Number factory_var = variation(factory_orders);
                string ratio = demand_var == 0 ? "n/a" : decimal(factory_var, demand_var, 4);
                rows.push_back({cost, i, policies[i].text, f.fill, ratio});
            }
            sort(rows.begin(), rows.end(), [](const Row& a, const Row& b) {
                return tie(a.cost, a.index) < tie(b.cost, b.index);
            });
            emit("COMPARE", policies.size(), "weeks", simulation.demands.size());
            for (size_t i = 0; i < rows.size(); ++i)
                emit(i + 1, rows[i].policy, "total", money(rows[i].cost),
                     "fill", rows[i].fill, "bullwhip", rows[i].ratio);
        } else if (command == "OPTIMIZE") {
            vector<int> indices = target(a[0]);
            int low = stoi(a[1]), high = stoi(a[2]);
            if (low > high) fail("bad range " + a[1] + " " + a[2]);
            if (high - low > 200) fail("range too large");
            Number best_cost = numeric_limits<Number>::max(), best_total = 0;
            int best_target = low;
            for (int value = low; value <= high; ++value) {
                array<Policy, 4> policies;
                for (int i = 0; i < 4; ++i) policies[i] = simulation.stages[i].policy;
                Policy replacement{"BASESTOCK", {value}, "BASESTOCK " + to_string(value)};
                for (int index : indices) policies[index] = replacement;
                Simulation s = trial(policies);
                auto costs = s.costs();
                Number objective = 0, chain_total = 0;
                for (int index : indices) objective += costs[index];
                for (Number cost : costs) chain_total += cost;
                if (objective < best_cost) {
                    best_cost = objective;
                    best_target = value;
                    best_total = chain_total;
                }
            }
            emit("OPTIMIZE", a[0], "BASESTOCK", best_target,
                 "cost", money(best_cost), "total", money(best_total));
        } else {
            fail("unknown command " + command);
        }
    }

public:
    explicit Game(const vector<vector<string>>& settings) {
        for (const vector<string>& tokens : settings) {
            Policy policy = parse_policy(vector<string>(tokens.begin() + 7, tokens.end()));
            initials.push_back({
                number(tokens[1]), number(tokens[2]),
                stoi(tokens[3]), stoi(tokens[4]),
                number(tokens[5]), number(tokens[6]), move(policy)
            });
        }
        initialize();
    }

    void execute_line(const string& line) {
        istringstream input(line);
        string command, word;
        input >> command;
        vector<string> args;
        while (input >> word) args.push_back(word);
        try {
            execute(command, args);
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
    vector<vector<string>> settings;
    for (int i = 0; i < 4; ++i) {
        string line, word;
        getline(cin, line);
        istringstream input(line);
        vector<string> tokens;
        while (input >> word) tokens.push_back(word);
        settings.push_back(move(tokens));
    }
    Game game(settings);
    string line;
    while (getline(cin, line) && line != "END") game.execute_line(line);
    game.print();
}
