#include <algorithm>
#include <cstdint>
#include <functional>
#include <iomanip>
#include <iostream>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

using std::string;
using std::vector;
using Integer = std::int64_t;
struct Member {
    string name;
    bool active;
    Integer day;
};
struct Part {
    int member;
    Integer value, result;
};
struct Expense {
    string id, currency, category, mode;
    Integer day, serial, amount, total, interval = 0, next = 0, copies = 0;
    vector<Part> payers, participants;
};
struct Settlement {
    int from, to;
    Integer amount, total, day, serial;
    string currency;
};
struct Transfer {
    int from, to;
    Integer amount;
};
vector<Member> members;
vector<Expense> expenses;
vector<Settlement> settlements;
std::map<string, Integer> currencies, budgets;
std::set<string> used;
Integer currentDay = 1, serial = 0;

[[noreturn]] void fail(const string &message) { throw std::runtime_error(message); }
vector<string> split(const string &s, char delimiter = ' ') {
    vector<string> result;
    std::size_t start = 0;
    for (std::size_t i = 0; i <= s.size(); ++i) {
        if (i == s.size() || s[i] == delimiter) {
            result.push_back(s.substr(start, i - start));
            start = i + 1;
        }
    }
    return result;
}
string join(const vector<string> &items, const string &separator) {
    string result;
    for (std::size_t i = 0; i < items.size(); ++i) {
        if (i) result += separator;
        result += items[i];
    }
    return result;
}
template <typename... Values> string text(const Values &...values) {
    std::ostringstream out;
    (out << ... << values);
    return out.str();
}
Integer amount(const string &s) {
    std::size_t dot = s.find('.');
    return std::stoll(s.substr(0, dot)) * 100 + std::stoll(s.substr(dot + 1));
}
string money(Integer value) {
    return text(value / 100, ".", value % 100 < 10 ? "0" : "", value % 100);
}
string signedMoney(Integer value) {
    if (value == 0) return "0.00";
    return string(value > 0 ? "+" : "-") + money(value > 0 ? value : -value);
}
string rateText(Integer rate) {
    std::ostringstream out;
    out << rate / 10000 << '.' << std::setfill('0') << std::setw(4) << rate % 10000;
    return out.str();
}
string percentage(Integer part, Integer whole) { return money(part * 10000 / whole) + "%"; }
std::pair<Integer, string> amountSpec(const string &s) {
    std::size_t at = s.find('@');
    return {amount(s.substr(0, at)), at == string::npos ? "" : s.substr(at + 1)};
}
Integer convert(Integer value, const string &currency) {
    if (currency.empty()) return value;
    std::map<string, Integer>::const_iterator it = currencies.find(currency);
    if (it == currencies.end()) fail("unknown currency " + currency);
    return (value * it->second + 5000) / 10000;
}
string note(Integer value, const string &currency) {
    return currency.empty() ? "" : " [" + money(value) + " " + currency + "]";
}
int memberId(const string &name, bool active = false) {
    for (int i = 0; i < int(members.size()); ++i) {
        if (members[i].name == name) {
            if (active && !members[i].active) fail("inactive member " + name);
            return i;
        }
    }
    fail("unknown member " + name);
}
vector<int> orderedMembers(bool active = false) {
    vector<int> result;
    for (int i = 0; i < int(members.size()); ++i) {
        if (!active || members[i].active) result.push_back(i);
    }
    std::sort(result.begin(), result.end(), [](int a, int b) { return members[a].name < members[b].name; });
    return result;
}
int expenseId(const string &id) {
    for (int i = 0; i < int(expenses.size()); ++i) if (expenses[i].id == id) return i;
    fail("unknown expense " + id);
}
void checkFrozen(const Expense &e) {
    for (const vector<Part> *parts : {&e.payers, &e.participants}) {
        for (Part p : *parts) if (!members[p.member].active) fail("inactive member " + members[p.member].name);
    }
}
bool allActive(const Expense &e) {
    for (const vector<Part> *parts : {&e.payers, &e.participants}) {
        for (Part p : *parts) if (!members[p.member].active) return false;
    }
    return true;
}
vector<Integer> distribute(Integer total, const vector<Integer> &weights) {
    Integer sum = std::accumulate(weights.begin(), weights.end(), Integer(0));
    vector<Integer> result(weights.size()), remainders(weights.size());
    vector<int> order(weights.size());
    Integer left = total;
    for (int i = 0; i < int(weights.size()); ++i) {
        Integer product = total * weights[i];
        result[i] = product / sum;
        remainders[i] = product % sum;
        left -= result[i];
        order[i] = i;
    }
    std::stable_sort(order.begin(), order.end(), [&](int i, int j) { return remainders[i] > remainders[j]; });
    for (int i = 0; i < left; ++i) ++result[order[i]];
    return result;
}
vector<Integer> equalDistribution(Integer total, int count) {
    vector<Integer> result(count, total / count);
    for (int i = 0; i < total % count; ++i) ++result[i];
    return result;
}
void contributions(Expense &e) {
    vector<Integer> weights;
    for (Part p : e.payers) weights.push_back(p.value);
    vector<Integer> result = distribute(e.total, weights);
    for (int i = 0; i < int(result.size()); ++i) e.payers[i].result = result[i];
}
void compute(Expense &e) {
    e.total = convert(e.amount, e.currency);
    vector<Integer> specified;
    for (Part p : e.participants) specified.push_back(p.value);
    vector<Integer> portions;
    if (e.mode == "EQUAL") portions = equalDistribution(e.amount, int(specified.size()));
    else if (e.mode == "EXACT") portions = specified;
    else if (e.mode == "ADJUST") {
        Integer extras = std::accumulate(specified.begin(), specified.end(), Integer(0));
        portions = equalDistribution(e.amount - extras, int(specified.size()));
        for (int i = 0; i < int(portions.size()); ++i) portions[i] += specified[i];
    } else portions = distribute(e.amount, specified);
    vector<Integer> shares = distribute(e.total, portions);
    for (int i = 0; i < int(shares.size()); ++i) e.participants[i].result = shares[i];
    contributions(e);
}
Expense draftExpense(const vector<string> &args, const Expense *previous) {
    Expense e = previous ? *previous : Expense{};
    int payer = memberId(args[2], true);
    std::pair<Integer, string> spec = amountSpec(args[3]);
    Integer total = convert(spec.first, spec.second);
    if (!spec.first || !total) fail("invalid amount");
    e.amount = spec.first;
    e.currency = spec.second;
    e.category = args[4];
    e.mode = args[5];
    e.payers = {{payer, e.amount, 0}};
    e.participants.clear();
    if (e.mode == "EQUAL" && args[6] == "ALL") {
        for (int i : orderedMembers(true)) e.participants.push_back({i, 0, 0});
    } else {
        std::set<int> seen;
        for (int i = 6; i < int(args.size()); ++i) {
            vector<string> part = split(args[i], ':');
            int id = memberId(part[0], true);
            if (!seen.insert(id).second) fail("duplicate member " + part[0]);
            Integer value = 0;
            if (part.size() == 2) value = e.mode == "PERCENT" || e.mode == "SHARES" ? std::stoll(part[1]) : amount(part[1]);
            e.participants.push_back({id, value, 0});
        }
    }
    Integer sum = 0;
    for (Part p : e.participants) sum += p.value;
    if ((e.mode == "EXACT" && sum != e.amount) || (e.mode == "PERCENT" && sum != 10000) || (e.mode == "SHARES" && sum == 0) || (e.mode == "ADJUST" && sum > e.amount)) fail("splits do not add up");
    compute(e);
    return e;
}
vector<Integer> net(const Expense &e) {
    vector<Integer> result(members.size());
    for (Part p : e.payers) result[p.member] += p.result;
    for (Part p : e.participants) result[p.member] -= p.result;
    return result;
}
bool involved(const Expense &e, int member) {
    for (const vector<Part> *parts : {&e.payers, &e.participants}) {
        for (Part p : *parts) if (p.member == member) return true;
    }
    return false;
}
vector<Integer> balances() {
    vector<Integer> result(members.size());
    for (const Expense &e : expenses) {
        vector<Integer> change = net(e);
        for (int i = 0; i < int(result.size()); ++i) result[i] += change[i];
    }
    for (const Settlement &s : settlements) {
        result[s.from] += s.total;
        result[s.to] -= s.total;
    }
    return result;
}
vector<vector<Integer>> debts() {
    vector<vector<Integer>> result(members.size(), vector<Integer>(members.size()));
    vector<int> order = orderedMembers();
    for (const Expense &e : expenses) {
        vector<Integer> change = net(e);
        vector<int> borrowers, lenders;
        for (int i : order) {
            if (change[i] < 0) borrowers.push_back(i);
            if (change[i] > 0) lenders.push_back(i);
        }
        int i = 0, j = 0;
        while (i < int(borrowers.size()) && j < int(lenders.size())) {
            int from = borrowers[i], to = lenders[j];
            Integer value = std::min(-change[from], change[to]);
            result[from][to] += value;
            change[from] += value;
            change[to] -= value;
            if (!change[from]) ++i;
            if (!change[to]) ++j;
        }
    }
    for (const Settlement &s : settlements) result[s.from][s.to] -= s.total;
    vector<vector<Integer>> raw = result;
    for (int i = 0; i < int(members.size()); ++i) {
        for (int j = 0; j < int(members.size()); ++j) result[i][j] = raw[i][j] - raw[j][i];
    }
    return result;
}
Integer spent(const string &category) {
    Integer total = 0;
    for (const Expense &e : expenses) if (e.category == category) total += e.total;
    return total;
}
void warning(const Expense &e, vector<string> &out) {
    std::map<string, Integer>::const_iterator it = budgets.find(e.category);
    if (it != budgets.end()) {
        Integer total = spent(e.category);
        if (total > it->second) out.push_back("  WARNING " + e.category + " over budget by " + money(total - it->second));
    }
}
string partsText(const vector<Part> &parts) {
    vector<string> result;
    for (Part p : parts) result.push_back(members[p.member].name + " " + money(p.result));
    return join(result, " + ");
}
vector<int> chronological() {
    vector<int> order(expenses.size());
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [](int i, int j) {
        return std::make_pair(expenses[i].day, expenses[i].serial) < std::make_pair(expenses[j].day, expenses[j].serial);
    });
    return order;
}
vector<Transfer> greedy(const vector<int> &group, vector<Integer> values) {
    vector<Transfer> result;
    for (;;) {
        int from = -1, to = -1;
        for (int i : group) {
            if (values[i] < 0 && (from < 0 || values[i] < values[from])) from = i;
            if (values[i] > 0 && (to < 0 || values[i] > values[to])) to = i;
        }
        if (from < 0) break;
        Integer value = std::min(-values[from], values[to]);
        result.push_back({from, to, value});
        values[from] += value;
        values[to] -= value;
    }
    return result;
}
void printTransfers(const vector<Transfer> &transfers, const string &indent, vector<string> &out) {
    for (Transfer t : transfers) out.push_back(indent + members[t.from].name + " -> " + members[t.to].name + " " + money(t.amount));
}
vector<string> execute(const string &line) {
    vector<string> a = split(line);
    string command = a[0];
    vector<string> out;
    if (command == "DAY") {
        Integer day = std::stoll(a[1]);
        if (day <= currentDay) fail("invalid day " + a[1]);
        out.push_back("DAY " + a[1]);
        for (;;) {
            int selected = -1;
            for (int i = 0; i < int(expenses.size()); ++i) {
                const Expense &e = expenses[i];
                if (e.interval > 0 && e.next <= day && (selected < 0 || std::make_pair(e.next, e.serial) < std::make_pair(expenses[selected].next, expenses[selected].serial))) selected = i;
            }
            if (selected < 0) break;
            Expense &original = expenses[selected];
            if (!allActive(original) || convert(original.amount, original.currency) == 0) {
                out.push_back("  CANCEL " + original.id);
                original.interval = 0;
                continue;
            }
            Expense copy = original;
            copy.id = original.id + "#" + std::to_string(original.copies + 2);
            copy.day = original.next;
            copy.serial = ++serial;
            copy.interval = copy.next = copy.copies = 0;
            ++original.copies;
            original.next += original.interval;
            compute(copy);
            used.insert(copy.id);
            expenses.push_back(copy);
            out.push_back("  RECUR " + copy.id + " " + money(copy.total));
            warning(copy, out);
        }
        currentDay = day;
    } else if (command == "MEMBER") {
        int id = -1;
        for (int i = 0; i < int(members.size()); ++i) if (members[i].name == a[1]) id = i;
        if (id >= 0 && members[id].active) fail("duplicate member " + a[1]);
        bool rejoined = id >= 0;
        if (id < 0) members.push_back({a[1], true, currentDay});
        else {
            members[id].active = true;
            members[id].day = currentDay;
        }
        out.push_back("MEMBER " + a[1] + (rejoined ? " rejoined" : " joined"));
    } else if (command == "LEAVE") {
        int id = memberId(a[1], true);
        if (balances()[id] != 0) fail("member has a balance " + a[1]);
        members[id].active = false;
        members[id].day = currentDay;
        out.push_back("LEAVE " + a[1]);
    } else if (command == "CURRENCY") {
        Integer value = std::stoll(a[2]);
        string result = "CURRENCY " + a[1] + " " + rateText(value);
        if (currencies.count(a[1])) result += " was " + rateText(currencies[a[1]]);
        currencies[a[1]] = value;
        out.push_back(result);
    } else if (command == "EXPENSE" || command == "EDIT") {
        int id = -1;
        if (command == "EXPENSE") {
            if (used.count(a[1])) fail("duplicate id " + a[1]);
        } else {
            id = expenseId(a[1]);
            checkFrozen(expenses[id]);
        }
        Expense e = draftExpense(a, id < 0 ? nullptr : &expenses[id]);
        if (id < 0) {
            e.id = a[1];
            e.day = currentDay;
            e.serial = ++serial;
            used.insert(e.id);
            expenses.push_back(e);
        } else expenses[id] = e;
        out.push_back(command + " " + e.id + " " + money(e.total) + note(e.amount, e.currency) + " = " + partsText(e.participants));
        warning(e, out);
    } else if (command == "PAYERS") {
        int id = expenseId(a[1]);
        checkFrozen(expenses[id]);
        vector<Part> payers;
        std::set<int> seen;
        Integer sum = 0;
        for (int i = 2; i < int(a.size()); ++i) {
            vector<string> pair = split(a[i], ':');
            int member = memberId(pair[0], true);
            if (!seen.insert(member).second) fail("duplicate member " + pair[0]);
            Integer value = amount(pair[1]);
            sum += value;
            payers.push_back({member, value, 0});
        }
        Expense &e = expenses[id];
        if (sum != e.amount) fail("payers do not add up");
        e.payers = std::move(payers);
        contributions(e);
        out.push_back("PAYERS " + e.id + " " + money(e.total) + note(e.amount, e.currency) + " = " + partsText(e.payers));
    } else if (command == "DELETE") {
        int id = expenseId(a[1]);
        checkFrozen(expenses[id]);
        expenses.erase(expenses.begin() + id);
        out.push_back("DELETE " + a[1]);
    } else if (command == "RECURRING") {
        Expense &e = expenses[expenseId(a[1])];
        e.interval = std::stoll(a[2]);
        if (e.interval) {
            e.next = currentDay + e.interval;
            out.push_back(text("RECURRING ", e.id, " interval ", e.interval, " next ", e.next));
        } else out.push_back("RECURRING " + e.id + " stopped");
    } else if (command == "SETTLE") {
        int from = memberId(a[1], true), to = memberId(a[2], true);
        if (from == to) fail("same member " + a[1]);
        std::pair<Integer, string> spec = amountSpec(a[3]);
        Integer total = convert(spec.first, spec.second);
        if (!spec.first || !total) fail("invalid amount");
        settlements.push_back({from, to, spec.first, total, currentDay, ++serial, spec.second});
        out.push_back("SETTLE " + a[1] + " -> " + a[2] + " " + money(total) + note(spec.first, spec.second));
    } else if (command == "BUDGET") {
        Integer value = amount(a[2]);
        if (value) {
            budgets[a[1]] = value;
            out.push_back("BUDGET " + a[1] + " " + money(value));
        } else {
            budgets.erase(a[1]);
            out.push_back("BUDGET " + a[1] + " removed");
        }
    } else if (command == "BALANCES") {
        out.push_back("BALANCES");
        vector<Integer> values = balances();
        for (int i : orderedMembers(true)) out.push_back("  " + members[i].name + " " + signedMoney(values[i]));
    } else if (command == "OWES") {
        int id = memberId(a[1]);
        out.push_back("OWES " + a[1]);
        vector<vector<Integer>> values = debts();
        for (int i : orderedMembers()) {
            if (i == id || !values[id][i]) continue;
            int from = values[id][i] > 0 ? id : i, to = values[id][i] > 0 ? i : id;
            out.push_back("  " + members[from].name + " owes " + members[to].name + " " + money(values[from][to]));
        }
    } else if (command == "HISTORY") {
        int id = memberId(a[1]);
        struct Item {
            Integer day, serial, change;
            string label;
        };
        vector<Item> items;
        for (const Expense &e : expenses) if (involved(e, id)) items.push_back({e.day, e.serial, net(e)[id], e.id});
        for (const Settlement &s : settlements) {
            if (s.from == id || s.to == id) items.push_back({s.day, s.serial, s.from == id ? s.total : -s.total, members[s.from].name + "->" + members[s.to].name});
        }
        std::sort(items.begin(), items.end(), [](const Item &x, const Item &y) { return std::make_pair(x.day, x.serial) < std::make_pair(y.day, y.serial); });
        out.push_back("HISTORY " + a[1]);
        Integer running = 0;
        for (const Item &item : items) {
            running += item.change;
            out.push_back(text("  day ", item.day, " ", item.label, " ", signedMoney(item.change), " balance ", signedMoney(running)));
        }
    } else if (command == "MATRIX") {
        out.push_back("MATRIX");
        vector<int> order = orderedMembers(true);
        if (order.empty()) out.push_back("  (none)");
        else {
            vector<vector<Integer>> values = debts();
            int l = 0, w = 0;
            for (int i : order) l = std::max(l, int(members[i].name.size()));
            w = l;
            for (int i : order) {
                for (int j : order) {
                    if (i != j) w = std::max(w, int(money(std::max(Integer(0), values[i][j])).size()));
                }
            }
            string header(l, ' ');
            for (int i : order) header += string(2 + w - members[i].name.size(), ' ') + members[i].name;
            out.push_back(header);
            for (int i : order) {
                string row = members[i].name + string(l - members[i].name.size(), ' ');
                for (int j : order) {
                    string cell = i == j ? "-" : money(std::max(Integer(0), values[i][j]));
                    row += string(2 + w - cell.size(), ' ') + cell;
                }
                out.push_back(row);
            }
        }
    } else if (command == "CATEGORY") {
        out.push_back("CATEGORY");
        std::map<string, Integer> totals;
        Integer total = 0;
        for (const Expense &e : expenses) {
            totals[e.category] += e.total;
            total += e.total;
        }
        vector<string> categories;
        for (const std::pair<const string, Integer> &entry : totals) categories.push_back(entry.first);
        std::sort(categories.begin(), categories.end(), [&](const string &x, const string &y) { return totals[x] != totals[y] ? totals[x] > totals[y] : x < y; });
        for (const string &category : categories) {
            out.push_back("  " + category + " " + money(totals[category]) + " " + percentage(totals[category], total));
            vector<Integer> shares(members.size());
            for (const Expense &e : expenses) {
                if (e.category == category) {
                    for (Part p : e.participants) shares[p.member] += p.result;
                }
            }
            vector<int> order = orderedMembers();
            std::stable_sort(order.begin(), order.end(), [&](int i, int j) { return shares[i] > shares[j]; });
            for (int i : order) if (shares[i]) out.push_back("    " + members[i].name + " " + money(shares[i]) + " " + percentage(shares[i], totals[category]));
        }
    } else if (command == "BUDGETS") {
        out.push_back("BUDGETS");
        for (const std::pair<const string, Integer> &entry : budgets) {
            Integer s = spent(entry.first), b = entry.second;
            out.push_back("  " + entry.first + " spent " + money(s) + " budget " + money(b) + " used " + percentage(s, b) + (s <= b ? " left " + money(b - s) : " over " + money(s - b)));
        }
    } else if (command == "TOTALS") {
        out.push_back("TOTALS");
        vector<Integer> paid(members.size()), shares(members.size()), sent(members.size()), received(members.size());
        Integer expenseTotal = 0, settlementTotal = 0;
        for (const Expense &e : expenses) {
            expenseTotal += e.total;
            for (Part p : e.payers) paid[p.member] += p.result;
            for (Part p : e.participants) shares[p.member] += p.result;
        }
        for (const Settlement &s : settlements) {
            settlementTotal += s.total;
            sent[s.from] += s.total;
            received[s.to] += s.total;
        }
        for (int i : orderedMembers()) out.push_back("  " + members[i].name + " paid " + money(paid[i]) + " share " + money(shares[i]) + " sent " + money(sent[i]) + " received " + money(received[i]));
        for (const std::pair<const string, Integer> &entry : currencies) {
            int count = 0;
            Integer original = 0, base = 0;
            for (const Expense &e : expenses) {
                if (e.currency == entry.first) {
                    ++count;
                    original += e.amount;
                    base += e.total;
                }
            }
            if (count) out.push_back(text("  currency ", entry.first, " expenses ", count, " amount ", money(original), " base ", money(base)));
        }
        out.push_back(text("  expenses ", expenses.size(), " total ", money(expenseTotal), " settlements ", settlements.size(), " total ", money(settlementTotal)));
    } else if (command == "MEMBERS") {
        out.push_back("MEMBERS");
        for (int i : orderedMembers()) {
            int count = 0;
            for (const Expense &e : expenses) if (involved(e, i)) ++count;
            out.push_back(text("  ", members[i].name, members[i].active ? " active day " : " left day ", members[i].day, " expenses ", count));
        }
    } else if (command == "EXPENSES") {
        int member = a[1] == "MEMBER" ? memberId(a[2]) : -1;
        out.push_back(line);
        int count = 0;
        Integer total = 0;
        for (int i : chronological()) {
            const Expense &e = expenses[i];
            bool matches = a[1] == "ALL" || (a[1] == "CATEGORY" && e.category == a[2]) || (a[1] == "MEMBER" && involved(e, member)) || (a[1] == "DAYS" && e.day >= std::stoll(a[2]) && e.day <= std::stoll(a[3]));
            if (!matches) continue;
            vector<string> names;
            for (Part p : e.payers) names.push_back(members[p.member].name);
            out.push_back(text("  day ", e.day, " ", e.id, " ", e.category, " ", money(e.total), " by ", join(names, ",")));
            ++count;
            total += e.total;
        }
        out.push_back(text("  count ", count, " total ", money(total)));
    } else if (command == "PERIODS") {
        Integer k = std::stoll(a[1]);
        std::map<Integer, std::pair<int, Integer>> groups;
        for (const Expense &e : expenses) {
            std::pair<int, Integer> &group = groups[(e.day - 1) / k];
            ++group.first;
            group.second += e.total;
        }
        out.push_back("PERIODS " + a[1]);
        for (const std::pair<const Integer, std::pair<int, Integer>> &entry : groups) out.push_back(text("  days ", entry.first * k + 1, "-", entry.first * k + k, " expenses ", entry.second.first, " total ", money(entry.second.second)));
    } else if (command == "SHOW") {
        const Expense &e = expenses[expenseId(a[1])];
        out.push_back("SHOW " + a[1]);
        out.push_back(text("  day ", e.day, " category ", e.category, " mode ", e.mode, " total ", money(e.total), note(e.amount, e.currency)));
        for (Part p : e.payers) out.push_back("  paid " + members[p.member].name + " " + money(p.result));
        Integer units = 0;
        for (Part p : e.participants) units += p.value;
        for (Part p : e.participants) {
            string suffix;
            if (e.mode == "EXACT") suffix = " " + money(p.value);
            if (e.mode == "PERCENT") suffix = " " + money(p.value) + "%";
            if (e.mode == "SHARES") suffix = text(" ", p.value, "/", units);
            if (e.mode == "ADJUST") suffix = " +" + money(p.value);
            out.push_back("  share " + members[p.member].name + " " + money(p.result) + suffix);
        }
        if (e.interval) out.push_back(text("  recurring interval ", e.interval, " next ", e.next));
    } else if (command == "SIMPLIFY") {
        vector<Integer> values = balances();
        vector<int> order;
        for (int i : orderedMembers()) if (values[i]) order.push_back(i);
        if (a[1] == "GREEDY") {
            vector<Transfer> transfers = greedy(order, values);
            out.push_back(text("SIMPLIFY GREEDY transfers ", transfers.size()));
            printTransfers(transfers, "  ", out);
        } else {
            int n = int(order.size());
            if (n > 12) fail("too many members");
            vector<Integer> sums(1 << n);
            for (int mask = 1; mask < (1 << n); ++mask) {
                int bit = 0;
                while (!(mask & (1 << bit))) ++bit;
                sums[mask] = sums[mask ^ (1 << bit)] + values[order[bit]];
            }
            vector<int> memo(1 << n, -1);
            memo[0] = 0;
            std::function<int(int)> best = [&](int mask) {
                if (memo[mask] >= 0) return memo[mask];
                int first = mask & -mask, result = 0;
                for (int sub = mask; sub; sub = (sub - 1) & mask) {
                    if ((sub & first) && sums[sub] == 0) result = std::max(result, 1 + best(mask ^ sub));
                }
                return memo[mask] = result;
            };
            int remaining = (1 << n) - 1, groupCount = best(remaining);
            out.push_back(text("SIMPLIFY OPTIMAL transfers ", n - groupCount, " groups ", groupCount));
            while (remaining) {
                int first = remaining & -remaining, chosen = 0;
                vector<int> chosenList;
                for (int sub = remaining; sub; sub = (sub - 1) & remaining) {
                    if (!(sub & first) || sums[sub] != 0 || 1 + best(remaining ^ sub) != best(remaining)) continue;
                    vector<int> list;
                    for (int i = 0; i < n; ++i) if (sub & (1 << i)) list.push_back(i);
                    if (!chosen || list < chosenList) {
                        chosen = sub;
                        chosenList = list;
                    }
                }
                vector<int> group;
                vector<string> names;
                for (int i : chosenList) {
                    group.push_back(order[i]);
                    names.push_back(members[order[i]].name);
                }
                out.push_back("  group " + join(names, " "));
                printTransfers(greedy(group, values), "    ", out);
                remaining ^= chosen;
            }
        }
    }
    const std::set<string> emptyMarker = {"BALANCES", "OWES", "HISTORY", "CATEGORY", "BUDGETS", "MEMBERS", "PERIODS"};
    if (emptyMarker.count(command) && out.size() == 1) out.push_back("  (none)");
    return out;
}
int main() {
    string line;
    std::getline(std::cin, line);
    int count = std::stoi(line);
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        try {
            vector<string> out = execute(line);
            for (const string &result : out) std::cout << result << '\n';
        } catch (const std::runtime_error &error) { std::cout << "ERROR " << error.what() << '\n'; }
    }
}
