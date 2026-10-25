#pragma once
#include <array>
#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <vector>

using Integer = std::int64_t;
using Lines = std::vector<std::string>;
struct Minstd { Integer state; Integer draw(); };
int select(const std::vector<Integer>& weights, Integer value);
struct Segment;
struct Junction;
struct Vehicle;
struct Turn { Segment* target; Integer weight, vehicles = 0; };
struct BusStop { Segment* segment; int cell, dwell; Integer buses = 0; };
struct Segment {
    std::string id, start, end;
    int length, lanes, limit;
    std::vector<std::vector<int>> cells;
    Junction* junction = nullptr;
    std::vector<Turn> turns;
    BusStop* stop = nullptr;
    Integer entered = 0, vehicleSum = 0, speedSum = 0, maxVehicles = 0, greenSteps = 0, queueSum = 0, maxQueue = 0, failures = 0, passed = 0, blocked = 0;
    std::array<Integer, 3> changes{};
    Segment(std::string id, std::string start, std::string end, int length, int lanes, int limit);
    bool empty(int lane, int cell) const;
    void put(int lane, int cell, int value);
    int free(int lane, int cell, int limit) const;
    int first(int lane) const;
    bool safe(int lane, int cell) const;
    std::vector<int> numbers(int lane) const;
    std::string text(int lane, const std::vector<Vehicle*>& vehicles) const;
};
struct Incident {
    Segment* segment;
    int lane, cell;
    Integer start, end;
    std::string state = "planned";
    int activeStart = 0, activeEnd = 0;
    std::string update(int step);
};
struct VehicleClass { std::string name; int vmax; Integer weight; bool overtakes, stops; };
struct Vehicle {
    int number;
    const VehicleClass* kind;
    std::string source;
    int arrival, inserted = 0, exited = 0;
    std::string sink;
    Segment* segment = nullptr;
    int lane = 0, cell = 0, speed = 0, dwell = 0;
    Turn* turn = nullptr;
    Lines route;
    Integer steps = 0, distance = 0, stoppedSteps = 0, stopCount = 0, laneChanges = 0;
    std::set<std::string> completedStops;
    int maxSpeed() const;
    void place(Segment* target, int lane, int cell);
    void leave();
    bool headingForStop() const;
    int travelTime() const;
};
int randomSlowdown(int speed, int previous, Integer value, int dawdle, int stopped);
struct Phase { int duration; std::string token; std::set<std::string> greens; };
struct Junction {
    std::string node;
    int offset, cycle = 0;
    std::vector<Phase> phases;
    std::vector<Segment*> incoming;
    Junction(std::string node, int offset, const Lines& tokens);
    bool green(const std::string& segment, int step) const;
    Lines planLines() const;
};
std::string dec(Integer numerator, Integer denominator, int places);
std::string frac(Integer numerator, Integer denominator);
Integer percentile(const std::vector<Integer>& times, int q);
Lines histogramLines(const std::vector<Integer>& times, Integer width);
