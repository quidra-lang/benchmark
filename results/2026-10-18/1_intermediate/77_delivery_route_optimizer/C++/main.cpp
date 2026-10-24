#include <algorithm>
#include <cstddef>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <optional>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using Route = std::vector<int>;

[[noreturn]] static void fail(const std::string& message) { throw std::runtime_error(message); }

static int parseTime(const std::string& text) { return std::stoi(text.substr(0, 2)) * 60 + std::stoi(text.substr(3)); }

static std::string timeText(int minutes) {
    std::ostringstream text;
    text << std::setfill('0') << std::setw(2) << minutes / 60 << ':' << std::setw(2) << minutes % 60;
    return text.str();
}

static std::string name(int location) { return location == 0 ? "D" : std::to_string(location); }

static std::string sequence(const Route& route) {
    std::string text = "D";
    for (int stop : route) text += '-' + std::to_string(stop);
    return text + "-D";
}

struct Stop {
    int x;
    int y;
    int demand;
    int service;
    std::optional<std::pair<int, int>> window;
};

struct Plan {
    int capacity;
    std::vector<Route> routes;

    void normalize() {
        routes.erase(std::remove_if(routes.begin(), routes.end(), [](const Route& route) { return route.empty(); }), routes.end());
        for (Route& route : routes) {
            if (route.front() > route.back()) std::reverse(route.begin(), route.end());
        }
        std::sort(routes.begin(), routes.end(), [](const Route& a, const Route& b) {
            return *std::min_element(a.begin(), a.end()) < *std::min_element(b.begin(), b.end());
        });
    }
};

struct Run {
    int returned;
    int travel;
    int wait;
    int service;
    int violations;
    int lateness;
};

class Optimizer {
    std::optional<std::pair<int, int>> depot;
    int departure = 480;
    std::map<int, Stop> stops;
    std::optional<Route> tour;
    std::optional<Plan> plan;

    int distance(int a, int b) const {
        std::pair<int, int> first = a == 0 ? *depot : std::make_pair(stops.at(a).x, stops.at(a).y);
        std::pair<int, int> second = b == 0 ? *depot : std::make_pair(stops.at(b).x, stops.at(b).y);
        return std::abs(first.first - second.first) + std::abs(first.second - second.second);
    }

    static int at(const Route& route, int position) {
        return position < 0 || position >= static_cast<int>(route.size()) ? 0 : route[position];
    }

    int length(const Route& route) const {
        int total = 0, previous = 0;
        for (int stop : route) {
            total += distance(previous, stop);
            previous = stop;
        }
        return total + distance(previous, 0);
    }

    int load(const Route& route) const {
        int total = 0;
        for (int stop : route) total += stops.at(stop).demand;
        return total;
    }

    int planLength() const {
        int total = 0;
        for (const Route& route : plan->routes) total += length(route);
        return total;
    }

    Route numbers() const {
        Route result;
        for (const auto& [number, stop] : stops) result.push_back(number);
        return result;
    }

    void requireStops() const {
        if (!depot) fail("no depot");
        if (stops.empty()) fail("no stops");
    }

    void requireTour() const { if (!tour) fail("no tour"); }
    void requirePlan() const { if (!plan) fail("no plan"); }

    void checkCapacity(int capacity) const {
        for (const auto& [number, stop] : stops) {
            if (stop.demand > capacity) fail("stop " + std::to_string(number) + " demand " + std::to_string(stop.demand) + " exceeds capacity " + std::to_string(capacity));
        }
    }

    void routeLines() const {
        for (std::size_t i = 0; i < plan->routes.size(); ++i) {
            const Route& route = plan->routes[i];
            std::cout << "route " << i + 1 << ": " << sequence(route) << " load " << load(route) << " length " << length(route) << '\n';
        }
    }

