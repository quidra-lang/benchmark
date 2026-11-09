#include <algorithm>
#include <array>
#include <cctype>
#include <iomanip>
#include <iterator>
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

using namespace std;
using Amount = long long;

const vector<string> rate_settings = {
    "STATE", "SUPP", "SSRATE", "MEDRATE", "ADDMED",
    "UIRATE", "MATCH", "MATCHMAX", "GARNCAP"
};
const vector<pair<string, Amount>> initial_settings = {
    {"STATE", 500}, {"SUPP", 2200}, {"SSRATE", 620}, {"MEDRATE", 145},
    {"ADDMED", 90}, {"UIRATE", 270}, {"MATCH", 5000}, {"MATCHMAX", 600},
    {"GARNCAP", 2500}, {"SSBASE", 16860000}, {"ADDBASE", 20000000},
    {"UIBASE", 700000}, {"RETIRECAP", 2300000}, {"ALLOWANCE", 15000},
    {"NIGHT", 100}
};
const vector<string> fields = {
    "R", "O", "D", "N", "P", "accrued", "salary", "leave", "deduction",
    "sales", "commission", "earnings", "bonus", "gross", "retirement", "health",
    "federal", "supplemental", "state", "social", "medicare", "garnishment",
    "net", "employer_social", "employer_medicare", "unemployment", "match",
    "employer", "W", "Y", "F", "J"
};
const array<string, 7> weekdays = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
using Totals = map<string, Amount>;
using Five = array<Amount, 5>;
using Six = array<Amount, 6>;

Amount cents(const string& text) {
    size_t dot = text.find('.');
    return stoll(text.substr(0, dot)) * 100 + stoll(text.substr(dot + 1));
}

string money(Amount amount) {
    ostringstream out;
    out << amount / 100 << '.' << setfill('0') << setw(2) << amount % 100;
    return out.str();
}

string rate_text(Amount rate) { return money(rate) + "%"; }

string duration(Amount minutes) {
    ostringstream out;
    out << minutes / 60 << ':' << setfill('0') << setw(2) << minutes % 60;
    return out.str();
}

string clock_text(int minutes) {
    ostringstream out;
    out << setfill('0') << setw(2) << minutes / 60 << ':'
        << setw(2) << minutes % 60;
    return out.str();
}

string weekday(int day) { return weekdays[(day - 1) % 7]; }
int period_of(int day) { return (day - 1) / 14 + 1; }

Totals empty_totals() {
    Totals totals;
    for (const string& field : fields) totals[field] = 0;
    return totals;
}

Totals sum_stubs(const vector<const Totals*>& stubs) {
    Totals result = empty_totals();
    for (const Totals* stub : stubs)
        for (const string& field : fields) result[field] += stub->at(field);
    return result;
}

Amount progressive(const map<Amount, Amount>& table, Amount amount) {
    Amount numerator = 0;
    for (auto it = table.begin(); it != table.end() && it->first < amount; ++it) {
        auto next = std::next(it);
        Amount upper = next == table.end() ? amount : next->first;
        numerator += it->second * (min(amount, upper) - it->first);
    }
    return numerator / 10000;
}

struct Garnishment {
    Amount rate;
    Amount balance;
};

struct Shift {
    int start;
    int end;
};

struct Stub {
    Totals values = empty_totals();
    vector<Amount> balances;
    Amount garnishment_balance = 0;
    Amount pto_balance = 0;

    Amount get(const string& key) const { return values.at(key); }
    Amount& operator[](const string& key) { return values[key]; }
};

struct StubRecord {
    Stub stub;
    string department;
};

struct Employee {
    int id = 0;
    string department;
    string kind;
    Amount base = 0;
    bool active = true;
    Amount retirement = 0, health = 0, allowances = 0, extra = 0;
    vector<Garnishment> garnishments;
    Amount bonus = 0, pto_balance = 0;
    map<int, vector<Shift>> shifts;
    map<int, int> pto;
    set<int> leave;
    map<int, Amount> sales;
    map<int, StubRecord> stubs;
    Totals ytd = empty_totals();
    int periods = 0;

