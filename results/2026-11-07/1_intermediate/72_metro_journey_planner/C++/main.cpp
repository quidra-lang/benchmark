#include <algorithm>
#include <iomanip>
#include <iostream>
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

static int timeValue(const std::string& text) {
    return std::stoi(text.substr(0, 2)) * 60 + std::stoi(text.substr(3, 2));
}

static std::string clockTime(int value) {
    std::ostringstream result;
    result << std::setfill('0') << std::setw(2) << value / 60 << ':' << std::setw(2) << value % 60;
    return result.str();
}

[[noreturn]] static void fail(const std::string& message) {
    throw std::runtime_error(message);
}

struct Station {
    int zone;
    std::string name;
    int transfer = 0;
    bool closed = false;
};

struct Direction {
    std::vector<std::string> stops;
    std::vector<int> offsets;
};

struct Line {
    int first;
    int last;
    int headway;
    std::vector<std::string> stops;
    std::vector<int> cumulative;
    int delay = 0;
    bool suspended = false;

    int trips() const {
        return (last - first) / headway + 1;
    }

    bool contains(const std::string& station) const {
        return std::find(stops.begin(), stops.end(), station) != stops.end();
    }

    Direction direction(int reverse) const {
        if (reverse == 0) return {stops, cumulative};
        Direction result;
        for (std::size_t j = stops.size(); j-- > 0;) {
            result.stops.push_back(stops[j]);
            result.offsets.push_back(cumulative.back() - cumulative[j]);
        }
        return result;
    }

    int nextTrain(int ready, int offset) const {
        int start = first + delay + offset;
        int train = ready <= start ? 0 : (ready - start + headway - 1) / headway;
        return train < trips() ? train : -1;
    }

    int at(int train, int offset) const {
        return first + delay + train * headway + offset;
    }
};

struct Leg {
    char kind;
    std::string line;
    std::string terminal;
    std::string from;
    int departure;
    std::string to;
    int arrival;
    int stops = 0;
};

using Journey = std::vector<Leg>;

struct Label {
    int arrival;
    Journey journey;
};

using Labels = std::map<std::string, Label>;
using Stations = std::set<std::string>;
using Segment = std::pair<std::string, std::string>;

static Segment segment(const std::string& a, const std::string& b) {
    return a < b ? Segment{a, b} : Segment{b, a};
}

static bool improve(Labels& labels, const std::string& station, const Journey& journey, const Leg& leg) {
    auto found = labels.find(station);
    if (found != labels.end() && found->second.arrival <= leg.arrival) return false;
    Journey next = journey;
    next.push_back(leg);
    labels[station] = {leg.arrival, std::move(next)};
    return true;
}

static int legCount(const Journey& journey, char kind) {
    return static_cast<int>(std::count_if(journey.begin(), journey.end(), [kind](const Leg& leg) {
        return leg.kind == kind;
    }));
}

static void printJourney(const std::string& heading, int departure, const Label& label) {
    std::cout << heading << ' ' << clockTime(departure) << " -> " << clockTime(label.arrival)
              << " total " << label.arrival - departure << " rides " << legCount(label.journey, 'R')
              << " walks " << legCount(label.journey, 'W') << '\n';
    int previous = departure;
    for (const Leg& leg : label.journey) {
        if (leg.kind == 'R') {
            std::cout << "RIDE " << leg.line << " toward " << leg.terminal << ' ' << leg.from << ' '
                      << clockTime(leg.departure) << " -> " << leg.to << ' ' << clockTime(leg.arrival)
                      << " wait " << leg.departure - previous << " stops " << leg.stops << '\n';
        } else if (leg.kind == 'W') {
            std::cout << "WALK " << leg.from << ' ' << clockTime(leg.departure) << " -> " << leg.to << ' ' << clockTime(leg.arrival) << '\n';
        } else {
            std::cout << "STAY " << leg.from << ' ' << clockTime(leg.departure) << " -> " << clockTime(leg.arrival) << '\n';
        }
        previous = leg.arrival;
    }
}

