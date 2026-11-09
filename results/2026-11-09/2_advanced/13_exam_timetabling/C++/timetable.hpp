#pragma once
#include <algorithm>
#include <array>
#include <functional>
#include <map>
#include <numeric>
#include <optional>
#include <set>
#include <sstream>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

using Lines = std::vector<std::string>;
using Indices = std::vector<int>;
using Assignment = std::vector<int>;
template<class... Parts> std::string text(const Parts&... parts) {
    std::ostringstream stream;
    (stream << ... << parts);
    return stream.str();
}
template<class... Parts> void add(Lines& lines, const Parts&... parts) { lines.push_back(text(parts...)); }
struct Course { std::string id, name; int duration; Indices students; int size() const { return static_cast<int>(students.size()); } };
struct Student { std::string id; Indices courses; std::set<int> unavailable; };
struct Room { std::string id; int capacity; };
struct Placement { int course, room, first, last; };
struct Choice { int course, slot, saturation; };
struct AttemptRecord { int courses, deadEnds, failedCourse; };
struct Insertion { int course, slot, increase; };
struct Breakdown { std::array<int, 3> counts{}; int late = 0, total = 0; std::string str() const; };
struct StudentStats { std::array<int, 3> counts{}; int total = 0; Indices assigned; };
Lines readLines(const std::string& path);
void writeFiles(const std::vector<std::pair<std::string, Lines>>& files);
std::string fixedWidth(const std::string& label, const Lines& cells, int labelWidth, int cellWidth);
int roundedPercent(int part, int whole);
std::vector<Course> loadCourses(Lines& errors);
std::vector<Student> loadEnrolments(std::vector<Course>& courses, Lines& errors);
std::vector<Room> loadRooms(Lines& errors);
int findCourse(const std::vector<Course>& courses, const std::string& id);
int findStudent(const std::vector<Student>& students, const std::string& id);
Indices packingOrder(const std::vector<Course>& courses, Indices group);
std::optional<std::vector<Placement>> pack(const std::vector<Room>& rooms, const std::vector<Course>& courses, Indices group);
class ConflictGraph {
public:
    std::vector<Indices> shared;
    Indices vertices, degrees;
    ConflictGraph(const std::vector<Course>& courses, const std::vector<Student>& students);
    std::vector<Indices> components() const;
    Indices clique(Indices candidates) const;
    Indices kempeChain(const Assignment& assignment, int start, int home, int target) const;
};
bool reachable(const std::vector<std::pair<int, int>>& orders, int source, int target);
class Attempt {
    const ConflictGraph& graph;
    Indices pending;
    int limit;
    std::function<Indices(int, const Assignment&)> candidates;
public:
    int deadEnds = 0, deadEndCourse = -1;
    bool aborted = false;
    std::vector<Choice> choices;
    Attempt(const ConflictGraph& graph, Indices pending, int limit, std::function<Indices(int, const Assignment&)> candidates);
    bool search(Assignment& assignment);
    int saturation(int course, const Assignment& assignment) const;
};
int greedyNumbering(const ConflictGraph& graph, const Indices& order);