    Run simulate(const Route& route, bool output = false) const {
        Run run{departure, length(route), 0, 0, 0, 0};
        int previous = 0;
        for (int number : route) {
            const Stop& stop = stops.at(number);
            int arrival = run.returned + distance(previous, number);
            int wait = stop.window ? std::max(0, stop.window->first - arrival) : 0;
            int late = stop.window ? std::max(0, arrival - stop.window->second) : 0;
            int begin = arrival + wait;
            run.returned = begin + stop.service;
            run.wait += wait;
            run.service += stop.service;
            run.violations += late > 0;
            run.lateness += late;
            if (output) {
                std::cout << number << " arrive " << timeText(arrival) << " wait " << wait << " begin " << timeText(begin)
                          << " leave " << timeText(run.returned) << (late > 0 ? " late " + std::to_string(late) : " ok") << '\n';
            }
            previous = number;
        }
        run.returned += distance(previous, 0);
        if (output) std::cout << "return " << timeText(run.returned) << ", travel " << run.travel << ", wait " << run.wait
                             << ", service " << run.service << ", violations " << run.violations << ", lateness " << run.lateness << '\n';
        return run;
    }

    void construct(const std::string& command) {
        requireStops();
        if (command == "EXACT" && stops.size() > 10) fail("too many stops for exact (" + std::to_string(stops.size()) + ')');
        Route route, remaining = numbers();
        if (command == "EXACT") {
            int best = std::numeric_limits<int>::max();
            do {
                int total = length(remaining);
                if (total < best) {
                    best = total;
                    route = remaining;
                }
            } while (std::next_permutation(remaining.begin(), remaining.end()));
        } else while (!remaining.empty()) {
            int best = std::numeric_limits<int>::max();
            std::size_t selected = 0, position = 0;
            for (std::size_t i = 0; i < remaining.size(); ++i) {
                int stop = remaining[i];
                if (command == "NEAREST") {
                    int cost = distance(route.empty() ? 0 : route.back(), stop);
                    if (cost < best) {
                        best = cost;
                        selected = i;
                        position = route.size();
                    }
                } else {
                    for (std::size_t j = 0; j <= route.size(); ++j) {
                        int before = at(route, static_cast<int>(j) - 1), after = at(route, static_cast<int>(j));
                        int cost = distance(before, stop) + distance(stop, after) - distance(before, after);
                        if (cost < best) {
                            best = cost;
                            selected = i;
                            position = j;
                        }
                    }
                }
            }
            route.insert(route.begin() + static_cast<std::ptrdiff_t>(position), remaining[selected]);
            remaining.erase(remaining.begin() + static_cast<std::ptrdiff_t>(selected));
        }
        tour = route;
        std::string label = command == "NEAREST" ? "nearest" : (command == "INSERTION" ? "insertion" : "exact");
        std::cout << label << ": " << sequence(route) << " length " << length(route) << '\n';
    }

    int twoOpt(Route& route, bool output) const {
        int moves = 0;
        while (true) {
            bool improved = false;
            for (int i = 0; i + 1 < static_cast<int>(route.size()) && !improved; ++i) {
                for (int j = i + 1; j < static_cast<int>(route.size()); ++j) {
                    int gain = distance(at(route, i - 1), route[i]) + distance(route[j], at(route, j + 1))
                             - distance(at(route, i - 1), route[j]) - distance(route[i], at(route, j + 1));
                    if (gain <= 0) continue;
                    if (output) std::cout << "reverse " << route[i] << ".." << route[j] << " gain " << gain << '\n';
                    std::reverse(route.begin() + i, route.begin() + j + 1);
                    ++moves;
                    improved = true;
                    break;
                }
            }
            if (!improved) return moves;
        }
    }

