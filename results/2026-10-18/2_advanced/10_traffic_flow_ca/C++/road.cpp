#include "traffic.hpp"
#include <algorithm>
#include <utility>

Segment::Segment(std::string id, std::string start, std::string end, int length, int lanes, int limit)
    : id(std::move(id)), start(std::move(start)), end(std::move(end)), length(length), lanes(lanes), limit(limit), cells(lanes,std::vector<int>(length)) {}
bool Segment::empty(int lane, int cell) const { return cells[lane - 1][cell] == 0; }
void Segment::put(int lane, int cell, int value) { cells[lane - 1][cell] = value; }
int Segment::free(int lane, int cell, int cap) const {
    int count = 0; while (count < cap && cell + count + 1 < length && empty(lane,cell + count + 1)) ++count; return count;
}
int Segment::first(int lane) const { for (int cell = 0; cell < length; ++cell) if (!empty(lane,cell)) return cell; return length; }
bool Segment::safe(int lane, int cell) const { for (int x = std::max(0,cell - limit); x <= cell; ++x) if (!empty(lane,x)) return false; return true; }
std::vector<int> Segment::numbers(int lane) const { std::vector<int> result; for (int value : cells[lane - 1]) if (value > 0) result.push_back(value); return result; }
std::string Segment::text(int lane, const std::vector<Vehicle*>& vehicles) const {
    std::string result; for (int value : cells[lane - 1]) result += value == 0 ? '.' : value < 0 ? '#' : static_cast<char>('0' + vehicles[value - 1]->speed); return result;
}
std::string Incident::update(int step) {
    std::string event;
    if (state == "active" && step > end) { state = "cleared"; segment->put(lane,cell,0); event = "INCIDENT_END"; }
    else if (state == "planned" && step > end) state = "cancelled";
    else if (state == "planned" && step >= start && segment->empty(lane,cell)) { state = "active"; segment->put(lane,cell,-1); activeStart = step; event = "INCIDENT_START"; }
    if (state == "active") activeEnd = step; return event;
}