    Amount garnish_balance() const {
        Amount total = 0;
        for (const Garnishment& order : garnishments) total += order.balance;
        return total;
    }
};

class Payroll {
    map<string, Amount> settings;
    map<Amount, Amount> brackets;
    map<Amount, Amount> tiers;
    set<int> holidays;
    map<int, Employee> employees;
    vector<string> output;
    int closed = 0;

    template<typename... Args>
    void emit(int indentation, const Args&... args) {
        ostringstream out;
        bool first = true;
        ((out << (first ? "" : " ") << args, first = false), ...);
        output.push_back(string(indentation, ' ') + out.str());
    }

    void emit_parts(int indentation, const vector<string>& parts) {
        ostringstream out;
        for (size_t i = 0; i < parts.size(); ++i) {
            if (i) out << ' ';
            out << parts[i];
        }
        output.push_back(string(indentation, ' ') + out.str());
    }

    static void fail(const string& message) { throw runtime_error(message); }

    Employee& employee(const string& text, bool active = false, const string& kind = "") {
        int identifier = stoi(text);
        auto it = employees.find(identifier);
        if (it == employees.end()) fail("unknown employee " + text);
        Employee& person = it->second;
        if (active && !person.active) fail("terminated employee " + text);
        if (!kind.empty() && person.kind != kind) {
            string lowered = kind;
            transform(lowered.begin(), lowered.end(), lowered.begin(),
                      [](unsigned char c) { return static_cast<char>(tolower(c)); });
            fail("not " + lowered + " " + text);
        }
        return person;
    }

    int day_check(const string& text) const {
        int day = stoi(text);
        if (day < 1 || day > 364) fail("invalid day " + text);
        int period = period_of(day);
        if (period <= closed) fail("period closed " + to_string(period));
        return day;
    }

    static int period_check(const string& text) {
        int period = stoi(text);
        if (period < 1 || period > 26) fail("invalid period " + text);
        return period;
    }

    static Amount rate_check(const string& text) {
        Amount rate = cents(text);
        if (rate > 10000) fail("invalid rate " + text);
        return rate;
    }

    static Amount amount_check(const string& text) {
        Amount amount = cents(text);
        if (amount == 0) fail("invalid amount");
        return amount;
    }

    static int time_check(const string& text) {
        int hour = stoi(text.substr(0, 2)), minute = stoi(text.substr(3, 2));
        if (hour > 23 || minute > 59) fail("invalid time " + text);
        return hour * 60 + minute;
    }

    Six daily(const Employee& person, int day) const {
        Amount worked = 0, night = 0;
        auto it = person.shifts.find(day);
        if (it != person.shifts.end()) {
            for (const Shift& shift : it->second) {
                worked += shift.end - shift.start;
                night += max(0, min(shift.end, 360) - shift.start);
                night += max(0, shift.end - max(shift.start, 1320));
            }
        }
        auto pto_it = person.pto.find(day);
        Amount pto = pto_it == person.pto.end() ? 0 : pto_it->second;
        if (day % 7 == 0 || holidays.count(day))
            return {worked, 0, 0, worked, night, pto};
        return {worked, min<Amount>(worked, 480),
                min<Amount>(max<Amount>(0, worked - 480), 240),
                max<Amount>(0, worked - 720), night, pto};
    }

    pair<Five, Amount> weekly(const Employee& person, int week) const {
        Five result{};
        for (int day = 7 * week - 6; day <= 7 * week; ++day) {
            Six values = daily(person, day);
            for (int i = 0; i < 5; ++i) result[i] += values[i + 1];
        }
        Amount weekly_overtime = max<Amount>(0, result[0] - 2400);
        result[0] -= weekly_overtime;
        result[1] += weekly_overtime;
        return {result, weekly_overtime};
    }

