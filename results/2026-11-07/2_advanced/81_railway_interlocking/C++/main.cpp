#include "railway.hpp"
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <stdexcept>

std::vector<std::string> readLines(const std::string &path) {
    std::ifstream file(path);
    if (!file)
        throw std::runtime_error("cannot read " + path);
    std::vector<std::string> lines;
    std::string line;
    while (std::getline(file, line))
        lines.push_back(line);
    return lines;
}
std::vector<std::string> words(const std::string &text) {
    std::istringstream stream(text);
    std::vector<std::string> result;
    std::string word;
    while (stream >> word)
        result.push_back(word);
    return result;
}
std::vector<std::string> list(const std::string &text) {
    if (text == "-")
        return {};
    std::vector<std::string> result;
    std::size_t start = 0;
    for (;;) {
        std::size_t end = text.find(',', start);
        if (end == std::string::npos) {
            result.push_back(text.substr(start));
            return result;
        }
        result.push_back(text.substr(start, end - start));
        start = end + 1;
    }
}
std::string join(const std::vector<std::string> &parts, const std::string &separator) {
    std::string result;
    for (std::size_t i = 0; i < parts.size(); ++i) {
        if (i > 0)
            result += separator;
        result += parts[i];
    }
    return result;
}
std::string directionName(Direction direction) {
    return direction == Direction::Up ? "UP" : "DOWN";
}
std::string aspectName(Aspect aspect) {
    return aspect == Aspect::Red ? "RED" : aspect == Aspect::Yellow ? "YELLOW" : "GREEN";
}
std::string routeStateName(RouteState state) {
    return state == RouteState::Locked     ? "LOCKED"
           : state == RouteState::Used     ? "USED"
           : state == RouteState::Approach ? "APPROACH"
                                           : "";
}
std::string trainStateName(TrainState state) {
    return state == TrainState::Waiting   ? "WAITING"
           : state == TrainState::Running ? "RUNNING"
                                          : "EXITED";
}
struct Event {
    int time;
    std::vector<std::string> words;
};
struct Request {
    int number;
    Route *route;
    int time;
    std::string lastReason = "none";
};
struct Punctuality {
    int onTime = 0, late = 0, missing = 0, totalDelay = 0, maxDelay = 0;
};
class Simulator {
    Layout layout = readLayout();
    Interlocking interlocking = readInterlocking(layout);
    std::vector<std::unique_ptr<Train>> trains;
    std::vector<TrainRequest> planned;
    std::vector<Event> events;
    std::set<int> snapshotTimes;
    std::vector<Request> queue;
    Safety safety;
    std::vector<std::string> log, snapshots;
    int time = 0, endTime = 0, throwTime = 0, overlapTime = 0, totalRequests = 0, granted = 0,
        dropped = 0;
    void write(const std::string &text) { log.push_back(std::to_string(time) + " " + text); }
    void startThrow(Point *point, char position) {
        point->moving = true;
        point->target = position;
        point->completion = time + throwTime;
        write("MOVE " + point->name + " " + position + " until " +
              std::to_string(point->completion));
    }
    void addRequest(Route *route, const std::string &requester) {
        ++totalRequests;
        queue.push_back({totalRequests, route, time});
        ++route->requests;
        write("REQUEST q" + std::to_string(totalRequests) + " " + route->name + " " + requester);
    }
    void cancel(Route *route) {
        std::vector<Request> remaining;
        bool removed = false;
        for (const Request &request : queue) {
            if (request.route == route) {
                write("DROP q" + std::to_string(request.number) + " " + route->name);
                ++dropped;
                removed = true;
            } else
                remaining.push_back(request);
        }
        queue = std::move(remaining);
        if (removed)
            return;
        if (route->state == RouteState::Locked) {
            ++route->cancels;
            if (route->start->aspect != Aspect::Red && route->start->section->occupied()) {
                route->state = RouteState::Approach;
                route->releaseTime = time + route->approach;
                write("CANCEL " + route->name + " approach until " +
                      std::to_string(route->releaseTime));
            } else {
                interlocking.release(route);
                write("CANCEL " + route->name + " released");
            }
        } else
            write("CANCEL " + route->name +
                  (route->state == RouteState::None ? " none" : " refused"));
    }
    void event(const Event &event) {
        const std::vector<std::string> &a = event.words;
        if (a[0] == "REQUEST")
            addRequest(interlocking.names.at(a[1]), "OPERATOR");
        else if (a[0] == "CANCEL")
            cancel(interlocking.names.at(a[1]));
        else if (a[0] == "THROW") {
            Point *point = layout.pointNames.at(a[1]);
            char position = a[2][0];
            std::string result = !point->locks.empty()         ? "locked"
                                 : point->failed               ? "failed"
                                 : point->moving               ? "moving"
                                 : point->common->occupied()   ? "occupied"
                                 : point->position == position ? "none"
                                                               : "start";
            write("THROW " + point->name + " " + position + " " + result);
            if (result == "start")
                startThrow(point, position);
        } else if (a[0] == "TCFAIL" || a[0] == "TCFIX") {
            Section *section = layout.sectionNames.at(a[1]);
            section->failed = a[0] == "TCFAIL";
            write(a[0] + " " + section->name);
        } else {
            Point *point = layout.pointNames.at(a[1]);
            if (a[0] == "POINTFAIL") {
                point->failed = true;
                if (point->moving)
                    point->completion = -1;
                write("POINTFAIL " + point->name);
            } else {
                point->failed = false;
                write("POINTFIX " + point->name);
                if (point->moving) {
                    point->completion = time + throwTime;
                    write("MOVE " + point->name + " " + point->target + " until " +
                          std::to_string(point->completion));
                }
            }
        }
    }
    std::string reason(Route *route) const {
        if (route->state != RouteState::None)
            return "busy";
        for (const Route *conflict : route->conflicts)
            if (conflict->state == RouteState::Locked || conflict->state == RouteState::Approach)
                return "conflict " + conflict->name;
        for (Section *section : route->sections) {
            if (section->occupied())
                return "occupied " + section->name;
            bool locked = section->route != nullptr;
            for (const Route *overlap : section->overlaps)
                locked = locked || overlap->direction != route->direction;
            if (locked)
                return "locked " + section->name;
        }
        for (Section *section : route->overlap) {
            if (section->occupied())
                return "occupied " + section->name;
            bool locked = section->route && section->route->direction != route->direction;
            for (const Route *overlap : section->overlaps)
                locked = locked || overlap->direction != route->direction;
            if (locked)
                return "locked " + section->name;
        }
        for (const Requirement &requirement : route->requirements()) {
            Point *point = requirement.point;
            for (const PointLock &lock : point->locks)
                if (lock.position != requirement.position)
                    return "point " + point->name + " locked";
            if (!point->moving && point->position == requirement.position ||
                point->moving && point->target == requirement.position)
                continue;
            if (point->failed)
                return "point " + point->name + " failed";
            if (point->moving)
                return "point " + point->name + " moving";
            if (point->common->occupied())
                return "point " + point->name + " occupied";
        }
        return "";
    }
    void judge() {
        std::vector<Request> pending;
        for (Request &request : queue) {
            Route *route = request.route;
            std::string failure = reason(route);
            if (!failure.empty()) {
                if (failure != request.lastReason) {
                    write("WAIT q" + std::to_string(request.number) + " " + route->name + " " +
                          failure);
                    request.lastReason = failure;
                }
                pending.push_back(request);
                continue;
            }
            interlocking.lock(route);
            int wait = time - request.time;
            ++granted;
            ++route->grants;
            route->wait += wait;
            route->maxwait = std::max(route->maxwait, wait);
            write("GRANT q" + std::to_string(request.number) + " " + route->name + " wait " +
                  std::to_string(wait));
            for (const Requirement &requirement : route->requirements())
                if (!requirement.point->moving &&
                    requirement.point->position != requirement.position)
                    startThrow(requirement.point, requirement.position);
        }
        queue = std::move(pending);
    }
    int limitDistance(Train &train) const {
        if (train.crossed)
            return -1;
        PathSection head = train.headSection();
        Section *section = head.section;
        int distance = head.start + section->length - train.head;
        for (;;) {
            Signal *signal = layout.signal(section, train.direction);
            if (signal && signal->aspect == Aspect::Red)
                return distance;
            Stop *stop = train.stop();
            if (stop && stop->section == section)
                return distance;
            Endpoint next = layout.beyond(section, train.direction);
            if (next.kind == EndKind::Boundary)
                return -1;
            if (next.kind != EndKind::Section)
                return distance;
            section = next.section;
            distance += section->length;
        }
    }
    void pass(Train &train, Signal *signal) {
        Route *route = nullptr;
        for (const std::unique_ptr<Route> &candidate : interlocking.routes)
            if (candidate->start == signal && (candidate->state == RouteState::Locked ||
                                               candidate->state == RouteState::Approach)) {
                route = candidate.get();
                break;
            }
        write("PASS " + train.name + " " + signal->name + " " + aspectName(signal->aspect) + " " +
              (route ? route->name : "-"));
        ++signal->passes;
        ++train.passes;
        if (route) {
            route->state = RouteState::Used;
            ++route->uses;
        }
        safety.signalPassing(time, &train, signal);
        if (signal->aspect == Aspect::Red) {
            write("SPAD " + train.name + " " + signal->name);
            train.emergency = true;
        }
    }
    void runTrain(Train &train, std::set<Boundary *> &entered) {
        if (train.state == TrainState::Exited)
            return;
        if (train.state == TrainState::Waiting) {
            if (time < train.scheduledEntry || train.entry->section->occupied() ||
                entered.count(train.entry))
                return;
            entered.insert(train.entry);
            train.state = TrainState::Running;
            train.direction = train.entry->end == 'L' ? Direction::Up : Direction::Down;
            train.path = {{train.entry->section, 0}};
            train.head = 0;
            train.speed = train.entrySpeed;
            train.actualEntry = time;
            write("ENTER " + train.name + " " + train.entry->name);
        }
        if (train.dwelling) {
            Stop *stop = train.stop();
            if (time < stop->arrival + stop->dwell || time < stop->scheduledDeparture)
                return;
            train.dwelling = false;
            train.awaitDeparture = stop;
            ++train.nextStop;
            if (stop->turn) {
                PathSection head = train.headSection();
                int end = head.start + head.section->length;
                std::vector<PathSection> occupied = train.occupiedSections(), path;
                for (std::vector<PathSection>::const_reverse_iterator part = occupied.rbegin();
                     part != occupied.rend(); ++part)
                    path.push_back({part->section, end - (part->start + part->section->length)});
                train.path = std::move(path);
                train.head = end - (train.head - train.length);
                train.direction =
                    train.direction == Direction::Up ? Direction::Down : Direction::Up;
                write("REVERSE " + train.name + " " + stop->section->name);
            }
        }
        int oldSpeed = train.speed, newSpeed = selectSpeed(train, limitDistance(train)),
            remaining = newSpeed;
        PathSection current = train.headSection();
        while (remaining > 0) {
            if (train.crossed) {
                train.head += remaining;
                break;
            }
            int end = current.start + current.section->length;
            if (train.head + remaining <= end) {
                train.head += remaining;
                break;
            }
            remaining -= end - train.head;
            train.head = end;
            Signal *signal = layout.signal(current.section, train.direction);
            if (signal)
                pass(train, signal);
            if (train.awaitDeparture && train.awaitDeparture->section == current.section) {
                train.awaitDeparture->departure = time;
                train.awaitDeparture = nullptr;
                write("DEPART " + train.name + " " + current.section->name);
            }
            Endpoint next = layout.beyond(current.section, train.direction);
            if (next.kind == EndKind::Boundary) {
                train.crossed = true;
                train.boundaryCoordinate = end;
            } else {
                if (next.kind != EndKind::Section)
                    throw std::runtime_error("impassable movement");
                current = {next.section, end};
                train.path.push_back(current);
            }
        }
        train.speed = newSpeed;
        train.distance += newSpeed;
        train.recordedMax = std::max(train.recordedMax, newSpeed);
        if (newSpeed == 0)
            train.emergency = false;
        bool arrived = false;
        Stop *stop = train.stop();
        if (stop && newSpeed == 0) {
            PathSection head = train.headSection();
            if (head.section == stop->section && train.head == head.start + head.section->length) {
                train.dwelling = true;
                stop->arrival = time;
                arrived = true;
                write("ARRIVE " + train.name + " " + stop->section->name);
            }
        }
        if (newSpeed == 0 && !arrived) {
            ++train.standing;
            if (oldSpeed > 0)
                write("HOLD " + train.name + " " + train.headSection().section->name);
        }
        if (train.crossed && train.head - train.length >= train.boundaryCoordinate) {
            train.state = TrainState::Exited;
            train.actualExit = time;
            write("EXIT " + train.name + " " + train.exit->name);
        }
    }
    void occupancy() {
        for (const std::unique_ptr<Section> &section : layout.sections)
            section->occupants.clear();
        for (const std::unique_ptr<Train> &train : trains)
            if (train->state == TrainState::Running)
                for (const PathSection &part : train->occupiedSections())
                    part.section->occupants.push_back(train.get());
    }
    void sectionalRelease() {
        for (const std::unique_ptr<Route> &value : interlocking.routes) {
            Route *route = value.get();
            if (route->state != RouteState::Used)
                continue;
            for (Section *section : route->sections)
                if (section->route == route && section->occupied())
                    route->passed.insert(section);
            for (Section *section : route->sections) {
                if (section->route != route)
                    continue;
                if (!route->passed.count(section) || section->occupied())
                    break;
                interlocking.unlockSection(route, section);
                write("RELEASE " + route->name + " " + section->name);
            }
            bool remaining = false;
            for (Section *section : route->sections)
                remaining = remaining || section->route == route;
            if (!remaining) {
                interlocking.release(route);
                write("DONE " + route->name);
            } else if (!route->overlap.empty() && route->overlapLocked) {
                route->overlapCounter =
                    route->sections.back()->occupied() ? route->overlapCounter + 1 : 0;
                if (route->overlapCounter >= overlapTime) {
                    interlocking.unlockOverlap(route);
                    write("OVERLAP " + route->name);
                }
            }
        }
    }
    void statistics() {
        for (const std::unique_ptr<Route> &route : interlocking.routes)
            if (route->state != RouteState::None)
                ++route->lockedTicks;
        for (const std::unique_ptr<Point> &point : layout.points) {
            if (!point->locks.empty())
                ++point->lockedTicks;
            if (point->moving)
                ++point->movingTicks;
        }
        for (const std::unique_ptr<Section> &section : layout.sections) {
            if (section->occupied())
                ++section->occupiedTicks;
            if (section->route || !section->overlaps.empty())
                ++section->lockedTicks;
            section->trains.insert(section->occupants.begin(), section->occupants.end());
        }
        for (const std::unique_ptr<Signal> &signal : layout.signals)
            ++signal->ticks[static_cast<int>(signal->aspect)];
    }
    void snapshot() {
        std::vector<std::string> grid(layout.height, std::string(layout.width, ' '));
        for (const Label &label : layout.labels)
            for (std::size_t i = 0; i < label.text.size(); ++i)
                grid[label.row][label.col + i] = label.text[i];
        for (const std::unique_ptr<Section> &section : layout.sections) {
            char symbol = section->failed              ? '#'
                          : section->route             ? '='
                          : !section->overlaps.empty() ? '~'
                                                       : '-';
            for (int col = section->first; col <= section->last; ++col)
                grid[section->row][col] = symbol;
        }
        for (const std::unique_ptr<Train> &train : trains) {
            if (train->state != TrainState::Running)
                continue;
            for (const PathSection &part : train->occupiedSections()) {
                Section *section = part.section;
                int low = std::max(train->head - train->length, part.start),
                    high = std::min(train->head, part.start + section->length),
                    p = low - part.start, q = high - part.start;
                if (train->direction == Direction::Down) {
                    p = section->length - (high - part.start);
                    q = section->length - (low - part.start);
                }
                int columns = section->last - section->first + 1;
                for (int j = 0; j < columns; ++j)
                    if (p * columns < (j + 1) * section->length &&
                        q * columns > j * section->length) {
                        char &cell = grid[section->row][section->first + j];
                        cell = cell >= 'a' && cell <= 'z' || cell == '*' ? '*' : train->symbol;
                    }
            }
        }
        for (const std::unique_ptr<Buffer> &buffer : layout.buffers)
            grid[buffer->row][buffer->col] = '|';
        for (const std::unique_ptr<Point> &point : layout.points)
            grid[point->row][point->col] = point->detected() ? point->position : '?';
        for (const std::unique_ptr<Signal> &signal : layout.signals)
            grid[signal->row][signal->col] = signal->aspect == Aspect::Red      ? 'X'
                                             : signal->aspect == Aspect::Yellow ? 'Y'
                                                                                : 'G';
        snapshots.push_back("SNAPSHOT " + std::to_string(time));
        for (std::string &row : grid) {
            std::size_t end = row.find_last_not_of(' ');
            snapshots.push_back(end == std::string::npos ? "" : row.substr(0, end + 1));
        }
        for (const std::unique_ptr<Train> &train : trains) {
            if (train->state != TrainState::Running)
                continue;
            std::vector<std::string> names;
            for (const PathSection &part : train->occupiedSections())
                names.push_back(part.section->name);
            std::string line = "TRAIN " + std::string(1, train->symbol) + " " + train->name + " " +
                               directionName(train->direction) + " " + std::to_string(train->speed);
            if (!names.empty())
                line += " " + join(names, ",");
            snapshots.push_back(line);
        }
        std::vector<std::string> routes;
        for (const std::unique_ptr<Route> &route : interlocking.routes)
            if (route->state != RouteState::None)
                routes.push_back(route->name + "/" + routeStateName(route->state));
        snapshots.push_back("ROUTES " + (routes.empty() ? "-" : join(routes, " ")));
    }
    std::vector<std::string> trainLog(Punctuality &punctuality) const {
        std::vector<std::string> result = {"train,location,scheduled,actual,delay"};
        const auto append = [&](const Train &train, const std::string &location, int scheduled,
                                int actual) {
            std::string line = train.name + "," + location + "," + std::to_string(scheduled) + ",";
            if (actual < 0) {
                line += "-,-";
                ++punctuality.missing;
            } else {
                int delay = actual - scheduled;
                line += std::to_string(actual) + "," + std::to_string(delay);
                if (delay <= 0)
                    ++punctuality.onTime;
                else {
                    ++punctuality.late;
                    punctuality.totalDelay += delay;
                }
                punctuality.maxDelay = std::max(punctuality.maxDelay, delay);
            }
            result.push_back(line);
        };
        for (const std::unique_ptr<Train> &train : trains) {
            append(*train, "enter:" + train->entry->name, train->scheduledEntry,
                   train->actualEntry);
            for (const Stop &stop : train->stops) {
                append(*train, "arr:" + stop.section->name, stop.scheduledArrival, stop.arrival);
                append(*train, "dep:" + stop.section->name, stop.scheduledDeparture,
                       stop.departure);
            }
            append(*train, "exit:" + train->exit->name, train->scheduledExit, train->actualExit);
        }
        return result;
    }
    std::vector<std::string> summary(const Punctuality &punctuality) const {
        std::vector<std::string> result;
        for (const std::unique_ptr<Route> &route : interlocking.routes)
            result.push_back(
                "ROUTE " + route->name + " " + route->start->name + "-" + route->finish +
                " requests " + std::to_string(route->requests) + " grants " +
                std::to_string(route->grants) + " uses " + std::to_string(route->uses) +
                " cancels " + std::to_string(route->cancels) + " wait " +
                std::to_string(route->wait) + " maxwait " + std::to_string(route->maxwait) +
                " locked " + std::to_string(route->lockedTicks));
        for (const std::unique_ptr<Point> &point : layout.points)
            result.push_back("POINT " + point->name + " throws " + std::to_string(point->throws) +
                             " locked " + std::to_string(point->lockedTicks) + " moving " +
                             std::to_string(point->movingTicks) + " final " +
                             (point->detected() ? std::string(1, point->position) : "?"));
        for (const std::unique_ptr<Section> &section : layout.sections)
            result.push_back("SECTION " + section->name + " occupied " +
                             std::to_string(section->occupiedTicks) + " locked " +
                             std::to_string(section->lockedTicks) + " trains " +
                             std::to_string(section->trains.size()));
        for (const std::unique_ptr<Signal> &signal : layout.signals)
            result.push_back("SIGNAL " + signal->name + " red " + std::to_string(signal->ticks[0]) +
                             " yellow " + std::to_string(signal->ticks[1]) + " green " +
                             std::to_string(signal->ticks[2]) + " passes " +
                             std::to_string(signal->passes));
        std::array<int, 3> states{};
        for (const std::unique_ptr<Train> &train : trains) {
            ++states[static_cast<int>(train->state)];
            result.push_back(
                "TRAIN " + train->name + " " + train->symbol + " " + trainStateName(train->state) +
                " distance " + std::to_string(train->distance) + " maxspeed " +
                std::to_string(train->recordedMax) + " standing " +
                std::to_string(train->standing) + " passes " + std::to_string(train->passes));
        }
        result.push_back("TRAINS total " + std::to_string(trains.size()) + " exited " +
                         std::to_string(states[2]) + " running " + std::to_string(states[1]) +
                         " waiting " + std::to_string(states[0]));
        result.push_back("PUNCTUALITY on_time " + std::to_string(punctuality.onTime) + " late " +
                         std::to_string(punctuality.late) + " missing " +
                         std::to_string(punctuality.missing) + " total_delay " +
                         std::to_string(punctuality.totalDelay) + " max_delay " +
                         std::to_string(punctuality.maxDelay));
        result.push_back("REQUESTS total " + std::to_string(totalRequests) + " granted " +
                         std::to_string(granted) + " dropped " + std::to_string(dropped) +
                         " pending " + std::to_string(queue.size()));
        return result;
    }
    static void save(const std::string &name, const std::vector<std::string> &lines) {
        std::ofstream file("output/" + name);
        if (!file)
            throw std::runtime_error("cannot write " + name);
        for (const std::string &line : lines)
            file << line << '\n';
    }

