#include "timetable.hpp"

std::vector<Room> loadRooms(Lines& errors) {
    Lines lines = readLines("input/rooms.csv"); std::vector<Room> rooms; std::set<std::string> accepted;
    for (int i = 1; i < static_cast<int>(lines.size()); ++i) {
        const std::string& line = lines[i]; std::size_t comma = line.find(',');
        std::string id = line.substr(0, comma), capacityText = line.substr(comma + 1); int capacity = std::stoi(capacityText);
        if (accepted.count(id)) add(errors, "rooms.csv line ", i + 1, ": duplicate room ", id);
        else if (capacity < 1) add(errors, "rooms.csv line ", i + 1, ": bad capacity ", capacityText);
        else { accepted.insert(id); rooms.push_back({id, capacity}); }
    }
    std::sort(rooms.begin(), rooms.end(), [](const Room& a, const Room& b) { return std::tie(a.capacity, a.id) < std::tie(b.capacity, b.id); });
    return rooms;
}
Indices packingOrder(const std::vector<Course>& courses, Indices group) {
    std::sort(group.begin(), group.end(), [&](int a, int b) { return courses[a].size() != courses[b].size() ? courses[a].size() > courses[b].size() : a < b; });
    return group;
}
std::optional<std::vector<Placement>> pack(const std::vector<Room>& rooms, const std::vector<Course>& courses, Indices group) {
    Indices remaining, durations(rooms.size()); std::vector<Placement> result;
    for (const Room& room : rooms) remaining.push_back(room.capacity);
    for (int c : packingOrder(courses, std::move(group))) {
        const Course& course = courses[c]; int room = 0;
        while (room < static_cast<int>(rooms.size()) &&
               (remaining[room] < course.size() || (durations[room] && durations[room] != course.duration))) ++room;
        if (room == static_cast<int>(rooms.size())) return std::nullopt;
        int first = rooms[room].capacity - remaining[room] + 1;
        result.push_back({c, room, first, first + course.size() - 1});
        remaining[room] -= course.size(); durations[room] = course.duration;
    }
    return result;
}