    Five breakdown(const Employee& person, int period) const {
        Five first = weekly(person, 2 * period - 1).first;
        Five second = weekly(person, 2 * period).first;
        for (int i = 0; i < 5; ++i) first[i] += second[i];
        return first;
    }

    optional<Stub> calculate(const Employee& person, int period) const {
        Stub stub;
        if (person.kind == "HOURLY") {
            Five hours = breakdown(person, period);
            for (int i = 0; i < 5; ++i) stub[fields[i]] = hours[i];
            Amount weighted = 2 * (hours[0] + hours[4]) + 3 * hours[1] + 4 * hours[2];
            stub["earnings"] =
                (weighted * person.base + 2 * hours[3] * settings.at("NIGHT")) / 120;
        } else if (person.kind == "SALARIED") {
            if (person.active) {
                stub["salary"] = person.base / 26;
                for (int day : person.leave)
                    if (period_of(day) == period && !holidays.count(day))
                        stub["leave"]++;
                stub["deduction"] = stub.get("leave") * (person.base / 260);
                stub["earnings"] = stub.get("salary") - stub.get("deduction");
            }
        } else {
            auto sale = person.sales.find(period);
            stub["sales"] = sale == person.sales.end() ? 0 : sale->second;
            stub["commission"] = progressive(tiers, stub.get("sales"));
            stub["earnings"] = stub.get("commission") + (person.active ? person.base : 0);
        }

        stub["bonus"] = person.bonus;
        Amount gross = stub.get("earnings") + stub.get("bonus");
        if (gross == 0) return nullopt;
        stub["gross"] = gross;
        Amount remaining = gross;

        auto deduct = [&](const string& field, Amount amount) {
            Amount actual = min(amount, remaining);
            stub[field] = actual;
            remaining -= actual;
        };

        Amount retirement_room =
            max<Amount>(0, settings.at("RETIRECAP") - person.ytd.at("retirement"));
        deduct("retirement", min(gross * person.retirement / 10000, retirement_room));
        deduct("health", person.health);
        stub["W"] = remaining;
        Amount base_taxable = max<Amount>(0,
            stub.get("earnings") - stub.get("retirement") - stub.get("health"));
        Amount taxable = max<Amount>(0,
            base_taxable - person.allowances * settings.at("ALLOWANCE"));
        deduct("federal", progressive(brackets, taxable) + person.extra);
        deduct("supplemental", (stub.get("W") - base_taxable) * settings.at("SUPP") / 10000);
        deduct("state", stub.get("W") * settings.at("STATE") / 10000);

        Amount medicare_wages = gross - stub.get("health");
        Amount social_wages = min(medicare_wages,
            max<Amount>(0, settings.at("SSBASE") - person.ytd.at("Y")));
        Amount additional = max<Amount>(0, min(medicare_wages,
            person.ytd.at("F") + medicare_wages - settings.at("ADDBASE")));
        stub["F"] = medicare_wages;
        stub["Y"] = social_wages;
        deduct("social", social_wages * settings.at("SSRATE") / 10000);
        deduct("medicare", medicare_wages * settings.at("MEDRATE") / 10000 +
                            additional * settings.at("ADDMED") / 10000);

        Amount disposable = remaining;
        Amount cap = disposable * settings.at("GARNCAP") / 10000;
        Amount garnished = 0;
        for (const Garnishment& order : person.garnishments) {
            Amount taken = min({disposable * order.rate / 10000,
                                order.balance, cap - garnished});
            garnished += taken;
            stub.balances.push_back(order.balance - taken);
        }
        stub["garnishment"] = garnished;
        stub.garnishment_balance =
            accumulate(stub.balances.begin(), stub.balances.end(), 0LL);
        stub["net"] = remaining - garnished;
        stub["employer_social"] = social_wages * settings.at("SSRATE") / 10000;
        stub["employer_medicare"] = medicare_wages * settings.at("MEDRATE") / 10000;
        stub["J"] = min(medicare_wages,
            max<Amount>(0, settings.at("UIBASE") - person.ytd.at("J")));
        stub["unemployment"] = stub.get("J") * settings.at("UIRATE") / 10000;
        Amount eligible_match = min(stub.get("retirement"),
                                    gross * settings.at("MATCHMAX") / 10000);
        stub["match"] = eligible_match * settings.at("MATCH") / 10000;
        stub["employer"] = stub.get("employer_social") + stub.get("employer_medicare") +
                           stub.get("unemployment") + stub.get("match");
        if (person.kind == "HOURLY")
            stub["accrued"] = min<Amount>(960 - person.pto_balance,
                (stub.get("R") + stub.get("O") + stub.get("D")) / 20);
        stub.pto_balance = person.pto_balance + stub.get("accrued");
        return stub;
    }