    void improveTour(const std::string& command) {
        requireTour();
        int before = length(*tour), moves = 0;
        if (command == "TWOOPT") moves = twoOpt(*tour, true);
        else while (true) {
            bool improved = false;
            Route& route = *tour;
            int size = static_cast<int>(route.size());
            if (command == "SWAP") {
                int oldLength = length(route);
                for (int i = 0; i + 1 < size && !improved; ++i) {
                    for (int j = i + 1; j < size; ++j) {
                        Route changed = route;
                        std::swap(changed[i], changed[j]);
                        int gain = oldLength - length(changed);
                        if (gain <= 0) continue;
                        std::cout << "swap " << route[i] << " and " << route[j] << " gain " << gain << '\n';
                        route = std::move(changed);
                        improved = true;
                        break;
                    }
                }
            } else {
                for (int count = 1; count <= 3 && !improved; ++count) {
                    for (int i = 0; i + count <= size && !improved; ++i) {
                        Route segment(route.begin() + i, route.begin() + i + count), remainder = route;
                        remainder.erase(remainder.begin() + i, remainder.begin() + i + count);
                        int removal = distance(at(route, i - 1), segment.front()) + distance(segment.back(), at(route, i + count))
                                    - distance(at(route, i - 1), at(route, i + count));
                        for (int j = 0; j <= static_cast<int>(remainder.size()); ++j) {
                            if (j == i) continue;
                            int a = at(remainder, j - 1), b = at(remainder, j);
                            int gain = removal - distance(a, segment.front()) - distance(segment.back(), b) + distance(a, b);
                            if (gain <= 0) continue;
                            std::cout << "move ";
                            for (std::size_t k = 0; k < segment.size(); ++k) std::cout << (k ? "-" : "") << segment[k];
                            std::cout << " after " << name(a) << " gain " << gain << '\n';
                            remainder.insert(remainder.begin() + j, segment.begin(), segment.end());
                            route = std::move(remainder);
                            improved = true;
                            break;
                        }
                    }
                }
            }
            if (!improved) break;
            ++moves;
        }
        std::string label = command == "TWOOPT" ? "twoopt" : (command == "OROPT" ? "oropt" : "swap");
        std::cout << label << ": moves " << moves << ", length " << before << " -> " << length(*tour) << '\n';
    }

    std::pair<int, std::vector<std::string>> mst(Route tree, Route remaining) const {
        int total = 0;
        std::vector<std::string> edges;
        while (!remaining.empty()) {
            int best = std::numeric_limits<int>::max();
            std::size_t child = 0, parent = 0;
            for (std::size_t c = 0; c < remaining.size(); ++c) {
                for (std::size_t p = 0; p < tree.size(); ++p) {
                    int cost = distance(tree[p], remaining[c]);
                    if (cost < best) {
                        best = cost;
                        child = c;
                        parent = p;
                    }
                }
            }
            total += best;
            edges.push_back(name(tree[parent]) + '-' + name(remaining[child]));
            tree.push_back(remaining[child]);
            remaining.erase(remaining.begin() + static_cast<std::ptrdiff_t>(child));
        }
        return {total, edges};
    }

    void bound() const {
        requireStops();
        Route all = numbers();
        auto [minimum, edges] = mst({0}, all);
        std::cout << "mst:";
        for (const std::string& edge : edges) std::cout << ' ' << edge;
        std::cout << " (length " << minimum << ")\n";
        int oneTree = 2 * distance(0, all[0]);
        if (all.size() >= 2) {
            Route remaining(all.begin() + 1, all.end());
            oneTree = mst({all[0]}, remaining).first;
            std::vector<int> distances;
            for (int stop : all) distances.push_back(distance(0, stop));
            std::sort(distances.begin(), distances.end());
            oneTree += distances[0] + distances[1];
        }
        int best = std::max(minimum, oneTree);
        std::cout << "bound: mst " << minimum << ", one-tree " << oneTree << ", best " << best << '\n';
        if (!tour) std::cout << "gap: no tour\n";
        else {
            int total = length(*tour), tenths = best > 0 ? (2000 * (total - best) + best) / (2 * best) : 0;
            std::cout << "gap: tour " << total << ", " << tenths / 10 << '.' << tenths % 10 << "%\n";
        }
    }

