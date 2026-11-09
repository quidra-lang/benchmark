#pragma once
#include <array>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <utility>
#include <vector>

enum class Direction { Up, Down };
enum class Aspect { Red, Yellow, Green };
enum class RouteState { None, Locked, Used, Approach };
enum class TrainState { Waiting, Running, Exited };
enum class EndKind { Section, Point, Buffer, Boundary, Impassable };
struct Route;
struct Train;
struct Point;
struct Section {
    std::string name;
    int length = 0, row = 0, first = 0, last = 0;
    bool failed = false;
    std::vector<Train *> occupants;
    Route *route = nullptr;
    std::set<Route *> overlaps;
    int occupiedTicks = 0, lockedTicks = 0;
    std::set<Train *> trains;
    bool occupied() const { return failed || !occupants.empty(); }
};
struct PointLock {
    Route *route;
    char position;
};
struct Point {
    std::string name;
    char side = 'R';
    Section *common = nullptr, *normal = nullptr, *reverse = nullptr;
    int row = 0, col = 0;
    char position = 'N', target = 'N';
    bool moving = false, failed = false;
    int completion = -1, throws = 0, lockedTicks = 0, movingTicks = 0;
    std::vector<PointLock> locks;
    bool detected() const { return !moving && !failed; }
};
struct Signal {
    std::string name;
    Section *section = nullptr;
    Direction direction = Direction::Up;
    int row = 0, col = 0;
    Aspect aspect = Aspect::Red;
    std::array<int, 3> ticks{};
    int passes = 0;
};
struct Buffer {
    std::string name;
    Section *section = nullptr;
    char end = 'L';
    int row = 0, col = 0;
};
struct Boundary {
    std::string name;
    Section *section = nullptr;
    char end = 'L';
};
struct Label {
    int row, col;
    std::string text;
};
struct Endpoint {
    EndKind kind = EndKind::Impassable;
    std::string name;
    Section *section = nullptr;
    Point *point = nullptr;
    bool common = false;
};
struct Layout {
    std::vector<std::unique_ptr<Section>> sections;
    std::vector<std::unique_ptr<Point>> points;
    std::vector<std::unique_ptr<Signal>> signals;
    std::vector<std::unique_ptr<Buffer>> buffers;
    std::vector<std::unique_ptr<Boundary>> boundaries;
    std::vector<Label> labels;
    std::map<std::string, Section *> sectionNames;
    std::map<std::string, Point *> pointNames;
    std::map<std::string, Signal *> signalNames;
    std::map<std::string, Buffer *> bufferNames;
    std::map<std::string, Boundary *> boundaryNames;
    std::map<std::pair<std::string, char>, Endpoint> ends;
    std::map<std::pair<std::string, Direction>, Signal *> signalAt;
    int height = 0, width = 0;
    Endpoint beyond(Section *, Direction) const;
    Signal *signal(Section *, Direction) const;
};
struct Requirement {
    Point *point;
    char position;
};
struct Route {
    std::string name, finish;
    Signal *start = nullptr;
    Direction direction = Direction::Up;
    RouteState state = RouteState::None;
    std::vector<Requirement> points, flank;
    std::vector<Section *> sections, overlap;
    std::vector<std::string> conflictNames;
    std::vector<Route *> conflicts;
    int approach = 0, releaseTime = -1, overlapCounter = 0;
    bool overlapLocked = false;
    std::set<Section *> passed;
    int requests = 0, grants = 0, uses = 0, cancels = 0, wait = 0, maxwait = 0, lockedTicks = 0;
    std::vector<Requirement> requirements() const;
};
struct Interlocking {
    Layout *layout = nullptr;
    std::vector<std::unique_ptr<Route>> routes;
    std::map<std::string, Route *> names;
    void lock(Route *);
    void unlockSection(Route *, Section *);
    void unlockOverlap(Route *);
    void release(Route *);
};
struct Stop {
    bool turn = false;
    Section *section = nullptr;
    int dwell = 0, scheduledArrival = 0, scheduledDeparture = 0, arrival = -1, departure = -1;
};
struct PathSection {
    Section *section;
    int start;
};
struct Train {
    std::string name;
    char symbol = 'a';
    int length = 0, acceleration = 0, deceleration = 0, maxSpeed = 0;
    Boundary *entry = nullptr, *exit = nullptr;
    int scheduledEntry = 0, entrySpeed = 0, actualEntry = -1, scheduledExit = 0, actualExit = -1;
    std::vector<Stop> stops;
    TrainState state = TrainState::Waiting;
    Direction direction = Direction::Up;
    std::vector<PathSection> path;
    int head = 0, speed = 0, nextStop = 0;
    bool dwelling = false;
    Stop *awaitDeparture = nullptr;
    bool emergency = false, crossed = false;
    int boundaryCoordinate = 0, distance = 0, recordedMax = 0, standing = 0, passes = 0;
    PathSection headSection() const;
    std::vector<PathSection> occupiedSections() const;
    Stop *stop();
};
struct TrainRequest {
    Train *train;
    Route *route;
    int time;
};
struct Safety {
    std::array<int, 4> checks{}, violations{};
    std::vector<std::string> records;
    void violation(int, int, const std::string &);
    void signalPassing(int, Train *, Signal *);
    void check(int, const Layout &, const Interlocking &);
    std::vector<std::string> lines() const;
};
std::vector<std::string> readLines(const std::string &);
std::vector<std::string> words(const std::string &);
std::vector<std::string> list(const std::string &);
std::string join(const std::vector<std::string> &, const std::string &);
Layout readLayout();
Interlocking readInterlocking(Layout &);
void readTrains(Layout &, Interlocking &, std::vector<std::unique_ptr<Train>> &,
                std::vector<TrainRequest> &);
int brakingDistance(int, int);
int selectSpeed(const Train &, int);
std::map<Signal *, Aspect> signalAspects(const Layout &, const Interlocking &);
std::string directionName(Direction);
std::string aspectName(Aspect);
std::string routeStateName(RouteState);
std::string trainStateName(TrainState);