    static vector<string> hours_parts(const Five& values) {
        const array<string, 5> labels = {"reg", "ot", "dbl", "night", "pto"};
        vector<string> parts;
        for (int i = 0; i < 5; ++i) {
            parts.push_back(labels[i]);
            parts.push_back(duration(values[i]));
        }
        return parts;
    }

    void stub_block(const Employee& person, const Totals& stub, Amount pto_balance,
                    Amount garnish_balance, int indentation) {
        if (person.kind == "HOURLY") {
            Five values{};
            for (int i = 0; i < 5; ++i) values[i] = stub.at(fields[i]);
            vector<string> parts = {"hours"};
            vector<string> hourly = hours_parts(values);
            parts.insert(parts.end(), hourly.begin(), hourly.end());
            emit_parts(indentation, parts);
            emit(indentation, "pto", "accrued", duration(stub.at("accrued")),
                 "balance", duration(pto_balance));
        } else if (person.kind == "SALARIED") {
            emit(indentation, "salary", money(stub.at("salary")), "leave",
                 stub.at("leave"), "deduction", money(stub.at("deduction")));
        } else {
            emit(indentation, "sales", money(stub.at("sales")),
                 "commission", money(stub.at("commission")));
        }
        for (const string& field : {
                 "earnings", "bonus", "gross", "retirement", "health", "federal",
                 "supplemental", "state", "social", "medicare"
             }) {
            emit(indentation, field == "social" ? "social-security" : field,
                 money(stub.at(field)));
        }
        emit(indentation, "garnishment", money(stub.at("garnishment")),
             "balance", money(garnish_balance));
        emit(indentation, "net", money(stub.at("net")));
        emit(indentation, "employer", "social-security",
             money(stub.at("employer_social")),
             "medicare", money(stub.at("employer_medicare")),
             "unemployment", money(stub.at("unemployment")),
             "match", money(stub.at("match")));
    }

    void print_stub(const Employee& person, int period, const Stub& stub,
                    const string& department) {
        emit(2, "STUB", person.id, department, person.kind, "period", period);
        stub_block(person, stub.values, stub.pto_balance, stub.garnishment_balance, 4);
    }

    void show_hours(const Employee& person, int period) {
        emit(0, "HOURS", person.id, "period", period);
        bool found = false;
        for (int day = 14 * period - 13; day <= 14 * period; ++day) {
            auto it = person.shifts.find(day);
            vector<Shift> shifts = it == person.shifts.end() ? vector<Shift>{} : it->second;
            if (shifts.empty() && !person.pto.count(day)) continue;
            sort(shifts.begin(), shifts.end(), [](const Shift& a, const Shift& b) {
                return a.start < b.start;
            });
            Six values = daily(person, day);
            vector<string> parts = {"day", to_string(day), weekday(day)};
            if (holidays.count(day)) parts.push_back("holiday");
            for (const Shift& shift : shifts)
                parts.push_back(clock_text(shift.start) + "-" + clock_text(shift.end));
            parts.push_back("total");
            parts.push_back(duration(values[0]));
            Five current = {values[1], values[2], values[3], values[4], values[5]};
            vector<string> hours = hours_parts(current);
            parts.insert(parts.end(), hours.begin(), hours.end());
            emit_parts(2, parts);
            found = true;
        }
        if (!found) emit(2, "(none)");
        for (int week : {2 * period - 1, 2 * period}) {
            auto [values, overtime] = weekly(person, week);
            vector<string> parts = {"week", to_string(week)};
            vector<string> hours = hours_parts(values);
            parts.insert(parts.end(), hours.begin(), hours.end());
            parts.push_back("weekly-ot");
            parts.push_back(duration(overtime));
            emit_parts(2, parts);
        }
        vector<string> parts = {"total"};
        vector<string> hours = hours_parts(breakdown(person, period));
        parts.insert(parts.end(), hours.begin(), hours.end());
        emit_parts(2, parts);
    }