class Network {
    std::map<std::string, Station> stations;
    std::map<std::string, Line> lines;
    std::map<Segment, int> walks;
    std::set<Segment> closedSegments;
    int discount = 0;
    int discountWindow = 0;
    std::vector<int> prices;

    const Station& requireStation(const std::string& name) const {
        auto found = stations.find(name);
        if (found == stations.end()) fail("unknown station " + name);
        return found->second;
    }

    const Line& requireLine(const std::string& name) const {
        auto found = lines.find(name);
        if (found == lines.end()) fail("unknown line " + name);
        return found->second;
    }

    void requireOpen(const std::string& name) const {
        if (stations.at(name).closed) fail("station " + name + " is closed");
    }

    void checkSearch(const std::string& origin, const std::string& destination) const {
        requireStation(origin);
        requireStation(destination);
        if (origin == destination) fail("origin and destination are the same");
        requireOpen(origin);
        requireOpen(destination);
    }

    bool blocked(const std::string& a, const std::string& b) const {
        return closedSegments.count(segment(a, b)) != 0;
    }

    std::map<std::string, int> neighbors(const std::string& station) const {
        std::map<std::string, int> result;
        for (const auto& [edge, duration] : walks) {
            if (edge.first == station) result[edge.second] = duration;
            else if (edge.second == station) result[edge.first] = duration;
        }
        return result;
    }

    Labels earliest(const std::string& origin, int departure) const {
        Labels labels = {{origin, {departure, {}}}};
        Stations settled;
        while (true) {
            std::string current;
            int best = 0;
            for (const auto& [name, label] : labels) {
                if (!settled.count(name) && (current.empty() || label.arrival < best)) {
                    current = name;
                    best = label.arrival;
                }
            }
            if (current.empty()) break;
            settled.insert(current);
            Label label = labels.at(current);
            int ready = label.arrival + (current == origin ? 0 : stations.at(current).transfer);
            for (const auto& [name, line] : lines) {
                if (line.suspended || !line.contains(current)) continue;
                for (int reverse = 0; reverse < 2; ++reverse) {
                    Direction direction = line.direction(reverse);
                    int board = static_cast<int>(std::find(direction.stops.begin(), direction.stops.end(), current) - direction.stops.begin());
                    if (board + 1 == static_cast<int>(direction.stops.size())) continue;
                    int train = line.nextTrain(ready, direction.offsets[board]);
                    if (train < 0) continue;
                    int boardTime = line.at(train, direction.offsets[board]);
                    for (int j = board + 1; j < static_cast<int>(direction.stops.size()); ++j) {
                        if (blocked(direction.stops[j - 1], direction.stops[j])) break;
                        const std::string& target = direction.stops[j];
                        if (stations.at(target).closed) continue;
                        Leg ride = {'R', name, direction.stops.back(), current, boardTime,
                                    target, line.at(train, direction.offsets[j]), j - board};
                        improve(labels, target, label.journey, ride);
                    }
                }
            }
            for (const auto& [target, duration] : neighbors(current)) {
                int arrival = label.arrival + duration;
                if (!stations.at(target).closed && arrival <= 1440) {
                    improve(labels, target, label.journey, {'W', "", "", current, label.arrival, target, arrival});
                }
            }
        }
        return labels;
    }

    void walkStep(Labels& labels, const Stations& sources, Stations& marked) const {
        Labels recorded;
        for (const std::string& source : sources) recorded[source] = labels.at(source);
        for (const auto& [source, label] : recorded) {
            for (const auto& [target, duration] : neighbors(source)) {
                int arrival = label.arrival + duration;
                if (!stations.at(target).closed && arrival <= 1440 &&
                    improve(labels, target, label.journey, {'W', "", "", source, label.arrival, target, arrival})) {
                    marked.insert(target);
                }
            }
        }
    }