    void constructPlan(const std::vector<std::string>& words) {
        const std::string& command = words[0];
        if (command == "SPLIT") requireTour();
        else requireStops();
        int capacity = std::stoi(words[1]);
        checkCapacity(capacity);
        std::optional<int> limit;
        if (words.size() == 3) {
            limit = std::stoi(words[2]);
            for (const auto& [number, stop] : stops) {
                if (2 * distance(0, number) > *limit) fail("stop " + std::to_string(number) + " too far for limit " + words[2]);
            }
        }
        Plan result{capacity, {}};
        int merges = 0;
        if (command == "VRP") {
            Route all = numbers();
            for (int number : all) result.routes.push_back({number});
            std::vector<std::tuple<int, int, int>> pairs;
            for (std::size_t i = 0; i < all.size(); ++i) {
                for (std::size_t j = i + 1; j < all.size(); ++j) {
                    int saving = distance(0, all[i]) + distance(0, all[j]) - distance(all[i], all[j]);
                    if (saving > 0) pairs.emplace_back(-saving, all[i], all[j]);
                }
            }
            std::sort(pairs.begin(), pairs.end());
            for (auto [saving, first, second] : pairs) {
                std::size_t a = 0, b = 0;
                for (std::size_t i = 0; i < result.routes.size(); ++i) {
                    if (std::find(result.routes[i].begin(), result.routes[i].end(), first) != result.routes[i].end()) a = i;
                    if (std::find(result.routes[i].begin(), result.routes[i].end(), second) != result.routes[i].end()) b = i;
                }
                if (a == b) continue;
                Route left = result.routes[a], right = result.routes[b];
                if ((left.front() != first && left.back() != first) || (right.front() != second && right.back() != second)) continue;
                if (load(left) + load(right) > capacity) continue;
                if (left.front() == first) std::reverse(left.begin(), left.end());
                if (right.back() == second) std::reverse(right.begin(), right.end());
                left.insert(left.end(), right.begin(), right.end());
                if (limit && length(left) > *limit) continue;
                result.routes[a] = std::move(left);
                result.routes.erase(result.routes.begin() + static_cast<std::ptrdiff_t>(b));
                ++merges;
            }
        } else if (command == "SPLIT") {
            int size = static_cast<int>(tour->size());
            std::vector<int> values(size + 1, 0), previous(size + 1, 0);
            for (int j = 1; j <= size; ++j) {
                values[j] = std::numeric_limits<int>::max();
                for (int i = 0; i < j; ++i) {
                    Route segment(tour->begin() + i, tour->begin() + j);
                    if (load(segment) > capacity) continue;
                    int cost = values[i] + length(segment);
                    if (cost < values[j]) {
                        values[j] = cost;
                        previous[j] = i;
                    }
                }
            }
            for (int j = size; j > 0; j = previous[j]) result.routes.emplace_back(tour->begin() + previous[j], tour->begin() + j);
        } else {
            Route all = numbers();
            std::sort(all.begin(), all.end(), [&](int a, int b) {
                int ax = stops.at(a).x - depot->first, ay = stops.at(a).y - depot->second;
                int bx = stops.at(b).x - depot->first, by = stops.at(b).y - depot->second;
                bool zeroA = ax == 0 && ay == 0, zeroB = bx == 0 && by == 0;
                if (zeroA != zeroB) return zeroA;
                if (zeroA) return a < b;
                int halfA = ay > 0 || (ay == 0 && ax > 0) ? 0 : 1;
                int halfB = by > 0 || (by == 0 && bx > 0) ? 0 : 1;
                if (halfA != halfB) return halfA < halfB;
                int cross = ax * by - ay * bx;
                if (cross != 0) return cross > 0;
                return std::make_pair(distance(0, a), a) < std::make_pair(distance(0, b), b);
            });
            result.routes.push_back({});
            for (int number : all) {
                if (load(result.routes.back()) + stops.at(number).demand > capacity) result.routes.push_back({});
                result.routes.back().push_back(number);
            }
        }
        result.normalize();
        plan = std::move(result);
        std::cout << (command == "VRP" ? "vrp" : (command == "SPLIT" ? "split" : "sweep")) << ": capacity " << capacity;
        if (command == "VRP") std::cout << ", merges " << merges;
        std::cout << ", routes " << plan->routes.size() << ", length " << planLength() << '\n';
        routeLines();
    }