    void run(int period) {
        closed = period;
        emit(0, "RUN", period, "days",
             to_string(14 * period - 13) + "-" + to_string(14 * period));
        int paid = 0, skipped = 0;
        vector<const Totals*> created;
        for (auto& [id, person] : employees) {
            optional<Stub> calculated = calculate(person, period);
            if (!calculated) {
                if (person.active) ++skipped;
                continue;
            }
            Stub stub = move(*calculated);
            print_stub(person, period, stub, person.department);
            person.bonus = 0;
            person.pto_balance = stub.pto_balance;
            for (size_t i = 0; i < person.garnishments.size(); ++i)
                person.garnishments[i].balance = stub.balances[i];
            for (const string& field : fields)
                person.ytd[field] += stub.get(field);
            ++person.periods;
            person.stubs.emplace(period, StubRecord{move(stub), person.department});
            created.push_back(&person.stubs.at(period).stub.values);
            ++paid;
        }
        Totals total = sum_stubs(created);
        emit(2, "TOTAL", "paid", paid, "skipped", skipped, "gross",
             money(total["gross"]), "deductions", money(total["gross"] - total["net"]),
             "net", money(total["net"]), "employer", money(total["employer"]));
    }

    void journal(int period) {
        vector<const Totals*> stubs;
        for (const auto& [id, person] : employees) {
            auto it = person.stubs.find(period);
            if (it != person.stubs.end())
                stubs.push_back(&it->second.stub.values);
        }
        Totals total = sum_stubs(stubs);
        struct Row { string side, label; Amount amount; };
        vector<Row> rows = {
            {"debit", "wages", total["gross"]},
            {"debit", "employer-tax",
             total["employer_social"] + total["employer_medicare"] + total["unemployment"]},
            {"debit", "retirement-match", total["match"]},
            {"credit", "retirement", total["retirement"] + total["match"]},
            {"credit", "health", total["health"]},
            {"credit", "federal", total["federal"] + total["supplemental"]},
            {"credit", "state", total["state"]},
            {"credit", "fica", total["social"] + total["medicare"] +
                      total["employer_social"] + total["employer_medicare"]},
            {"credit", "unemployment", total["unemployment"]},
            {"credit", "garnishment", total["garnishment"]},
            {"credit", "net-pay", total["net"]}
        };
        emit(0, "JOURNAL", period, "stubs", stubs.size());
        Amount debit = 0, credit = 0;
        for (const Row& row : rows) {
            emit(2, row.side, row.label, money(row.amount));
            if (row.side == "debit") debit += row.amount;
            else credit += row.amount;
        }
        emit(2, "total", "debit", money(debit), "credit", money(credit));
    }

    void report_line(const string& department, const vector<const Totals*>& stubs) {
        Totals total = sum_stubs(stubs);
        Amount taxes = total["federal"] + total["supplemental"] +
                       total["state"] + total["social"] + total["medicare"];
        emit(2, department, "stubs", stubs.size(), "gross", money(total["gross"]),
             "pretax", money(total["retirement"] + total["health"]),
             "taxes", money(taxes), "garnishment", money(total["garnishment"]),
             "net", money(total["net"]), "employer", money(total["employer"]));
    }