    std::vector<Labels> rounds(const std::string& origin, int departure) const {
        Labels labels = {{origin, {departure, {}}}};
        Stations marked = {origin};
        walkStep(labels, {origin}, marked);
        std::vector<Labels> result = {labels};
        while (!marked.empty()) {
            Labels previous = labels;
            Stations previousMarked = marked;
            marked.clear();
            Stations rideUpdates;
            for (const auto& [name, line] : lines) {
                if (line.suspended) continue;
                for (int reverse = 0; reverse < 2; ++reverse) {
                    Direction direction = line.direction(reverse);
                    int train = -1;
                    int board = -1;
                    int boardTime = 0;
                    Journey boardedJourney;
                    for (int j = 0; j < static_cast<int>(direction.stops.size()); ++j) {
                        const std::string& station = direction.stops[j];
                        if (j > 0 && blocked(direction.stops[j - 1], station)) train = -1;
                        if (stations.at(station).closed) continue;
                        if (train >= 0) {
                            Leg ride = {'R', name, direction.stops.back(), direction.stops[board], boardTime,
                                        station, line.at(train, direction.offsets[j]), j - board};
                            if (improve(labels, station, boardedJourney, ride)) {
                                rideUpdates.insert(station);
                                marked.insert(station);
                            }
                        }
                        if (j + 1 < static_cast<int>(direction.stops.size()) && previousMarked.count(station)) {
                            const Label& old = previous.at(station);
                            int ready = old.arrival + (station == origin ? 0 : stations.at(station).transfer);
                            int candidate = line.nextTrain(ready, direction.offsets[j]);
                            if (candidate >= 0 && (train < 0 || candidate < train)) {
                                train = candidate;
                                board = j;
                                boardTime = line.at(train, direction.offsets[j]);
                                boardedJourney = old.journey;
                            }
                        }
                    }
                }
            }
            walkStep(labels, rideUpdates, marked);
            result.push_back(labels);
        }
        return result;
    }

    void fare(const std::string& heading, const Journey& journey, bool child) const {
        std::vector<std::string> tickets;
        int total = 0;
        int previousArrival = -1;
        for (const Leg& leg : journey) {
            if (leg.kind != 'R') continue;
            const Line& line = lines.at(leg.line);
            Direction direction = line.direction(leg.terminal == line.stops.back() ? 0 : 1);
            auto first = std::find(direction.stops.begin(), direction.stops.end(), leg.from);
            auto last = std::find(direction.stops.begin(), direction.stops.end(), leg.to);
            std::set<int> zones;
            for (auto at = first; at <= last; ++at) zones.insert(stations.at(*at).zone);
            int price = prices[std::min(zones.size(), prices.size()) - 1];
            if (child) price = (price + 19) / 20 * 10;
            int cap = child ? (discount + 19) / 20 * 10 : discount;
            int reduction = previousArrival >= 0 && leg.departure - previousArrival <= discountWindow ? std::min(cap, price) : 0;
            int payment = price - reduction;
            total += payment;
            previousArrival = leg.arrival;
            std::ostringstream ticket;
            ticket << "TICKET " << leg.line << ' ' << leg.from << ' ' << leg.to << " zones " << zones.size()
                   << " price " << price << " discount " << reduction << " pay " << payment;
            tickets.push_back(ticket.str());
        }
        std::cout << heading << " rides " << tickets.size() << " total " << total << '\n';
        for (const std::string& ticket : tickets) std::cout << ticket << '\n';
    }

    int directionTo(const std::string& name, const Line& line, const std::string& terminal) const {
        if (terminal != line.stops.front() && terminal != line.stops.back()) fail(terminal + " is not a terminal of line " + name);
        return terminal == line.stops.back() ? 0 : 1;
    }