    void improvePlan(const std::string& command) {
        requirePlan();
        int before = planLength(), oldCount = static_cast<int>(plan->routes.size()), moves = 0;
        while (true) {
            bool improved = false;
            auto& routes = plan->routes;
            int size = static_cast<int>(routes.size());
            if (command == "RELOCATE") {
                for (int r = 0; r < size && !improved; ++r) {
                    for (int p = 0; p < static_cast<int>(routes[r].size()) && !improved; ++p) {
                        int stop = routes[r][p];
                        int removal = distance(at(routes[r], p - 1), stop) + distance(stop, at(routes[r], p + 1)) - distance(at(routes[r], p - 1), at(routes[r], p + 1));
                        for (int t = 0; t < size && !improved; ++t) {
                            if (r == t || load(routes[t]) + stops.at(stop).demand > plan->capacity) continue;
                            for (int j = 0; j <= static_cast<int>(routes[t].size()); ++j) {
                                int a = at(routes[t], j - 1), b = at(routes[t], j);
                                int gain = removal - distance(a, stop) - distance(stop, b) + distance(a, b);
                                if (gain <= 0) continue;
                                std::cout << "relocate " << stop << " from route " << r + 1 << " to route " << t + 1 << " after " << name(a) << " gain " << gain << '\n';
                                routes[r].erase(routes[r].begin() + p);
                                routes[t].insert(routes[t].begin() + j, stop);
                                improved = true;
                                break;
                            }
                        }
                    }
                }
            } else {
                for (int r = 0; r < size && !improved; ++r) {
                    for (int t = r + 1; t < size && !improved; ++t) {
                        int a = static_cast<int>(routes[r].size()), b = static_cast<int>(routes[t].size());
                        for (int i = 0; i < a + (command == "CROSS" ? 1 : 0) && !improved; ++i) {
                            for (int j = 0; j < b + (command == "CROSS" ? 1 : 0); ++j) {
                                Route left, right;
                                int gain;
                                if (command == "EXCHANGE") {
                                    left = routes[r];
                                    right = routes[t];
                                    std::swap(left[i], right[j]);
                                    if (load(left) > plan->capacity || load(right) > plan->capacity) continue;
                                    gain = length(routes[r]) + length(routes[t]) - length(left) - length(right);
                                } else {
                                    left.assign(routes[r].begin(), routes[r].begin() + i);
                                    left.insert(left.end(), routes[t].begin() + j, routes[t].end());
                                    right.assign(routes[t].begin(), routes[t].begin() + j);
                                    right.insert(right.end(), routes[r].begin() + i, routes[r].end());
                                    if (load(left) > plan->capacity || load(right) > plan->capacity) continue;
                                    gain = distance(at(routes[r], i - 1), at(routes[r], i)) + distance(at(routes[t], j - 1), at(routes[t], j))
                                         - distance(at(routes[r], i - 1), at(routes[t], j)) - distance(at(routes[t], j - 1), at(routes[r], i));
                                }
                                if (gain <= 0) continue;
                                if (command == "EXCHANGE") std::cout << "exchange " << routes[r][i] << " (route " << r + 1 << ") with " << routes[t][j] << " (route " << t + 1 << ") gain " << gain << '\n';
                                else std::cout << "cross route " << r + 1 << " after " << name(at(routes[r], i - 1)) << " with route " << t + 1 << " after " << name(at(routes[t], j - 1)) << " gain " << gain << '\n';
                                routes[r] = std::move(left);
                                routes[t] = std::move(right);
                                improved = true;
                                break;
                            }
                        }
                    }
                }
            }
            if (!improved) break;
            ++moves;
            plan->normalize();
        }
        std::string label = command == "RELOCATE" ? "relocate" : (command == "EXCHANGE" ? "exchange" : "cross");
        std::cout << label << ": moves " << moves;
        if (command != "EXCHANGE") std::cout << ", routes " << oldCount << " -> " << plan->routes.size();
        std::cout << ", length " << before << " -> " << planLength() << '\n';
    }

public:
    void execute(const std::string& line) {
        std::istringstream input(line);
        std::vector<std::string> words;
        for (std::string word; input >> word;) words.push_back(word);
        const std::string& command = words[0];
        if (command == "DEPOT") {
            depot = std::make_pair(std::stoi(words[1]), std::stoi(words[2]));
            std::cout << "depot at (" << depot->first << ',' << depot->second << ")\n";
        } else if (command == "START") {
            departure = parseTime(words[1]);
            std::cout << "start " << timeText(departure) << '\n';
        } else if (command == "STOP") {
            int number = std::stoi(words[1]);
            if (stops.count(number)) fail("stop " + words[1] + " already exists");
            Stop stop{std::stoi(words[2]), std::stoi(words[3]), std::stoi(words[4]), std::stoi(words[5]), std::nullopt};
            if (words.size() == 8) {
                int opening = parseTime(words[6]), closing = parseTime(words[7]);
                if (opening > closing) fail("invalid window");
                stop.window = std::make_pair(opening, closing);
            }
            stops.emplace(number, stop);
            tour.reset();
            plan.reset();
            std::cout << "stop " << number << " added\n";
        } else if (command == "REMOVE") {
            int number = std::stoi(words[1]);
            if (!stops.erase(number)) fail("unknown stop " + words[1]);
            if (stops.empty()) {
                tour.reset();
                plan.reset();
            }
            else {
                if (tour) tour->erase(std::remove(tour->begin(), tour->end(), number), tour->end());
                if (plan) {
                    for (Route& route : plan->routes) route.erase(std::remove(route.begin(), route.end(), number), route.end());
                    plan->normalize();
                }
            }
            std::cout << "stop " << number << " removed\n";
        } else if (command == "LIST") {
            if (depot) std::cout << "depot (" << depot->first << ',' << depot->second << ")\n";
            else std::cout << "depot none\n";
            std::cout << "start " << timeText(departure) << "\nstops " << stops.size() << '\n';
            for (const auto& [number, stop] : stops) {
                std::cout << number << " at (" << stop.x << ',' << stop.y << ") demand " << stop.demand << " service " << stop.service
                          << " window " << (stop.window ? timeText(stop.window->first) + '-' + timeText(stop.window->second) : "none") << '\n';
            }
        } else if (command == "MATRIX") {
            if (!depot) fail("no depot");
            Route locations = numbers();
            locations.insert(locations.begin(), 0);
            std::size_t width = 1;
            for (int a : locations) {
                width = std::max(width, name(a).size());
                for (int b : locations) width = std::max(width, std::to_string(distance(a, b)).size());
            }
            std::cout << std::string(width, ' ');
            for (int location : locations) std::cout << ' ' << std::setw(static_cast<int>(width)) << name(location);
            std::cout << '\n';
            for (int a : locations) {
                std::cout << std::setw(static_cast<int>(width)) << name(a);
                for (int b : locations) std::cout << ' ' << std::setw(static_cast<int>(width)) << distance(a, b);
                std::cout << '\n';
            }
        } else if (command == "ORDER") {
            requireStops();
            Route route;
            for (std::size_t i = 1; i < words.size(); ++i) {
                int number = std::stoi(words[i]);
                if (!stops.count(number)) fail("unknown stop " + words[i]);
                route.push_back(number);
            }
            std::set<int> seen;
            for (int number : route) {
                if (!seen.insert(number).second) fail("duplicate stop " + std::to_string(number));
            }
            if (route.size() != stops.size()) fail("order has " + std::to_string(route.size()) + " stops, expected " + std::to_string(stops.size()));
            tour = route;
            std::cout << "order: " << sequence(route) << " length " << length(route) << '\n';
        } else if (command == "NEAREST" || command == "INSERTION" || command == "EXACT") construct(command);
        else if (command == "TOUR") {
            requireTour();
            std::cout << "tour: " << sequence(*tour) << " length " << length(*tour) << '\n';
        } else if (command == "TWOOPT" || command == "OROPT" || command == "SWAP") improveTour(command);
        else if (command == "TIMECHECK") {
            const Route* route;
            if (words.size() == 1) {
                requireTour();
                route = &*tour;
                std::cout << "timecheck tour depart " << timeText(departure) << '\n';
            } else {
                requirePlan();
                int number = std::stoi(words[1]);
                if (number > static_cast<int>(plan->routes.size())) fail("no route " + words[1]);
                route = &plan->routes[number - 1];
                std::cout << "timecheck route " << number << " depart " << timeText(departure) << '\n';
            }
            simulate(*route, true);
        } else if (command == "BOUND") bound();
        else if (command == "VRP" || command == "SPLIT" || command == "SWEEP") constructPlan(words);
        else if (command == "ROUTES") {
            requirePlan();
            std::cout << "plan: capacity " << plan->capacity << ", routes " << plan->routes.size() << ", length " << planLength() << '\n';
            routeLines();
        } else if (command == "RELOCATE" || command == "EXCHANGE" || command == "CROSS") improvePlan(command);
        else if (command == "ROUTEOPT") {
            requirePlan();
            int before = planLength();
            for (std::size_t i = 0; i < plan->routes.size(); ++i) {
                int oldLength = length(plan->routes[i]);
                int moves = twoOpt(plan->routes[i], false);
                std::cout << "route " << i + 1 << ": moves " << moves << ", length " << oldLength << " -> " << length(plan->routes[i]) << '\n';
            }
            plan->normalize();
            std::cout << "routeopt: length " << before << " -> " << planLength() << '\n';
        } else if (command == "REPORT") {
            int demand = 0, service = 0, windows = 0;
            for (const auto& [number, stop] : stops) {
                demand += stop.demand;
                service += stop.service;
                windows += stop.window.has_value();
            }
            std::cout << "report: stops " << stops.size() << ", demand " << demand << ", service " << service << ", windows " << windows << '\n';
            if (!tour) std::cout << "tour: none\n";
            else {
                Run run = simulate(*tour);
                std::cout << "tour: length " << run.travel << ", return " << timeText(run.returned) << ", violations " << run.violations << ", lateness " << run.lateness << '\n';
            }
            if (!plan) std::cout << "plan: none\n";
            else {
                int returned = departure, violations = 0, lateness = 0;
                for (const Route& route : plan->routes) {
                    Run run = simulate(route);
                    returned = std::max(returned, run.returned);
                    violations += run.violations;
                    lateness += run.lateness;
                }
                int denominator = static_cast<int>(plan->routes.size()) * plan->capacity;
                int utilization = (2000 * demand + denominator) / (2 * denominator);
                std::cout << "plan: capacity " << plan->capacity << ", routes " << plan->routes.size() << ", length " << planLength()
                          << ", utilization " << utilization / 10 << '.' << utilization % 10 << "%, return " << timeText(returned)
                          << ", violations " << violations << ", lateness " << lateness << '\n';
            }
        }
    }
};

int main() {
    int count;
    std::cin >> count;
    std::string line;
    std::getline(std::cin, line);
    Optimizer optimizer;
    for (int i = 0; i < count; ++i) {
        std::getline(std::cin, line);
        try {
            optimizer.execute(line);
        }
        catch (const std::runtime_error& error) {
            std::cout << "error: " << error.what() << '\n';
        }
    }
}
