#include <algorithm>
#include <array>
#include <functional>
#include <iomanip>
#include <iostream>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

[[noreturn]] static void fail(const std::string& message) {
    throw std::runtime_error(message);
}

static std::string joined(const std::vector<std::string>& words, const std::string& separator = " ") {
    std::string result;
    for (const std::string& word : words) {
        if (!result.empty()) result += separator;
        result += word;
    }
    return result;
}

static std::string signedNumber(int value) {
    return (value >= 0 ? "+" : "") + std::to_string(value);
}

static std::string decimal(int numerator, int denominator) {
    int hundredths = numerator * 100 / denominator;
    std::ostringstream text;
    text << hundredths / 100 << '.' << std::setw(2) << std::setfill('0') << hundredths % 100;
    return text.str();
}

static bool leap(int year) {
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

static int monthDays(int year, int month) {
    static const int lengths[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    return lengths[month - 1] + (month == 2 && leap(year) ? 1 : 0);
}

static int parseDate(const std::string& text) {
    int year = std::stoi(text.substr(0, 4)), month = std::stoi(text.substr(5, 2)), day = std::stoi(text.substr(8, 2));
    if (month < 1 || month > 12 || day < 1 || day > monthDays(year, month)) fail("invalid date " + text);
    int serial = day - 1;
    for (int y = 2000; y < year; ++y) serial += leap(y) ? 366 : 365;
    for (int m = 1; m < month; ++m) serial += monthDays(year, m);
    return serial;
}

static int weekday(int date) {
    return (date + 5) % 7;
}

static std::string dateText(int date) {
    static const char* weekdays[] = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"};
    int year = 2000, month = 1, remaining = date;
    while (remaining >= (leap(year) ? 366 : 365)) {
        remaining -= leap(year) ? 366 : 365;
        ++year;
    }
    while (remaining >= monthDays(year, month)) {
        remaining -= monthDays(year, month);
        ++month;
    }
    std::ostringstream text;
    text << year << '-' << std::setfill('0') << std::setw(2) << month << '-' << std::setw(2) << remaining + 1
         << ' ' << weekdays[weekday(date)];
    return text.str();
}

struct Crash {
    int limit;
    int cost;
};

struct Task {
    int base;
    std::string resource;
    int units;
    int notBefore = 0;
    int used = 0;
    std::optional<Crash> crash;
    std::optional<std::array<int, 3>> estimate;

    int duration() const { return base - used; }
};

struct Dependency {
    std::string kind;
    int lag;
};

struct Timing {
    int duration = 0;
    int es = 0;
    int ef = 0;
    int ls = 0;
    int lf = 0;
    int tf = 0;
    int free = 0;
};

struct Schedule {
    std::map<std::string, Timing> times;
    int duration = 0;
};

struct Baseline {
    int duration;
    std::map<std::string, std::pair<int, int>> times;
};

class Scheduler {
    std::map<std::string, Task> tasks;
    std::map<std::pair<std::string, std::string>, Dependency> dependencies;
    std::map<std::string, int> capacities;
    std::set<int> holidays;
    std::optional<int> startDate, deadline;
    std::optional<Baseline> baseline;

    Task& task(const std::string& name) {
        auto found = tasks.find(name);
        if (found == tasks.end()) fail("unknown task " + name);
        return found->second;
    }

    std::pair<std::vector<std::string>, std::string> topology() const {
        std::map<std::string, int> degree;
        for (const auto& [name, item] : tasks) degree[name] = 0;
        for (const auto& [ends, link] : dependencies) ++degree[ends.second];
        std::set<std::string> ready;
        for (const auto& [name, count] : degree) {
            if (count == 0) ready.insert(name);
        }
        std::vector<std::string> order;
        while (!ready.empty()) {
            std::string name = *ready.begin();
            ready.erase(ready.begin());
            order.push_back(name);
            for (const auto& [ends, link] : dependencies) {
                if (ends.first == name && --degree[ends.second] == 0) ready.insert(ends.second);
            }
        }
        if (order.size() == tasks.size()) return {order, ""};
        std::string current;
        for (const auto& [name, count] : degree) {
            if (count > 0) {
                current = name;
                break;
            }
        }
        std::vector<std::string> backwards;
        while (std::find(backwards.begin(), backwards.end(), current) == backwards.end()) {
            backwards.push_back(current);
            for (const auto& [ends, link] : dependencies) {
                if (ends.second == current && degree.at(ends.first) > 0) {
                    current = ends.first;
                    break;
                }
            }
        }
        auto first = std::find(backwards.begin(), backwards.end(), current);
        std::vector<std::string> cycle(first, backwards.end());
        std::reverse(cycle.begin(), cycle.end());
        std::rotate(cycle.begin(), std::min_element(cycle.begin(), cycle.end()), cycle.end());
        cycle.push_back(cycle.front());
        return {order, joined(cycle, " -> ")};
    }

    Schedule compute(const std::vector<std::string>& order, const std::string& changed = "", int replacement = 0) const {
        Schedule schedule;
        for (const std::string& name : order) {
            Timing time;
            const Task& item = tasks.at(name);
            time.duration = name == changed ? replacement : item.duration();
            time.es = item.notBefore;
            for (const auto& [ends, link] : dependencies) {
                if (ends.second != name) continue;
                const Timing& previous = schedule.times.at(ends.first);
                int bound = link.kind == "SS" ? previous.es : previous.ef;
                bound += link.lag;
                if (link.kind == "FF") bound -= time.duration;
                time.es = std::max(time.es, bound);
            }
            time.ef = time.es + time.duration;
            schedule.duration = std::max(schedule.duration, time.ef);
            schedule.times[name] = time;
        }
        for (auto position = order.rbegin(); position != order.rend(); ++position) {
            Timing& time = schedule.times.at(*position);
            time.lf = schedule.duration;
            for (const auto& [ends, link] : dependencies) {
                if (ends.first != *position) continue;
                const Timing& next = schedule.times.at(ends.second);
                int bound = link.kind == "FF" ? next.lf : next.ls;
                bound -= link.lag;
                if (link.kind == "SS") bound += time.duration;
                time.lf = std::min(time.lf, bound);
            }
            time.ls = time.lf - time.duration;
            time.tf = time.ls - time.es;
            time.free = schedule.duration - time.ef;
        }
        for (const auto& [ends, link] : dependencies) {
            Timing& previous = schedule.times.at(ends.first);
            const Timing& next = schedule.times.at(ends.second);
            int margin = (link.kind == "FF" ? next.ef : next.es)
                       - (link.kind == "SS" ? previous.es : previous.ef) - link.lag;
            previous.free = std::min(previous.free, margin);
        }
        return schedule;
    }

    static std::vector<std::string> criticalNames(const Schedule& schedule) {
        std::vector<std::string> names;
        for (const auto& [name, time] : schedule.times) {
            if (time.tf == 0) names.push_back(name);
        }
        return names;
    }

    std::vector<std::vector<std::string>> criticalPaths(const Schedule& schedule) const {
        std::map<std::string, std::vector<std::string>> next;
        std::set<std::string> nonroots;
        for (const std::string& name : criticalNames(schedule)) next[name] = {};
        for (const auto& [ends, link] : dependencies) {
            const Timing& previous = schedule.times.at(ends.first);
            const Timing& following = schedule.times.at(ends.second);
            int margin = (link.kind == "FF" ? following.ef : following.es)
                       - (link.kind == "SS" ? previous.es : previous.ef) - link.lag;
            if (previous.tf == 0 && following.tf == 0 && margin == 0) {
                next[ends.first].push_back(ends.second);
                nonroots.insert(ends.second);
            }
        }
        std::vector<std::vector<std::string>> paths;
        std::vector<std::string> path;
        std::function<void(const std::string&)> visit = [&](const std::string& name) {
            path.push_back(name);
            if (next.at(name).empty()) paths.push_back(path);
            else for (const std::string& child : next.at(name)) visit(child);
            path.pop_back();
        };
        for (const auto& [name, children] : next) {
            if (!nonroots.count(name)) visit(name);
        }
        return paths;
    }

    static std::vector<std::string> startOrder(const Schedule& schedule) {
        std::vector<std::string> names;
        for (const auto& [name, time] : schedule.times) names.push_back(name);
        std::sort(names.begin(), names.end(), [&](const std::string& a, const std::string& b) {
            return std::make_pair(schedule.times.at(a).es, a) < std::make_pair(schedule.times.at(b).es, b);
        });
        return names;
    }

    bool working(int date) const {
        return weekday(date) < 5 && !holidays.count(date);
    }

    void calendar(const Schedule& schedule) const {
        if (!startDate) fail("no start date");
        std::vector<int> dates;
        for (int date = *startDate; dates.size() < static_cast<std::size_t>(schedule.duration); ++date) {
            if (working(date)) dates.push_back(date);
        }
        for (const std::string& name : startOrder(schedule)) {
            const Timing& time = schedule.times.at(name);
            std::cout << name << ' ' << dateText(dates[time.es]) << " - " << dateText(dates[time.ef - 1]) << '\n';
        }
        int first = dates.front(), last = dates.back();
        std::cout << "project " << dateText(first) << " - " << dateText(last) << ", " << schedule.duration
                  << " working days, " << last - first + 1 << " calendar days\n";
        if (deadline) {
            int spare = 0;
            for (int date = std::min(last, *deadline) + 1; date <= std::max(last, *deadline); ++date) spare += working(date);
            std::cout << "deadline " << dateText(*deadline);
            if (last <= *deadline) std::cout << " met, " << spare << " working days to spare\n";
            else std::cout << " missed by " << spare << " working days\n";
        }
        std::vector<std::string> inSpan;
        for (int date : holidays) {
            if (first <= date && date <= last && weekday(date) < 5) inSpan.push_back(dateText(date));
        }
        std::cout << "holidays in span: " << (inSpan.empty() ? "none" : joined(inSpan, ", ")) << '\n';
    }

    std::map<std::string, std::vector<int>> usage(const Schedule& schedule) const {
        std::map<std::string, std::vector<int>> totals;
        for (const auto& [name, item] : tasks) {
            std::vector<int>& days = totals[item.resource];
            days.resize(schedule.duration, 0);
            const Timing& time = schedule.times.at(name);
            for (int day = time.es; day < time.ef; ++day) days[day] += item.units;
        }
        return totals;
    }

    void level(const Schedule& schedule, int fallback) const {
        auto capacity = [&](const std::string& resource) {
            auto found = capacities.find(resource);
            return found == capacities.end() ? fallback : found->second;
        };
        for (const auto& [name, item] : tasks) {
            int limit = capacity(item.resource);
            if (item.units > limit) fail("capacity " + std::to_string(limit) + " too small for " + name);
        }
        Schedule leveled;
        std::vector<std::string> decided;
        std::map<std::string, std::vector<int>> totals;
        while (decided.size() < tasks.size()) {
            std::string best;
            for (const auto& [name, item] : tasks) {
                if (leveled.times.count(name)) continue;
                bool ready = true;
                for (const auto& [ends, link] : dependencies) {
                    if (ends.second == name && !leveled.times.count(ends.first)) ready = false;
                }
                if (ready && (best.empty() || schedule.times.at(name).ls < schedule.times.at(best).ls)) best = name;
            }
            const Task& item = tasks.at(best);
            Timing time;
            time.duration = item.duration();
            time.es = item.notBefore;
            for (const auto& [ends, link] : dependencies) {
                if (ends.second != best) continue;
                const Timing& previous = leveled.times.at(ends.first);
                int bound = (link.kind == "SS" ? previous.es : previous.ef) + link.lag;
                if (link.kind == "FF") bound -= time.duration;
                time.es = std::max(time.es, bound);
            }
            std::vector<int>& days = totals[item.resource];
            while (true) {
                days.resize(std::max(days.size(), static_cast<std::size_t>(time.es + time.duration)), 0);
                bool available = true;
                for (int day = time.es; day < time.es + time.duration; ++day) {
                    if (days[day] + item.units > capacity(item.resource)) available = false;
                }
                if (available) break;
                ++time.es;
            }
            time.ef = time.es + time.duration;
            for (int day = time.es; day < time.ef; ++day) days[day] += item.units;
            leveled.times[best] = time;
            leveled.duration = std::max(leveled.duration, time.ef);
            decided.push_back(best);
        }
        std::cout << "level capacity " << fallback << ": duration " << schedule.duration << " -> " << leveled.duration << '\n';
        for (const std::string& name : decided) {
            const Timing& time = leveled.times.at(name);
            std::cout << name << " start " << time.es << " finish " << time.ef << " shift "
                      << time.es - schedule.times.at(name).es << '\n';
        }
        auto original = usage(schedule), result = usage(leveled);
        for (const auto& [resource, days] : original) {
            const std::vector<int>& changed = result.at(resource);
            std::cout << "resource " << resource << " capacity " << capacity(resource) << " peak "
                      << *std::max_element(days.begin(), days.end()) << " -> " << *std::max_element(changed.begin(), changed.end()) << '\n';
        }
    }

    void crash(const std::vector<std::string>& order, int budget) {
        int initial = compute(order).duration, remaining = budget, count = 0;
        std::string reason;
        while (true) {
            Schedule schedule = compute(order);
            std::string best;
            for (const auto& [name, item] : tasks) {
                if (schedule.times.at(name).tf != 0 || !item.crash || item.used >= item.crash->limit) continue;
                if (compute(order, name, item.duration() - 1).duration >= schedule.duration) continue;
                if (best.empty() || item.crash->cost < tasks.at(best).crash->cost) best = name;
            }
            if (best.empty()) {
                reason = "no candidate";
                break;
            }
            Task& item = tasks.at(best);
            if (item.crash->cost > remaining) {
                reason = "insufficient budget";
                break;
            }
            int before = item.duration();
            ++item.used;
            remaining -= item.crash->cost;
            std::cout << "step " << ++count << ": " << best << ' ' << before << " -> " << item.duration()
                      << ", cost " << item.crash->cost << ", project " << compute(order).duration << '\n';
        }
        std::cout << "crash done: " << count << " days, cost " << budget - remaining << ", project " << initial
                  << " -> " << compute(order).duration << ", budget left " << remaining << ", " << reason << '\n';
    }

    void analyze(const std::vector<std::string>& words) {
        if (tasks.empty()) fail("no tasks");
        auto [order, cycle] = topology();
        if (!cycle.empty()) fail("cycle " + cycle);
        const std::string& command = words[0];
        if (command == "WHATIF") task(words[1]);
        if (command == "VARIANCE" && !baseline) fail("no baseline");
        Schedule schedule = compute(order);
        if (command == "CPM") {
            std::size_t width = 4;
            for (const auto& [name, item] : tasks) width = std::max(width, name.size());
            std::cout << std::left << std::setw(static_cast<int>(width)) << "TASK" << std::right;
            for (const char* label : {"DUR", "ES", "EF", "LS", "LF", "TF", "FF"}) std::cout << std::setw(5) << label;
            std::cout << '\n';
            for (const auto& [name, time] : schedule.times) {
                std::cout << std::left << std::setw(static_cast<int>(width)) << name << std::right;
                for (int value : {time.duration, time.es, time.ef, time.ls, time.lf, time.tf, time.free}) std::cout << std::setw(5) << value;
                if (time.tf == 0) std::cout << " *";
                std::cout << '\n';
            }
            std::cout << "project duration " << schedule.duration << '\n';
        } else if (command == "CRITICAL" || command == "PERTSUM") {
            std::vector<std::vector<std::string>> paths = criticalPaths(schedule);
            if (command == "CRITICAL") std::cout << "critical paths: " << paths.size() << '\n';
            for (const auto& path : paths) {
                std::cout << joined(path, " -> ");
                if (command == "PERTSUM") {
                    int expected = 0, variance = 0;
                    for (const std::string& name : path) {
                        const Task& item = tasks.at(name);
                        std::array<int, 3> estimate = item.estimate.value_or(std::array<int, 3>{item.duration(), item.duration(), item.duration()});
                        expected += estimate[0] + 4 * estimate[1] + estimate[2];
                        variance += (estimate[2] - estimate[0]) * (estimate[2] - estimate[0]);
                    }
                    std::cout << ": expected " << decimal(expected, 6) << " variance " << decimal(variance, 36);
                }
                std::cout << '\n';
            }
        } else if (command == "SLACK") {
            std::map<int, std::vector<std::string>> floats;
            for (const auto& [name, time] : schedule.times) floats[time.tf].push_back(name);
            for (const auto& [amount, names] : floats) std::cout << "float " << amount << ": " << joined(names) << '\n';
        } else if (command == "DRAG") {
            for (const std::string& name : criticalNames(schedule)) {
                std::cout << name << " drag " << schedule.duration - compute(order, name, 0).duration << '\n';
            }
        } else if (command == "STATS") {
            std::map<std::string, int> kinds, work;
            for (const auto& [ends, link] : dependencies) ++kinds[link.kind];
            for (const auto& [name, item] : tasks) work[item.resource] += item.duration() * item.units;
            int totalFloat = 0;
            for (const auto& [name, time] : schedule.times) totalFloat += time.tf;
            std::cout << "tasks " << tasks.size() << ", critical " << criticalNames(schedule).size() << ", dependencies "
                      << dependencies.size() << " (FS " << kinds["FS"] << ", SS " << kinds["SS"] << ", FF " << kinds["FF"] << ")\nwork ";
            std::vector<std::string> totals;
            for (const auto& [resource, amount] : work) totals.push_back(resource + " " + std::to_string(amount));
            std::cout << joined(totals, ", ") << "\nfloat total " << totalFloat << ", average " << decimal(totalFloat, static_cast<int>(tasks.size()))
                      << "\nduration " << schedule.duration << ", critical share " << decimal(100 * static_cast<int>(criticalNames(schedule).size()), static_cast<int>(tasks.size())) << "%\n";
        } else if (command == "CALENDAR") calendar(schedule);
        else if (command == "GANTT") {
            if (schedule.duration > 60) fail("chart too wide (" + std::to_string(schedule.duration) + " days)");
            std::size_t width = 0;
            for (const auto& [name, item] : tasks) width = std::max(width, name.size());
            std::cout << std::string(width, ' ') << " |";
            for (int day = 0; day < schedule.duration; ++day) std::cout << day % 10;
            std::cout << "|\n";
            for (const std::string& name : startOrder(schedule)) {
                const Timing& time = schedule.times.at(name);
                std::string bar(schedule.duration, ' ');
                for (int day = 0; day < schedule.duration; ++day) {
                    if (time.es <= day && day < time.ef) bar[day] = time.tf == 0 ? '=' : '-';
                    else if (time.ef <= day && day < time.lf) bar[day] = '.';
                }
                std::cout << name << std::string(width - name.size(), ' ') << " |" << bar << "|\n";
            }
        } else if (command == "LEVEL") level(schedule, std::stoi(words[1]));
        else if (command == "LOAD") {
            auto totals = usage(schedule);
            auto found = totals.find(words[1]);
            if (found == totals.end()) fail("unknown resource " + words[1]);
            const std::vector<int>& days = found->second;
            std::cout << "load " << words[1] << ':';
            for (int amount : days) std::cout << ' ' << amount;
            auto peak = std::max_element(days.begin(), days.end());
            std::cout << "\npeak " << *peak << " on day " << peak - days.begin() << '\n';
            auto limit = capacities.find(words[1]);
            if (limit != capacities.end()) {
                int exceeded = static_cast<int>(std::count_if(days.begin(), days.end(), [&](int amount) { return amount > limit->second; }));
                std::cout << "capacity " << limit->second << " exceeded on " << exceeded << " days\n";
            }
        } else if (command == "CRASH") crash(order, std::stoi(words[1]));
        else if (command == "WHATIF") {
            Schedule after = compute(order, words[1], std::stoi(words[2]));
            std::cout << "whatif " << words[1] << ' ' << tasks.at(words[1]).duration() << " -> " << words[2]
                      << ": project " << schedule.duration << " -> " << after.duration << '\n';
            for (const auto& [name, before] : schedule.times) {
                const Timing& changed = after.times.at(name);
                if (before.es == changed.es && before.ef == changed.ef && before.tf == changed.tf) continue;
                std::cout << name;
                if (before.es != changed.es) std::cout << " ES " << before.es << "->" << changed.es;
                if (before.ef != changed.ef) std::cout << " EF " << before.ef << "->" << changed.ef;
                if (before.tf != changed.tf) std::cout << " TF " << before.tf << "->" << changed.tf;
                std::cout << '\n';
            }
            if (criticalNames(schedule) != criticalNames(after)) std::cout << "critical " << joined(criticalNames(schedule)) << " -> " << joined(criticalNames(after)) << '\n';
        } else if (command == "BASELINE") {
            Baseline saved{schedule.duration, {}};
            for (const auto& [name, time] : schedule.times) saved.times[name] = {time.es, time.ef};
            baseline = std::move(saved);
            std::cout << "baseline saved: " << tasks.size() << " tasks, duration " << schedule.duration << '\n';
        } else if (command == "VARIANCE") {
            std::cout << "variance: duration " << baseline->duration << " -> " << schedule.duration << " (" << signedNumber(schedule.duration - baseline->duration) << ")\n";
            std::set<std::string> names;
            for (const auto& [name, time] : baseline->times) names.insert(name);
            for (const auto& [name, time] : schedule.times) names.insert(name);
            bool changed = false;
            for (const std::string& name : names) {
                auto previous = baseline->times.find(name);
                auto current = schedule.times.find(name);
                if (previous == baseline->times.end()) std::cout << name << " new\n";
                else if (current == schedule.times.end()) std::cout << name << " removed\n";
                else if (current->second.es != previous->second.first || current->second.ef != previous->second.second) {
                    std::cout << name << " start " << signedNumber(current->second.es - previous->second.first)
                              << " finish " << signedNumber(current->second.ef - previous->second.second) << '\n';
                } else continue;
                changed = true;
            }
            if (!changed) std::cout << "no task changes\n";
        }
    }

public:
    void execute(const std::string& line) {
        std::istringstream input(line);
        std::vector<std::string> words;
        for (std::string word; input >> word;) words.push_back(word);
        const std::string& command = words[0];
        if (command == "TASK") {
            if (tasks.count(words[1])) fail("task " + words[1] + " already exists");
            tasks.emplace(words[1], Task{std::stoi(words[2]), words[3], std::stoi(words[4])});
            std::cout << "task " << words[1] << " added\n";
        } else if (command == "DEP" || command == "UNDEP") {
            task(words[1]);
            task(words[2]);
            std::pair<std::string, std::string> ends{words[1], words[2]};
            if (command == "DEP") {
                if (words[1] == words[2]) fail("self dependency " + words[1]);
                if (dependencies.count(ends)) fail("dependency " + words[1] + " -> " + words[2] + " already exists");
                int lag = std::stoi(words[4]);
                dependencies.emplace(ends, Dependency{words[3], lag});
                std::cout << "dependency " << words[1] << " -> " << words[2] << ' ' << words[3] << signedNumber(lag) << " added\n";
            } else {
                if (!dependencies.erase(ends)) fail("no dependency " + words[1] + " -> " + words[2]);
                std::cout << "dependency " << words[1] << " -> " << words[2] << " removed\n";
            }
        } else if (command == "REMOVE") {
            task(words[1]);
            int count = 0;
            for (auto position = dependencies.begin(); position != dependencies.end();) {
                if (position->first.first == words[1] || position->first.second == words[1]) {
                    position = dependencies.erase(position);
                    ++count;
                } else ++position;
            }
            tasks.erase(words[1]);
            std::cout << "task " << words[1] << " removed with " << count << " dependencies\n";
        } else if (command == "NOTBEFORE") {
            task(words[1]).notBefore = std::stoi(words[2]);
            std::cout << "notbefore " << words[1] << ' ' << words[2] << '\n';
        } else if (command == "CRASHCOST") {
            Task& item = task(words[1]);
            int limit = std::stoi(words[2]), cost = std::stoi(words[3]);
            if (limit >= item.base) fail("crash limit too large for " + words[1]);
            if (limit < item.used) fail("crash limit below used days for " + words[1]);
            item.crash = Crash{limit, cost};
            std::cout << "crash " << words[1] << " max " << limit << " cost " << cost << '\n';
        } else if (command == "UNCRASH") {
            Task& item = task(words[1]);
            std::cout << "uncrash " << words[1] << " restored " << item.used << " days\n";
            item.used = 0;
        } else if (command == "PERT") {
            Task& item = task(words[1]);
            int optimistic = std::stoi(words[2]), likely = std::stoi(words[3]), pessimistic = std::stoi(words[4]);
            if (optimistic > likely || likely > pessimistic) fail("invalid estimate");
            item.estimate = std::array<int, 3>{optimistic, likely, pessimistic};
            std::cout << "pert " << words[1] << " expected " << decimal(optimistic + 4 * likely + pessimistic, 6)
                      << " variance " << decimal((pessimistic - optimistic) * (pessimistic - optimistic), 36) << '\n';
        } else if (command == "CAPACITY") {
            capacities[words[1]] = std::stoi(words[2]);
            std::cout << "capacity " << words[1] << ' ' << words[2] << '\n';
        } else if (command == "START" || command == "HOLIDAY" || command == "DEADLINE") {
            int date = parseDate(words[1]);
            if (command == "HOLIDAY") {
                if (!holidays.insert(date).second) fail("duplicate holiday " + words[1]);
                std::cout << "holiday ";
            } else if (command == "START") {
                startDate = date;
                std::cout << "start ";
            } else {
                deadline = date;
                std::cout << "deadline ";
            }
            std::cout << dateText(date) << '\n';
        } else if (command == "LIST") {
            std::cout << "tasks " << tasks.size() << ", dependencies " << dependencies.size() << ", holidays " << holidays.size() << '\n';
            for (const auto& [name, item] : tasks) {
                std::vector<std::string> predecessors;
                for (const auto& [ends, link] : dependencies) {
                    if (ends.second == name) predecessors.push_back(ends.first);
                }
                std::cout << name << " duration " << item.duration() << " resource " << item.resource << " units " << item.units
                          << " preds " << (predecessors.empty() ? "none" : joined(predecessors)) << '\n';
            }
        } else if (command == "SHOW") {
            const Task& item = task(words[1]);
            std::cout << "task " << words[1] << " duration " << item.duration() << " resource " << item.resource << " units " << item.units;
            if (item.notBefore != 0) std::cout << " notbefore " << item.notBefore;
            std::cout << '\n';
            for (bool predecessor : {true, false}) {
                std::vector<std::string> links;
                for (const auto& [ends, link] : dependencies) {
                    if ((predecessor ? ends.second : ends.first) == words[1]) links.push_back((predecessor ? ends.first : ends.second) + " " + link.kind + signedNumber(link.lag));
                }
                std::cout << (predecessor ? "preds: " : "succs: ") << (links.empty() ? "none" : joined(links, ", ")) << '\n';
            }
            if (item.crash) std::cout << "crash: max " << item.crash->limit << " used " << item.used << " cost " << item.crash->cost << '\n';
            else std::cout << "crash: none\n";
            if (item.estimate) std::cout << "pert: " << (*item.estimate)[0] << ' ' << (*item.estimate)[1] << ' ' << (*item.estimate)[2] << '\n';
            else std::cout << "pert: none\n";
            auto [order, cycle] = topology();
            if (!cycle.empty()) std::cout << "schedule: unavailable\n";
            else {
                Timing time = compute(order).times.at(words[1]);
                std::cout << "schedule: ES " << time.es << " EF " << time.ef << " LS " << time.ls << " LF " << time.lf
                          << " TF " << time.tf << " FF " << time.free << (time.tf == 0 ? " critical\n" : "\n");
            }
        } else if (command == "IMPACT") {
            task(words[1]);
            std::set<std::string> reached{words[1]};
            std::vector<std::string> pending{words[1]};
            for (std::size_t i = 0; i < pending.size(); ++i) {
                for (const auto& [ends, link] : dependencies) {
                    if (ends.first == pending[i] && reached.insert(ends.second).second) pending.push_back(ends.second);
                }
            }
            reached.erase(words[1]);
            std::vector<std::string> names(reached.begin(), reached.end());
            std::cout << "impact " << words[1] << ": " << (names.empty() ? "none" : joined(names)) << '\n';
        } else analyze(words);
    }
};

int main() {
    int count;
    std::cin >> count;
    std::string line;
    std::getline(std::cin, line);
    Scheduler scheduler;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        try {
            scheduler.execute(line);
        } catch (const std::runtime_error& error) {
            std::cout << "error: " << error.what() << '\n';
        }
    }
}