    void departures(const std::vector<std::string>& words, bool arrivals) const {
        const std::string& station = words[1];
        requireStation(station);
        requireOpen(station);
        int time = timeValue(words[2]);
        int count = std::stoi(words[3]);
        using Event = std::tuple<int, std::string, int, std::string>;
        std::vector<Event> events;
        for (const auto& [name, line] : lines) {
            if (line.suspended || !line.contains(station)) continue;
            for (int reverse = 0; reverse < 2; ++reverse) {
                Direction direction = line.direction(reverse);
                int position = static_cast<int>(std::find(direction.stops.begin(), direction.stops.end(), station) - direction.stops.begin());
                if (arrivals ? position == 0 : position + 1 == static_cast<int>(direction.stops.size())) continue;
                int first = line.nextTrain(time, direction.offsets[position]);
                if (first < 0) continue;
                for (int train = first; train < line.trips(); ++train) {
                    events.emplace_back(line.at(train, direction.offsets[position]), name, reverse,
                                        arrivals ? direction.stops.front() : direction.stops.back());
                }
            }
        }
        std::sort(events.begin(), events.end());
        if (events.size() > static_cast<std::size_t>(count)) events.resize(count);
        std::cout << words[0] << ' ' << station << ' ' << words[2] << " count " << events.size() << '\n';
        for (const auto& [at, name, reverse, terminal] : events) {
            std::cout << clockTime(at) << ' ' << name << (arrivals ? " from " : " toward ") << terminal << '\n';
        }
    }