    void command(const string& cmd, const vector<string>& a) {
        if (cmd == "SET") {
            auto it = settings.find(a[0]);
            if (it == settings.end()) fail("unknown setting " + a[0]);
            bool rate = find(rate_settings.begin(), rate_settings.end(), a[0])
                        != rate_settings.end();
            Amount value = rate ? rate_check(a[1]) : cents(a[1]);
            Amount old = it->second;
            it->second = value;
            emit(0, "SET", a[0], rate ? rate_text(old) : money(old),
                 "->", rate ? rate_text(value) : money(value));
        } else if (cmd == "BRACKET" || cmd == "TIER") {
            Amount rate = rate_check(a[1]);
            auto& table = cmd == "BRACKET" ? brackets : tiers;
            Amount lower = cents(a[0]);
            bool replaced = table.count(lower);
            table[lower] = rate;
            emit(0, cmd, money(lower), rate_text(rate),
                 replaced ? "replaced" : "added");
        } else if (cmd == "EMP") {
            int id = stoi(a[0]);
            if (employees.count(id)) fail("duplicate employee " + a[0]);
            Amount base = amount_check(a[3]);
            Employee person;
            person.id = id;
            person.department = a[1];
            person.kind = a[2];
            person.base = base;
            employees.emplace(id, move(person));
            emit(0, "EMP", id, a[1], a[2], money(base));
        } else if (cmd == "RATE" || cmd == "DEPT" || cmd == "BENEFIT" ||
                   cmd == "W4" || cmd == "GARNISH" || cmd == "TERM" || cmd == "BONUS") {
            Employee& person = employee(a[0], true);
            if (cmd == "RATE") {
                Amount base = amount_check(a[1]), old = person.base;
                person.base = base;
                emit(0, "RATE", person.id, money(old), "->", money(base));
            } else if (cmd == "DEPT") {
                if (a[1] == person.department) fail("same department " + a[1]);
                string old = person.department;
                person.department = a[1];
                emit(0, "DEPT", person.id, old, "->", a[1]);
            } else if (cmd == "BENEFIT") {
                Amount rate = rate_check(a[1]);
                person.retirement = rate;
                person.health = cents(a[2]);
                emit(0, "BENEFIT", person.id, "retirement", rate_text(rate),
                     "health", money(person.health));
            } else if (cmd == "W4") {
                person.allowances = stoll(a[1]);
                person.extra = cents(a[2]);
                emit(0, "W4", person.id, "allowances", person.allowances,
                     "extra", money(person.extra));
            } else if (cmd == "GARNISH") {
                Amount rate = rate_check(a[1]);
                Amount amount = amount_check(a[2]);
                person.garnishments.push_back({rate, amount});
                emit(0, "GARNISH", person.id, "order", person.garnishments.size(),
                     rate_text(rate), "balance", money(amount));
            } else if (cmd == "TERM") {
                person.active = false;
                emit(0, "TERM", person.id);
            } else {
                Amount amount = amount_check(a[1]);
                person.bonus += amount;
                emit(0, "BONUS", person.id, money(amount), "pending", money(person.bonus));
            }
        } else if (cmd == "HOLIDAY") {
            int day = day_check(a[0]);
            if (holidays.count(day)) fail("duplicate holiday " + a[0]);
            holidays.insert(day);
            emit(0, "HOLIDAY", day, weekday(day));
        } else if (cmd == "TIME" || cmd == "UNTIME" || cmd == "PTO" ||
                   cmd == "LEAVE" || cmd == "SALES") {
            string kind = cmd == "LEAVE" ? "SALARIED" :
                          cmd == "SALES" ? "COMMISSION" : "HOURLY";
            Employee& person = employee(a[0], true, kind);
            int day = day_check(a[1]);
            if (cmd == "TIME") {
                int start = time_check(a[2]), end = time_check(a[3]);
                if (start >= end) fail("invalid shift " + a[2] + "-" + a[3]);
                auto shift_it = person.shifts.find(day);
                vector<Shift> shifts = shift_it == person.shifts.end() ?
                    vector<Shift>{} : shift_it->second;
                sort(shifts.begin(), shifts.end(), [](const Shift& a, const Shift& b) {
                    return a.start < b.start;
                });
                for (const Shift& shift : shifts)
                    if (start < shift.end && shift.start < end)
                        fail("overlapping shift " + clock_text(shift.start) + "-" +
                             clock_text(shift.end));
                int worked = end - start;
                for (const Shift& shift : shifts) worked += shift.end - shift.start;
                if (worked > 960) fail("daily limit " + a[0] + " " + a[1]);
                person.shifts[day].push_back({start, end});
                emit(0, "TIME", person.id, "day", day,
                     clock_text(start) + "-" + clock_text(end), duration(end - start));
            } else if (cmd == "UNTIME") {
                int start = time_check(a[2]);
                auto it = person.shifts.find(day);
                if (it == person.shifts.end()) fail("no shift " + a[0] + " " + a[1] + " " + a[2]);
                auto& shifts = it->second;
                auto found = find_if(shifts.begin(), shifts.end(), [start](const Shift& shift) {
                    return shift.start == start;
                });
                if (found == shifts.end()) fail("no shift " + a[0] + " " + a[1] + " " + a[2]);
                Shift removed = *found;
                shifts.erase(found);
                emit(0, "UNTIME", person.id, "day", day,
                     clock_text(removed.start) + "-" + clock_text(removed.end));
            } else if (cmd == "PTO") {
                int hour = stoi(a[2].substr(0, 2));
                int minute = stoi(a[2].substr(3, 2));
                int length = hour * 60 + minute;
                if (minute > 59 || length < 1 || length > 480)
                    fail("invalid duration " + a[2]);
                if (person.pto.count(day)) fail("duplicate pto " + a[0] + " " + a[1]);
                if (length > person.pto_balance)
                    fail("insufficient pto " + a[0] + " " + duration(person.pto_balance));
                person.pto[day] = length;
                person.pto_balance -= length;
                emit(0, "PTO", person.id, "day", day, duration(length),
                     "balance", duration(person.pto_balance));
            } else if (cmd == "LEAVE") {
                if (day % 7 == 0 || day % 7 == 6 || holidays.count(day))
                    fail("not workday " + a[1]);
                if (person.leave.count(day)) fail("duplicate leave " + a[0] + " " + a[1]);
                person.leave.insert(day);
                emit(0, "LEAVE", person.id, "day", day, weekday(day));
            } else {
                Amount amount = amount_check(a[2]);
                int period = period_of(day);
                person.sales[period] += amount;
                emit(0, "SALES", person.id, "day", day, money(amount),
                     "period", period, "total", money(person.sales[period]));
            }
        } else if (cmd == "HOURS") {
            Employee& person = employee(a[0], false, "HOURLY");
            int period = period_check(a[1]);
            show_hours(person, period);
        } else if (cmd == "RUN") {
            int period = stoi(a[0]);
            if (period != closed + 1 || period > 26) fail("invalid period " + a[0]);
            run(period);
        } else if (cmd == "PREVIEW") {
            Employee& person = employee(a[0]);
            int period = closed + 1;
            optional<Stub> stub = calculate(person, period);
            emit(0, "PREVIEW", person.id, "period", period);
            if (!stub) emit(2, "no pay");
            else print_stub(person, period, *stub, person.department);
        } else if (cmd == "REPRINT") {
            Employee& person = employee(a[0]);
            int period = period_check(a[1]);
            auto it = person.stubs.find(period);
            if (it == person.stubs.end()) fail("no stub " + a[0] + " " + a[1]);
            emit(0, "REPRINT", person.id, period);
            print_stub(person, period, it->second.stub, it->second.department);
        } else if (cmd == "YTD") {
            Employee& person = employee(a[0]);
            emit(0, "YTD", person.id, person.department, person.kind,
                 person.active ? "active" : "terminated", "periods", person.periods);
            stub_block(person, person.ytd, person.pto_balance, person.garnish_balance(), 2);
            emit(2, "wages", "federal", money(person.ytd["W"]),
                 "social-security", money(person.ytd["Y"]),
                 "medicare", money(person.ytd["F"]),
                 "unemployment", money(person.ytd["J"]));
            emit(2, "retirement-room",
                 money(max<Amount>(0, settings["RETIRECAP"] - person.ytd["retirement"])),
                 "pending-bonus", money(person.bonus));
        } else if (cmd == "JOURNAL") {
            int period = stoi(a[0]);
            if (period < 1 || period > closed) fail("no run " + a[0]);
            journal(period);
        } else if (cmd == "REPORT") {
            map<string, vector<const Totals*>> departments;
            vector<const Totals*> all;
            for (const auto& [id, person] : employees) {
                for (const auto& [period, record] : person.stubs) {
                    departments[record.department].push_back(&record.stub.values);
                    all.push_back(&record.stub.values);
                }
            }
            emit(0, "REPORT", "period", closed);
            for (const auto& [department, stubs] : departments)
                report_line(department, stubs);
            report_line("total", all);
        } else if (cmd == "TOP") {
            int count = stoi(a[0]);
            vector<const Employee*> ranking;
            for (const auto& [id, person] : employees)
                if (person.periods) ranking.push_back(&person);
            sort(ranking.begin(), ranking.end(), [](const Employee* a, const Employee* b) {
                return a->ytd.at("gross") != b->ytd.at("gross") ?
                       a->ytd.at("gross") > b->ytd.at("gross") : a->id < b->id;
            });
            emit(0, "TOP", count);
            for (int i = 0; i < count && i < static_cast<int>(ranking.size()); ++i) {
                const Employee& person = *ranking[i];
                emit(2, i + 1, person.id, person.department, "gross",
                     money(person.ytd.at("gross")), "net", money(person.ytd.at("net")));
            }
            if (ranking.empty()) emit(2, "(none)");
        } else if (cmd == "EMPLOYEES") {
            emit(0, "EMPLOYEES");
            for (const auto& [id, person] : employees) {
                emit(2, id, person.department, person.kind, money(person.base),
                     person.active ? "active" : "terminated",
                     "retirement", rate_text(person.retirement),
                     "health", money(person.health),
                     "allowances", person.allowances, "extra", money(person.extra),
                     "bonus", money(person.bonus));
                for (size_t i = 0; i < person.garnishments.size(); ++i) {
                    const Garnishment& order = person.garnishments[i];
                    emit(4, "garnish", i + 1, rate_text(order.rate),
                         "balance", money(order.balance));
                }
            }
            if (employees.empty()) emit(2, "(none)");
        } else if (cmd == "CONFIG") {
            emit(0, "CONFIG");
            for (const auto& [name, default_value] : initial_settings) {
                Amount value = settings[name];
                bool rate = find(rate_settings.begin(), rate_settings.end(), name)
                            != rate_settings.end();
                emit(2, name, rate ? rate_text(value) : money(value));
            }
            for (const auto& [lower, rate] : brackets)
                emit(2, "bracket", money(lower), rate_text(rate));
            for (const auto& [lower, rate] : tiers)
                emit(2, "tier", money(lower), rate_text(rate));
        }
    }

public:
    Payroll() {
        for (const auto& [name, value] : initial_settings) settings[name] = value;
    }

    void execute(const string& line) {
        istringstream input(line);
        string cmd;
        input >> cmd;
        vector<string> args;
        string token;
        while (input >> token) args.push_back(token);
        try {
            command(cmd, args);
        } catch (const runtime_error& error) {
            emit(0, "ERROR", error.what());
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
    cin.ignore();
    Payroll payroll;
    string line;
    for (int i = 0; i < count; ++i) {
        getline(cin, line);
        payroll.execute(line);
    }
    payroll.print();
}
