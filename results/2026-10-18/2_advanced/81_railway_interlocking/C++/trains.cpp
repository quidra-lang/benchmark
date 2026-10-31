#include "railway.hpp"
#include <algorithm>

void readTrains(Layout &layout, Interlocking &interlocking,
                std::vector<std::unique_ptr<Train>> &trains, std::vector<TrainRequest> &requests) {
    std::map<std::string, Train *> names;
    for (const std::string &line : readLines("input/trains.txt")) {
        std::vector<std::string> a = words(line);
        if (a[0] == "TRAIN") {
            std::unique_ptr<Train> value = std::make_unique<Train>();
            Train *t = value.get();
            t->name = a[1];
            t->symbol = char('a' + trains.size());
            t->length = std::stoi(a[2]);
            t->acceleration = std::stoi(a[3]);
            t->deceleration = std::stoi(a[4]);
            t->maxSpeed = std::stoi(a[5]);
            t->entry = layout.boundaryNames.at(a[6]);
            t->scheduledEntry = std::stoi(a[7]);
            t->entrySpeed = std::stoi(a[8]);
            names[t->name] = t;
            trains.push_back(std::move(value));
            continue;
        }
        Train *train = names.at(a[1]);
        if (a[0] == "REQUEST")
            requests.push_back({train, interlocking.names.at(a[2]), std::stoi(a[3])});
        else if (a[0] == "EXIT") {
            train->exit = layout.boundaryNames.at(a[2]);
            train->scheduledExit = std::stoi(a[3]);
        } else {
            Stop stop;
            stop.turn = a[0] == "TURN";
            stop.section = layout.sectionNames.at(a[2]);
            stop.dwell = std::stoi(a[3]);
            stop.scheduledArrival = std::stoi(a[4]);
            stop.scheduledDeparture = std::stoi(a[5]);
            train->stops.push_back(stop);
        }
    }
}
int brakingDistance(int speed, int deceleration) {
    int n = speed / deceleration;
    return n * speed - deceleration * n * (n + 1) / 2;
}
int selectSpeed(const Train &train, int distance) {
    int low = std::max(train.speed - train.deceleration, 0);
    if (train.emergency)
        return low;
    for (int speed = std::min(train.speed + train.acceleration, train.maxSpeed); speed >= low;
         --speed)
        if (distance < 0 || speed + brakingDistance(speed, train.deceleration) <= distance)
            return speed;
    return low;
}
PathSection Train::headSection() const {
    PathSection result = path.front();
    for (const PathSection &part : path)
        if (part.start < head)
            result = part;
    return result;
}
std::vector<PathSection> Train::occupiedSections() const {
    std::vector<PathSection> result;
    for (const PathSection &part : path)
        if (part.start < head && part.start + part.section->length > head - length)
            result.push_back(part);
    return result;
}
Stop *Train::stop() { return nextStop < int(stops.size()) ? &stops[nextStop] : nullptr; }