    void searchCommand(const std::vector<std::string>& words) const {
        const std::string& command = words[0];
        const std::string& origin = words[1];
        const std::string& destination = words[2];
        checkSearch(origin, destination);
        std::string heading = command + ' ' + origin + ' ' + destination;
        if (command == "LASTTRAIN" || command == "ARRIVEBY") {
            int deadline = command == "LASTTRAIN" ? 1440 : timeValue(words[3]);
            if (command == "ARRIVEBY") heading += " by " + words[3];
            for (int departure = deadline - 1; departure >= 0; --departure) {
                Labels labels = earliest(origin, departure);
                auto target = labels.find(destination);
                if (target != labels.end() && target->second.arrival <= deadline) {
                    printJourney(heading, departure, target->second);
                    return;
                }
            }
            std::cout << heading << " none\n";
            return;
        }
        int departure = timeValue(words[3]);
        if (command == "PROFILE") {
            int end = timeValue(words[4]);
            if (departure > end) fail("empty interval " + words[3] + ' ' + words[4]);
            std::vector<int> arrivals(end - departure + 1, -1);
            for (int time = departure; time <= end; ++time) {
                Labels labels = earliest(origin, time);
                if (labels.count(destination)) arrivals[time - departure] = labels.at(destination).arrival;
            }
            std::vector<std::pair<int, int>> selected;
            for (int time = departure; time <= end; ++time) {
                int arrival = arrivals[time - departure];
                if (arrival >= 0 && (time == end || arrivals[time - departure + 1] < 0 || arrival < arrivals[time - departure + 1])) selected.emplace_back(time, arrival);
            }
            std::cout << heading << ' ' << words[3] << ' ' << words[4] << " count " << selected.size() << '\n';
            for (const auto& [time, arrival] : selected) std::cout << clockTime(time) << " -> " << clockTime(arrival) << " total " << arrival - time << '\n';
            return;
        }
        if (command == "FEWEST" || command == "PARETO") {
            std::vector<Labels> labels = rounds(origin, departure);
            std::vector<std::pair<int, Label>> options;
            int previous = -1;
            for (std::size_t round = 0; round < labels.size(); ++round) {
                auto target = labels[round].find(destination);
                if (target != labels[round].end() && (previous < 0 || target->second.arrival < previous)) {
                    options.emplace_back(static_cast<int>(round), target->second);
                }
                if (target != labels[round].end()) previous = target->second.arrival;
            }
            if (command == "PARETO") {
                std::cout << heading << ' ' << words[3] << " options " << options.size() << '\n';
                for (const auto& [rides, label] : options) printJourney("OPTION trips " + std::to_string(rides), departure, label);
            } else if (options.empty()) std::cout << heading << ' ' << words[3] << " unreachable\n";
            else printJourney(heading + " trips " + std::to_string(options[0].first), departure, options[0].second);
            return;
        }
        if (command == "FARE") {
            if (words[4] != "ADULT" && words[4] != "CHILD") fail("unknown fare class " + words[4]);
            if (prices.empty()) fail("no tariff");
            heading += ' ' + words[3] + ' ' + words[4];
        }
        Labels labels = earliest(origin, departure);
        auto target = labels.find(destination);
        if (target == labels.end()) std::cout << heading << (command == "FARE" ? "" : " " + words[3]) << " unreachable\n";
        else if (command == "FARE") fare(heading, target->second.journey, words[4] == "CHILD");
        else printJourney(heading, departure, target->second);
    }

public:
    void execute(const std::string& text) {
        std::istringstream input(text);
        std::vector<std::string> words;
        for (std::string word; input >> word;) words.push_back(word);
        const std::string& command = words[0];
        const std::string first = words.size() > 1 ? words[1] : "";
        if (command == "STATION") {
            if (stations.count(first)) fail("station " + first + " already exists");
            stations.emplace(first, Station{std::stoi(words[2]), words[3]});
            std::cout << "STATION " << first << " zone " << words[2] << ' ' << words[3] << '\n';
        } else if (command == "LINE") {
            if (lines.count(first)) fail("line " + first + " already exists");
            Line line{timeValue(words[2]), timeValue(words[3]), std::stoi(words[4]), {}, {0}};
            for (std::size_t i = 5; i < words.size(); i += 2) {
                requireStation(words[i]);
                line.stops.push_back(words[i]);
                if (i > 5) line.cumulative.push_back(line.cumulative.back() + std::stoi(words[i - 1]));
            }
            Stations seen;
            for (const std::string& stop : line.stops) {
                if (!seen.insert(stop).second) fail("station " + stop + " appears twice on line " + first);
            }
            if (line.first > line.last) fail("line " + first + " first departure is after last departure");
            if (line.last + line.cumulative.back() > 1440) fail("line " + first + " runs past 24:00");
            lines.emplace(first, line);
            std::cout << "LINE " << first << " stops " << line.stops.size() << " time " << line.cumulative.back() << " trips " << line.trips() << '\n';
        } else if (command == "TRANSFER") {
            requireStation(first);
            stations.at(first).transfer = std::stoi(words[2]);
            std::cout << "TRANSFER " << first << ' ' << words[2] << '\n';
        } else if (command == "WALK") {
            requireStation(first);
            requireStation(words[2]);
            if (first == words[2]) fail("walk from " + first + " to itself");
            Segment edge = segment(first, words[2]);
            auto found = walks.find(edge);
            std::cout << "WALK " << first << ' ' << words[2] << ' ' << words[3];
            if (found != walks.end()) std::cout << " was " << found->second;
            std::cout << '\n';
            walks[edge] = std::stoi(words[3]);
        } else if (command == "TARIFF") {
            std::vector<int> updated;
            for (std::size_t i = 3; i < words.size(); ++i) updated.push_back(std::stoi(words[i]));
            if (!std::is_sorted(updated.begin(), updated.end())) fail("tariff prices must not decrease");
            discount = std::stoi(words[1]);
            discountWindow = std::stoi(words[2]);
            prices = updated;
            std::cout << "TARIFF zones " << prices.size() << " discount " << discount << " window " << discountWindow << '\n';
        } else if (command == "CLOSE" || command == "OPEN") {
            requireStation(first);
            bool closing = command == "CLOSE";
            if (words.size() == 2) {
                if (stations.at(first).closed == closing) fail("station " + first + (closing ? " is already closed" : " is not closed"));
                stations.at(first).closed = closing;
                std::cout << command << ' ' << first << '\n';
            } else {
                requireStation(words[2]);
                Segment edge = segment(first, words[2]);
                std::string label = first + '-' + words[2];
                std::vector<std::string> containing;
                if (closing) {
                    for (const auto& [name, line] : lines) {
                        for (std::size_t i = 1; i < line.stops.size(); ++i) {
                            if (segment(line.stops[i - 1], line.stops[i]) == edge) {
                                containing.push_back(name);
                                break;
                            }
                        }
                    }
                    if (containing.empty()) fail("no segment " + label);
                    if (closedSegments.count(edge)) fail("segment " + label + " is already closed");
                    closedSegments.insert(edge);
                } else {
                    if (!closedSegments.count(edge)) fail("segment " + label + " is not closed");
                    closedSegments.erase(edge);
                }
                std::cout << command << ' ' << label;
                if (closing) {
                    std::cout << " lines";
                    for (const std::string& name : containing) std::cout << ' ' << name;
                }
                std::cout << '\n';
            }
        } else if (command == "DELAY" || command == "SUSPEND" || command == "RESUME") {
            requireLine(first);
            Line& line = lines.at(first);
            if (command == "DELAY") {
                int delay = std::stoi(words[2]);
                if (line.last + delay + line.cumulative.back() > 1440) fail("line " + first + " runs past 24:00");
                line.delay = delay;
                std::cout << "DELAY " << first << ' ' << delay << '\n';
            } else {
                bool suspending = command == "SUSPEND";
                if (line.suspended == suspending) fail("line " + first + (suspending ? " is already suspended" : " is not suspended"));
                line.suspended = suspending;
                std::cout << command << ' ' << first << '\n';
            }
        } else if (command == "VIA") {
            requireStation(first);
            requireStation(words[2]);
            requireStation(words[3]);
            if (first == words[3]) fail("origin and destination are the same");
            if (words[2] == first || words[2] == words[3]) fail("via station " + words[2] + " must differ from origin and destination");
            requireOpen(first);
            requireOpen(words[2]);
            requireOpen(words[3]);
            int departure = timeValue(words[4]);
            std::string heading = "VIA " + first + ' ' + words[2] + ' ' + words[3];
            Labels before = earliest(first, departure);
            if (before.count(words[2])) {
                Label via = before.at(words[2]);
                int ready = via.arrival + stations.at(words[2]).transfer;
                Labels after = earliest(words[2], ready);
                if (after.count(words[3])) {
                    via.journey.push_back({'S', "", "", words[2], via.arrival, words[2], ready});
                    const Label& final = after.at(words[3]);
                    via.journey.insert(via.journey.end(), final.journey.begin(), final.journey.end());
                    via.arrival = final.arrival;
                    printJourney(heading, departure, via);
                    return;
                }
            }
            std::cout << heading << ' ' << words[4] << " unreachable\n";
        } else if (command == "ROUTE" || command == "FEWEST" || command == "PARETO" || command == "FARE" ||
                   command == "LASTTRAIN" || command == "ARRIVEBY" || command == "PROFILE") {
            searchCommand(words);
        } else if (command == "REACH") {
            requireStation(first);
            requireOpen(first);
            int departure = timeValue(words[2]);
            int limit = departure + std::stoi(words[3]);
            Labels labels = earliest(first, departure);
            std::vector<std::pair<int, std::string>> selected;
            for (const auto& [name, label] : labels) {
                if (label.arrival <= limit) selected.emplace_back(label.arrival, name);
            }
            std::sort(selected.begin(), selected.end());
            std::cout << "REACH " << first << ' ' << words[2] << ' ' << words[3] << " count " << selected.size() << '\n';
            for (const auto& [arrival, name] : selected) {
                std::cout << name << ' ' << stations.at(name).name << ' ' << clockTime(arrival) << ' ' << arrival - departure
                          << " rides " << legCount(labels.at(name).journey, 'R') << '\n';
            }
        } else if (command == "TIMETABLE") {
            requireStation(first);
            const Line& line = requireLine(words[2]);
            if (!line.contains(first)) fail("station " + first + " is not on line " + words[2]);
            Direction direction = line.direction(directionTo(words[2], line, words[3]));
            if (first == words[3]) fail("no departures from " + first + " toward " + words[3]);
            if (line.suspended) fail("line " + words[2] + " is suspended");
            requireOpen(first);
            int position = static_cast<int>(std::find(direction.stops.begin(), direction.stops.end(), first) - direction.stops.begin());
            int train = line.nextTrain(timeValue(words[4]), direction.offsets[position]);
            std::vector<int> times;
            if (train >= 0) {
                for (; train < line.trips() && times.size() < static_cast<std::size_t>(std::stoi(words[5])); ++train) times.push_back(line.at(train, direction.offsets[position]));
            }
            std::cout << "TIMETABLE " << first << ' ' << words[2] << " toward " << words[3] << ' ' << words[4] << " next " << times.size();
            for (int time : times) std::cout << ' ' << clockTime(time);
            std::cout << '\n';
        } else if (command == "DEPARTURES" || command == "ARRIVALS") {
            departures(words, command == "ARRIVALS");
        } else if (command == "TRIP") {
            const Line& line = requireLine(first);
            Direction direction = line.direction(directionTo(first, line, words[2]));
            if (line.suspended) fail("line " + first + " is suspended");
            int train = line.nextTrain(timeValue(words[3]), 0);
            std::cout << "TRIP " << first << " toward " << words[2] << ' ' << words[3];
            if (train < 0) std::cout << " none\n";
            else {
                std::cout << " trip " << train + 1 << " departs " << clockTime(line.at(train, 0)) << '\n';
                for (std::size_t j = 0; j < direction.stops.size(); ++j) {
                    const std::string& station = direction.stops[j];
                    std::cout << clockTime(line.at(train, direction.offsets[j])) << ' ' << station;
                    if (stations.at(station).closed) std::cout << " closed";
                    if (j > 0 && blocked(direction.stops[j - 1], station)) std::cout << " blocked";
                    std::cout << '\n';
                }
            }
        } else if (command == "SHOWLINE") {
            const Line& line = requireLine(first);
            std::cout << "SHOWLINE " << first << (line.suspended ? " suspended" : " running") << " first " << clockTime(line.first)
                      << " last " << clockTime(line.last) << " headway " << line.headway << " delay " << line.delay << " trips " << line.trips() << '\n';
            for (std::size_t j = 0; j < line.stops.size(); ++j) {
                const std::string& station = line.stops[j];
                std::cout << line.cumulative[j] << ' ' << station << " zone " << stations.at(station).zone;
                if (stations.at(station).closed) std::cout << " closed";
                if (j > 0 && blocked(line.stops[j - 1], station)) std::cout << " blocked";
                std::cout << '\n';
            }
        } else if (command == "INFO") {
            const Station& station = requireStation(first);
            std::cout << "INFO " << first << ' ' << station.name << " zone " << station.zone << " transfer " << station.transfer << (station.closed ? " closed\n" : " open\n");
            bool any = false;
            std::cout << "LINES";
            for (const auto& [name, line] : lines) {
                if (line.contains(first)) {
                    std::cout << ' ' << name;
                    any = true;
                }
            }
            if (!any) std::cout << " none";
            std::cout << "\nWALKS";
            std::map<std::string, int> linked = neighbors(first);
            if (linked.empty()) std::cout << " none";
            for (const auto& [name, duration] : linked) std::cout << ' ' << name << ' ' << duration;
            std::cout << '\n';
        } else if (command == "STATUS") {
            std::cout << "STATUS stations " << stations.size() << " lines " << lines.size() << " walks " << walks.size() << '\n';
            for (const auto& [name, station] : stations) {
                if (station.closed) std::cout << "CLOSED " << name << '\n';
            }
            for (const auto& [a, b] : closedSegments) std::cout << "CLOSED " << a << '-' << b << '\n';
            for (const auto& [name, line] : lines) {
                if (line.suspended) std::cout << "SUSPENDED " << name << '\n';
            }
            for (const auto& [name, line] : lines) {
                if (line.delay != 0) std::cout << "DELAYED " << name << ' ' << line.delay << '\n';
            }
        }
    }
};

int main() {
    int count;
    std::cin >> count;
    std::string line;
    std::getline(std::cin, line);
    Network network;
    while (count-- > 0 && std::getline(std::cin, line)) {
        try {
            network.execute(line);
        } catch (const std::runtime_error& error) {
            std::cout << "ERROR " << error.what() << '\n';
        }
    }
}