  public:
    Simulator() {
        readTrains(layout, interlocking, trains, planned);
        std::vector<std::string> parameters = readLines("input/params.txt");
        endTime = std::stoi(words(parameters[0])[1]);
        throwTime = std::stoi(words(parameters[1])[1]);
        overlapTime = std::stoi(words(parameters[2])[1]);
        std::vector<std::string> times = words(parameters[3]);
        for (std::size_t i = 1; i < times.size(); ++i)
            snapshotTimes.insert(std::stoi(times[i]));
        for (const std::string &line : readLines("input/events.txt")) {
            std::vector<std::string> a = words(line);
            events.push_back({std::stoi(a[0]), std::vector<std::string>(a.begin() + 1, a.end())});
        }
    }
    void run() {
        for (time = 0; time <= endTime; ++time) {
            for (const std::unique_ptr<Point> &point : layout.points)
                if (point->moving && point->completion == time) {
                    point->position = point->target;
                    point->moving = false;
                    point->completion = -1;
                    ++point->throws;
                    write("POINT " + point->name + " " + point->position);
                }
            for (const std::unique_ptr<Route> &route : interlocking.routes)
                if (route->state == RouteState::Approach && route->releaseTime == time) {
                    interlocking.release(route.get());
                    write("TIMEOUT " + route->name);
                }
            for (const TrainRequest &request : planned)
                if (request.time == time)
                    addRequest(request.route, request.train->name);
            for (const Event &instruction : events)
                if (instruction.time == time)
                    event(instruction);
            judge();
            std::map<Signal *, Aspect> aspects = signalAspects(layout, interlocking);
            for (const std::unique_ptr<Signal> &signal : layout.signals) {
                Aspect next = aspects.at(signal.get());
                if (signal->aspect != next) {
                    signal->aspect = next;
                    write("SIGNAL " + signal->name + " " + aspectName(next));
                }
            }
            std::set<Boundary *> entered;
            for (const std::unique_ptr<Train> &train : trains)
                runTrain(*train, entered);
            occupancy();
            sectionalRelease();
            safety.check(time, layout, interlocking);
            statistics();
            if (snapshotTimes.count(time))
                snapshot();
        }
        Punctuality punctuality;
        std::vector<std::string> times = trainLog(punctuality);
        std::filesystem::create_directories("output");
        save("events.txt", log);
        save("snapshots.txt", snapshots);
        save("train_log.csv", times);
        save("safety.txt", safety.lines());
        save("summary.txt", summary(punctuality));
    }
};
int main() {
    Simulator simulator;
    simulator.run();
}
